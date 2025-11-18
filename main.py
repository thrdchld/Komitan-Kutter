import os
import re
import uuid
import shutil
import threading
import subprocess
import time
import zipfile
from pathlib import Path
from datetime import datetime
from typing import List, Tuple, Optional

# --- Kivy Imports ---
from kivy.app import App
from kivy.lang import Builder
from kivy.properties import StringProperty, NumericProperty, ListProperty
from kivy.uix.screenmanager import ScreenManager, Screen
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.popup import Popup
from kivy.clock import mainthread, Clock
from kivy.uix.filechooser import FileChooserListView
from kivy.uix.label import Label
from kivy.uix.button import Button
from kivy.uix.slider import Slider
from kivy.uix.textinput import TextInput
from kivy.uix.video import Video
from kivy.utils import platform

# --- KONFIGURASI ANDROID & FFMPEG ---
FFmpegKit = None
FFprobeKit = None
ReturnCode = None

if platform == 'android':
    try:
        from jnius import autoclass
        from android.permissions import request_permissions, Permission
        
        # Load FFmpeg-Kit Library
        FFmpegKit = autoclass('com.arthenica.ffmpegkit.FFmpegKit')
        FFprobeKit = autoclass('com.arthenica.ffmpegkit.FFprobeKit')
        ReturnCode = autoclass('com.arthenica.ffmpegkit.ReturnCode')
        FFmpegKitConfig = autoclass('com.arthenica.ffmpegkit.FFmpegKitConfig')
        FFmpegKitConfig.enableLogCallback(None) # Supaya tidak spam log
    except Exception as e:
        print(f"Error loading Android libs: {e}")

# --- CONFIG PATH ---
BASE = Path(__file__).parent.resolve()
ANDROID_DEFAULT = Path('/storage/emulated/0/Movies/KomitanKutter')

def get_output_dir():
    if platform == 'android':
        if not ANDROID_DEFAULT.exists():
            try:
                ANDROID_DEFAULT.mkdir(parents=True, exist_ok=True)
            except:
                pass
        return ANDROID_DEFAULT
    
    # Fallback untuk PC
    local_out = BASE / 'outputs'
    local_out.mkdir(parents=True, exist_ok=True)
    return local_out

OUTPUT_FOLDER = get_output_dir()
UPLOAD_FOLDER = BASE / 'uploads'
UPLOAD_FOLDER.mkdir(parents=True, exist_ok=True)

ALLOWED_EXT = {'.mp4', '.mov', '.mkv', '.avi', '.webm'}

# --- GLOBAL STATE ---
JOBS = {}
JOBS_LOCK = threading.Lock()


# --- UTILITIES ---
def parse_time_to_seconds(t: str) -> Optional[float]:
    if t is None: return None
    s = str(t).strip().replace(',', '.')
    if not s: return None
    if ':' in s:
        parts = s.split(':')
        try: parts_f = [float(p) for p in parts]
        except ValueError: return None
        parts_f = list(reversed(parts_f))
        multipliers = [1, 60, 3600]
        seconds = 0.0
        for i, val in enumerate(parts_f):
            if i >= len(multipliers): return None
            seconds += val * multipliers[i]
        return seconds
    else:
        try: return float(s)
        except ValueError: return None

def seconds_to_hhmmssms(sec: float) -> str:
    if sec is None: return ''
    ms = int(round((sec - int(sec)) * 1000))
    s = int(sec) % 60
    m = (int(sec) // 60) % 60
    h = int(sec) // 3600
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"

def parse_range_line(line: str) -> Optional[Tuple[float, float]]:
    if line is None: return None
    raw = line.strip().replace('\u2013', '-').replace('->', '-')
    separators = [' to ', ',', '\t', ' - ', '-', ' ']
    for sep in separators:
        if sep in raw:
            parts = raw.split(sep, 1)
            if len(parts) != 2: continue
            s, e = parse_time_to_seconds(parts[0]), parse_time_to_seconds(parts[1])
            if s is not None and e is not None: return (s, e)
    return None

# --- CORE LOGIC: GET DURATION ---
def get_duration(input_file: str) -> Optional[float]:
    # Android: Pakai FFprobeKit
    if platform == 'android' and FFprobeKit:
        try:
            session = FFprobeKit.getMediaInformation(input_file)
            info = session.getMediaInformation()
            if info:
                return float(info.getDuration())
        except:
            return None
    
    # PC: Pakai subprocess ffprobe
    try:
        cmd = ['ffprobe', '-v', 'error', '-show_entries', 'format=duration', 
               '-of', 'default=noprint_wrappers=1:nokey=1', input_file]
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, timeout=8)
        return float(out.decode().strip())
    except:
        return None

# --- CORE LOGIC: WORKER ---
def start_cut_job(session: str, upload_entry: dict):
    saved_path = Path(upload_entry['path'])
    ext = saved_path.suffix.lower()
    job = JOBS.get(session)
    if not job: return

    # Buat folder output
    date_str = datetime.now().strftime('%Y%m%d-%H%M%S')
    run_folder = OUTPUT_FOLDER / f"{date_str}-{saved_path.stem}"
    run_folder.mkdir(parents=True, exist_ok=True)
    
    with JOBS_LOCK:
        job['run_folders'] = [str(run_folder)]

    ranges = upload_entry.get('ranges', [])
    total = len(ranges)

    for idx, (s, e) in enumerate(ranges, start=1):
        if job.get('cancel'): break
        
        out_name = f"part_{idx}{ext}"
        out_path = run_folder / out_name
        
        # Update status UI
        with JOBS_LOCK:
            job['done'] = idx - 1 # Sedang mengerjakan ini
            
        print(f"[Worker] Cutting {idx}/{total}: {out_path}")

        # LOGIKA UTAMA: PILIH ENGINE (ANDROID VS PC)
        if platform == 'android' and FFmpegKit:
            # Android Command (String)
            cmd = f'-y -ss {s} -to {e} -i "{saved_path}" -c copy "{out_path}"'
            print(f"[Worker Android] Exec: {cmd}")
            ff_session = FFmpegKit.execute(cmd)
            success = ReturnCode.isSuccess(ff_session.getReturnCode())
            if not success:
                err = ff_session.getLogsAsString()
                with JOBS_LOCK: job['errors'].append(f"Seg {idx} Fail: {err[:200]}")
        else:
            # PC Command (List)
            cmd = ['ffmpeg', '-y', '-ss', str(s), '-to', str(e), 
                   '-i', str(saved_path), '-c', 'copy', str(out_path)]
            print(f"[Worker PC] Exec: {cmd}")
            try:
                subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                success = True
            except Exception as e:
                success = False
                with JOBS_LOCK: job['errors'].append(str(e))

        if success:
            with JOBS_LOCK: job['files'].append(str(out_path))
            
    # Selesai
    with JOBS_LOCK:
        job['done'] = total
        job['status'] = 'finished'


# --- KIVY UI (KV LANG) ---
KV = r"""
#:import os os
#:import platform kivy.utils.platform

ScreenManager:
    id: sm
    IndexScreen:
    PreviewScreen:
    ResultsScreen:

<IndexScreen>:
    name: 'index'
    BoxLayout:
        orientation: 'vertical'
        padding: dp(20)
        spacing: dp(15)
        canvas.before:
            Color:
                rgba: 0.95, 0.95, 0.97, 1
            Rectangle:
                pos: self.pos
                size: self.size

        Label:
            text: 'Komitan Kutter'
            font_size: '24sp'
            bold: True
            color: 0.1, 0.1, 0.1, 1
            size_hint_y: None
            height: dp(40)

        # Area Pilih File
        BoxLayout:
            orientation: 'vertical'
            size_hint_y: None
            height: dp(100)
            canvas.before:
                Color:
                    rgba: 1, 1, 1, 1
                RoundedRectangle:
                    pos: self.pos
                    size: self.size
                    radius: [10,]
            padding: dp(10)
            
            Button:
                id: pick_btn
                text: root.pick_btn_text
                background_normal: ''
                background_color: 0.2, 0.6, 1, 1
                on_release: root.open_filechooser()
            
            Label:
                text: root.picked_filename
                color: 0.4, 0.4, 0.4, 1
                font_size: '12sp'
                text_size: self.size
                halign: 'center'
                valign: 'middle'

        # Input Timestamp
        Label:
            text: 'Masukkan Timestamp (Satu per baris)\nContoh: 00:05 - 00:10'
            color: 0.2, 0.2, 0.2, 1
            size_hint_y: None
            height: dp(40)
            font_size: '12sp'

        TextInput:
            id: ts_input
            hint_text: '00:00:05 - 00:00:20\n00:01:15 - 00:01:30'
            multiline: True
            background_color: 1, 1, 1, 1
            foreground_color: 0, 0, 0, 1
            padding: dp(10)

        Button:
            text: 'MULAI POTONG VIDEO'
            size_hint_y: None
            height: dp(60)
            background_normal: ''
            background_color: 0, 0.7, 0.3, 1
            bold: True
            on_release: root.on_preview()

        Label:
            text: root.short_output
            color: 0.5, 0.5, 0.5, 1
            font_size: '11sp'
            size_hint_y: None
            height: dp(30)

<PreviewScreen>:
    name: 'preview'
    BoxLayout:
        orientation: 'vertical'
        padding: dp(10)
        spacing: dp(10)
        
        Label:
            text: 'Preview & Konfirmasi'
            font_size: '18sp'
            bold: True
            size_hint_y: None
            height: dp(40)

        ScrollView:
            GridLayout:
                id: seg_container
                cols: 1
                size_hint_y: None
                height: self.minimum_height
                spacing: dp(10)

        BoxLayout:
            size_hint_y: None
            height: dp(50)
            spacing: dp(10)
            Button:
                text: 'Batal'
                background_color: 0.8, 0.2, 0.2, 1
                on_release: root.manager.current = 'index'
            Button:
                text: 'PROSES SEKARANG'
                background_color: 0.2, 0.6, 1, 1
                on_release: root.start_process()

<ResultsScreen>:
    name: 'results'
    BoxLayout:
        orientation: 'vertical'
        padding: dp(30)
        spacing: dp(20)
        canvas.before:
            Color:
                rgba: 0.95, 0.95, 0.97, 1
            Rectangle:
                pos: self.pos
                size: self.size

        Label:
            text: 'Sedang Memproses...'
            font_size: '22sp'
            color: 0.1, 0.1, 0.1, 1
            size_hint_y: None
            height: dp(50)

        ProgressBar:
            id: prog
            max: 100
            value: 0
            size_hint_y: None
            height: dp(20)

        Label:
            id: count_lbl
            text: 'Menunggu...'
            color: 0.3, 0.3, 0.3, 1

        Label:
            id: out_path
            text: ''
            font_size: '12sp'
            color: 0.4, 0.4, 0.4, 1
            halign: 'center'

        Button:
            id: btn_finish
            text: 'Selesai / Kembali'
            disabled: True
            size_hint_y: None
            height: dp(50)
            background_color: 0.2, 0.6, 1, 1
            on_release: root.new_job()
"""

# --- UI IMPLEMENTATION ---

class SegmentWidget(BoxLayout):
    # Widget untuk menampilkan 1 baris potongan di halaman Preview
    def __init__(self, idx, s, e, duration, **kwargs):
        super().__init__(orientation='vertical', size_hint_y=None, height=120, padding=10, **kwargs)
        # Background Putih
        with self.canvas.before:
            from kivy.graphics import Color, RoundedRectangle
            Color(1, 1, 1, 1)
            RoundedRectangle(pos=self.pos, size=self.size, radius=[10,])
        self.bind(pos=self.update_bg, size=self.update_bg)
        
        self.s = s
        self.e = e
        
        # Label Info
        self.add_widget(Label(text=f"[b]Bagian #{idx}[/b]", markup=True, color=(0,0,0,1), size_hint_y=0.3))
        
        # Row Edit
        row = BoxLayout(spacing=10)
        self.txt_s = TextInput(text=seconds_to_hhmmssms(s), multiline=False)
        self.txt_e = TextInput(text=seconds_to_hhmmssms(e), multiline=False)
        row.add_widget(Label(text="Start:", color=(0,0,0,1), size_hint_x=0.3))
        row.add_widget(self.txt_s)
        row.add_widget(Label(text="End:", color=(0,0,0,1), size_hint_x=0.3))
        row.add_widget(self.txt_e)
        self.add_widget(row)

    def update_bg(self, *args):
        self.canvas.before.children[1].pos = self.pos
        self.canvas.before.children[1].size = self.size

    def get_range(self):
        s = parse_time_to_seconds(self.txt_s.text)
        e = parse_time_to_seconds(self.txt_e.text)
        return (s, e)

class IndexScreen(Screen):
    picked_path = StringProperty('')
    picked_filename = StringProperty('')
    pick_btn_text = StringProperty('Pilih Video (Klik disini)')
    short_output = StringProperty(f"Output: {OUTPUT_FOLDER}")

    def open_filechooser(self):
        # Setup path awal supaya user tidak bingung di Android
        init_path = str(ANDROID_DEFAULT) if platform == 'android' else str(BASE)
        if platform == 'android' and not os.path.exists(init_path):
             init_path = '/storage/emulated/0/' # Root internal storage

        content = FileChooserListView(path=init_path, filters=['*.mp4', '*.mkv', '*.avi', '*.mov'])
        
        btn_select = Button(text="PILIH FILE INI", size_hint_y=None, height=50, background_color=(0,0.8,0,1))
        layout = BoxLayout(orientation='vertical')
        layout.add_widget(content)
        layout.add_widget(btn_select)
        
        popup = Popup(title="Pilih Video", content=layout, size_hint=(0.9, 0.9))
        
        def select(*args):
            if content.selection:
                self.set_file(content.selection[0])
                popup.dismiss()
        
        btn_select.bind(on_release=select)
        popup.open()

    def set_file(self, path):
        self.picked_path = path
        self.picked_filename = Path(path).name
        self.pick_btn_text = "Ganti Video"

    def on_preview(self):
        if not self.picked_path:
            self.show_error("Pilih file video dulu!")
            return
        
        txt = self.ids.ts_input.text
        ranges = []
        for line in txt.splitlines():
            r = parse_range_line(line)
            if r and r[1] > r[0]:
                ranges.append(r)
        
        if not ranges:
            self.show_error("Timestamp tidak valid!\nGunakan format: 00:00:05 - 00:00:10")
            return

        # Pindah ke preview
        app = App.get_running_app()
        app.temp_data = {
            'path': self.picked_path,
            'ranges': ranges,
            'duration': get_duration(self.picked_path) or 0
        }
        self.manager.current = 'preview'

    def show_error(self, msg):
        Popup(title='Error', content=Label(text=msg), size_hint=(0.8, 0.4)).open()

class PreviewScreen(Screen):
    def on_enter(self):
        self.ids.seg_container.clear_widgets()
        app = App.get_running_app()
        data = getattr(app, 'temp_data', {})
        
        if not data: return

        for i, (s, e) in enumerate(data['ranges'], start=1):
            w = SegmentWidget(i, s, e, data['duration'])
            self.ids.seg_container.add_widget(w)

    def start_process(self):
        # Collect data final
        final_ranges = []
        for child in self.ids.seg_container.children:
            if isinstance(child, SegmentWidget):
                s, e = child.get_range()
                if s is not None and e is not None and e > s:
                    final_ranges.insert(0, (s, e)) # Kivy child order reversed
        
        if not final_ranges: return

        # Buat Job
        app = App.get_running_app()
        session = uuid.uuid4().hex
        
        JOBS[session] = {
            'uploads': [{
                'path': app.temp_data['path'],
                'ranges': final_ranges
            }],
            'total': len(final_ranges),
            'done': 0,
            'files': [], 'errors': [],
            'status': 'running'
        }
        
        # Jalankan Worker
        threading.Thread(target=start_cut_job, args=(session, JOBS[session]['uploads'][0]), daemon=True).start()
        
        # Pindah screen
        res = self.manager.get_screen('results')
        res.session_id = session
        res.start_watching()
        self.manager.current = 'results'

class ResultsScreen(Screen):
    session_id = StringProperty('')
    
    def start_watching(self):
        self.ids.btn_finish.disabled = True
        self.ids.prog.value = 0
        self.event = Clock.schedule_interval(self.update, 1.0)

    def update(self, dt):
        if not self.session_id or self.session_id not in JOBS: return
        
        job = JOBS[self.session_id]
        
        # Update Progress UI
        total = job.get('total', 1)
        done = job.get('done', 0)
        pct = (done / total) * 100
        
        self.ids.prog.value = pct
        self.ids.count_lbl.text = f"Selesai: {done} dari {total} bagian"
        
        if job['status'] == 'finished':
            self.finish_job(job)
            return False # Stop clock

    def finish_job(self, job):
        self.ids.prog.value = 100
        
        if job['errors']:
            self.ids.count_lbl.text = f"Selesai dengan {len(job['errors'])} error."
            self.ids.out_path.text = "Cek log untuk detail."
        else:
            self.ids.count_lbl.text = "BERHASIL!"
            # Ambil folder dari file pertama
            if job['files']:
                folder = Path(job['files'][0]).parent
                self.ids.out_path.text = f"Disimpan di:\n{folder}"
            
        self.ids.btn_finish.disabled = False

    def new_job(self):
        self.manager.current = 'index'


class KomitanKutterApp(App):
    def build(self):
        self.request_permissions()
        return Builder.load_string(KV)

    def request_permissions(self):
        if platform == 'android':
            from android.permissions import request_permissions, Permission
            request_permissions([
                Permission.READ_EXTERNAL_STORAGE,
                Permission.WRITE_EXTERNAL_STORAGE
            ])

if __name__ == '__main__':
    KomitanKutterApp().run()