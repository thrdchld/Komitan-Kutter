import os
import re
import uuid
import json
import time
import zipfile
import threading
from pathlib import Path
from datetime import datetime
from typing import List, Tuple, Optional

# --- Kivy Imports ---
from kivy.app import App
from kivy.lang import Builder
from kivy.uix.screenmanager import ScreenManager, Screen
from kivy.properties import ObjectProperty, StringProperty, NumericProperty
from kivy.clock import mainthread # PENTING untuk update UI dari thread
from kivy.utils import platform # Untuk mendeteksi Android

# --- Kustomisasi Android (pyjnius) ---
# Ini adalah "telepon" untuk memanggil spesialis ffmpeg
try:
    from jnius import autoclass
    FFmpegKit = autoclass('com.arthenica.ffmpegkit.FFmpegKit')
    FFprobeKit = autoclass('com.arthenica.ffmpegkit.FFprobeKit')
    ReturnCode = autoclass('com.arthenica.ffmpegkit.ReturnCode')
    FFmpegKitConfig = autoclass('com.arthenica.ffmpegkit.FFmpegKitConfig')
    
    # Nonaktifkan log default agar tidak spam
    FFmpegKitConfig.enableLogCallback(None)
    print("[main.py] pyjnius autoclass untuk ffmpeg-kit berhasil dimuat.")
except Exception as e:
    print(f"[main.py] PENTING: Gagal memuat autoclass pyjnius. Error: {e}")
    FFmpegKit = None
    FFprobeKit = None
    ReturnCode = None
# --- Akhir Kustomisasi ---


# -------- Config (Dipindah dari service.py) --------
BASE = Path(os.path.dirname(__file__)).resolve() # Path Kivy sedikit beda

ANDROID_DEFAULT = Path('/storage/emulated/0/Movies/Komitan Kutter')
try:
    # Cek platform untuk path yang benar
    if platform == 'android':
        ANDROID_DEFAULT.mkdir(parents=True, exist_ok=True)
        DEFAULT_OUTPUT_PARENT = ANDROID_DEFAULT
        print(f"[main.py] Mode Android. Output di: {DEFAULT_OUTPUT_PARENT}")
    else:
        DEFAULT_OUTPUT_PARENT = BASE / 'outputs'
        DEFAULT_OUTPUT_PARENT.mkdir(parents=True, exist_ok=True)
        print(f"[main.py] Mode Non-Android. Output di: {DEFAULT_OUTPUT_PARENT}")
except Exception:
    DEFAULT_OUTPUT_PARENT = BASE / 'outputs'
    DEFAULT_OUTPUT_PARENT.mkdir(parents=True, exist_ok=True)
    print(f"[main.py] Fallback. Output di: {DEFAULT_OUTPUT_PARENT}")

UPLOAD_FOLDER = BASE / 'uploads' # Tidak terpakai di versi ini, tapi aman
OUTPUT_FOLDER = DEFAULT_OUTPUT_PARENT
ALLOWED_EXT = {'.mp4', '.mov', '.mkv', '.avi', '.webm'}


# -------- Utilities (SEMUA DISALIN dari service.py) --------
# Ini adalah "resep" Anda yang kita pakai ulang
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
    raw = line.strip()
    if not raw: return None
    raw = raw.replace('\u2013', '-').replace('\u2014', '-').replace('\u2192', '-').replace('->', '-')
    separators = [' to ', ',', '\t', ' - ', '-', ' ']
    for sep in separators:
        if sep in raw:
            parts = raw.split(sep, 1)
            if len(parts) != 2: continue
            s, e = parse_time_to_seconds(parts[0]), parse_time_to_seconds(parts[1])
            if s is not None and e is not None: return (s, e)
    tokens = raw.split()
    if len(tokens) >= 2:
        s, e = parse_time_to_seconds(tokens[0]), parse_time_to_seconds(tokens[1])
        if s is not None and e is not None: return (s, e)
    return None

def build_ffmpeg_cmd_string(input_file: str, start: float, end: float, out_path: str) -> str:
    abs_input = str(Path(input_file).resolve())
    abs_output = str(Path(out_path).resolve())
    return f'-y -ss {start} -to {end} -i "{abs_input}" -c copy -map 0 "{abs_output}"'

def get_duration(input_file: str) -> Optional[float]:
    if not FFprobeKit or not ReturnCode: return None
    abs_input = str(Path(input_file).resolve())
    try:
        session = FFprobeKit.getMediaInformation(abs_input)
        if ReturnCode.isSuccess(session.getReturnCode()):
            duration_str = session.getMediaInformation().getDuration()
            return float(duration_str) if duration_str else None
        else:
            print(f"[main.py] ffprobe gagal: {session.getLogsAsString()}")
            return None
    except Exception as e:
        print(f"[main.py] Exception di get_duration: {e}")
        return None

def _find_next_index(target_dir: Path, ext: str) -> int:
    maxn = 0
    pat = re.compile(r'^(\d+)' + re.escape(ext) + r'$')
    if not target_dir.exists(): return 1
    for f in target_dir.iterdir():
        if f.is_file():
            m = pat.match(f.name)
            if m:
                try: maxn = max(maxn, int(m.group(1)))
                except Exception: pass
    return maxn + 1
# -------- Akhir dari Utilities --------


# -------- Kivy UI Screens (Pengganti HTML) --------

# Ini adalah Halaman 1 (Index)
class IndexScreen(Screen):
    # Ini menghubungkan Python ke widget di string KV
    video_path_input = ObjectProperty(None)
    timestamps_input = ObjectProperty(None)
    status_label = ObjectProperty(None)
    start_button = ObjectProperty(None)

    def do_cut(self):
        print("[IndexScreen] Tombol 'Mulai Potong' ditekan.")
        self.status_label.text = "Menganalisa input..."
        self.start_button.disabled = True

        video_path = self.video_path_input.text.strip()
        timestamps_text = self.timestamps_input.text.strip()

        # 1. Validasi Input
        if not video_path or not timestamps_text:
            self.status_label.text = "[ERROR] Path video dan timestamp harus diisi."
            self.start_button.disabled = False
            return

        video_file = Path(video_path)
        if not video_file.exists():
            self.status_label.text = f"[ERROR] File tidak ditemukan: {video_path}"
            self.start_button.disabled = False
            return
            
        ext = video_file.suffix.lower()
        if ext not in ALLOWED_EXT:
            self.status_label.text = f"[ERROR] Ekstensi {ext} tidak didukung."
            self.start_button.disabled = False
            return

        # 2. Parse Timestamps
        ranges = []
        bad_lines = []
        for i, line in enumerate(timestamps_text.splitlines(), start=1):
            parsed = parse_range_line(line)
            if parsed and parsed[1] > parsed[0]:
                ranges.append(parsed)
            elif line.strip():
                bad_lines.append(i)
        
        if not ranges:
            self.status_label.text = "[ERROR] Tidak ada timestamp yang valid."
            self.start_button.disabled = False
            return
            
        print(f"[IndexScreen] Ditemukan {len(ranges)} range valid.")
        
        # 3. Dapatkan Durasi Video (ini bisa lambat, tapi kita tunggu)
        duration = get_duration(video_path)
        if duration is None:
            self.status_label.text = "[ERROR] Gagal membaca durasi video. Cek file."
            self.start_button.disabled = False
            return
            
        print(f"[IndexScreen] Durasi video: {duration} detik.")

        # 4. Siapkan Job dan pindah layar
        app = App.get_running_app()
        app.job_config = {
            'video_path': video_file, # Kirim sebagai objek Path
            'video_ext': ext,
            'ranges': ranges,
            'total_jobs': len(ranges),
            'date_str': datetime.now().strftime('%Y%m%d'),
            'start_time_str': datetime.now().strftime('%H.%M.%S')
        }
        
        # Reset UI
        self.status_label.text = "Siap untuk memotong!"
        self.start_button.disabled = False
        
        # Pindah ke layar 'results'
        self.manager.current = 'results'


# Ini adalah Halaman 2 (Results/Progress)
class ResultsScreen(Screen):
    progress_bar = ObjectProperty(None)
    status_label = ObjectProperty(None)
    done_button = ObjectProperty(None)
    
    output_folder_path = StringProperty("") # Untuk menyimpan path hasil

    def on_pre_enter(self, *args):
        # Fungsi ini berjalan TEPAT SEBELUM layar ditampilkan
        print("[ResultsScreen] Layar ditampilkan, memulai job.")
        
        # Reset Tampilan
        self.progress_bar.value = 0
        self.status_label.text = "Mempersiapkan job..."
        self.done_button.disabled = True
        self.output_folder_path = ""
        
        # Ambil config dari App
        app = App.get_running_app()
        if not app.job_config:
            self.status_label.text = "[ERROR] Tidak ada konfigurasi job. Kembali."
            self.done_button.disabled = False
            return

        # JALANKAN JOB DI THREAD TERPISAH
        # Ini PENTING agar UI tidak freeze
        threading.Thread(target=app.run_the_job, daemon=True).start()

    def go_to_index(self):
        # Kembali ke halaman awal
        self.manager.current = 'index'
        

# --- [ INI ADALAH BAGIAN UTAMA APLIKASI ] ---
class KutterApp(App):
    job_config = {} # Tempat menyimpan data (pengganti 'session')

    def build(self):
        # Kivy akan mem-build UI dari string di bawah ini
        return Builder.load_string(KV_STRING)

    # Ini adalah FUNGSI UTAMA yang berjalan di background thread
    def run_the_job(self):
        print("[AppThread] Thread job dimulai.")
        try:
            cfg = self.job_config
            video_path = cfg['video_path']
            ext = cfg['video_ext']
            ranges = cfg['ranges']
            total = cfg['total_jobs']

            # Tentukan folder output
            base = OUTPUT_FOLDER / f"{cfg['date_str']}-{video_path.stem}"
            run_folder = base / f"StartKutter-{cfg['start_time_str']}"
            run_folder.mkdir(parents=True, exist_ok=True)
            
            output_folder_str = str(run_folder)
            print(f"[AppThread] Folder output: {output_folder_str}")
            
            # Kirim update path ke UI
            self.update_output_path(output_folder_str)

            idx = _find_next_index(run_folder, ext)
            
            for i, (start, end) in enumerate(ranges, start=1):
                # Update UI (Status)
                self.update_progress(f"Memotong segmen {i} dari {total}...", (i / total) * 100)
                
                out_path = run_folder / f"{idx}{ext}"
                
                # Buat perintah ffmpeg
                cmd_string = build_ffmpeg_cmd_string(str(video_path), start, end, str(out_path))
                print(f"[AppThread] Menjalankan: {cmd_string}")
                
                # Eksekusi!
                if not FFmpegKit:
                    self.update_progress("[ERROR] FFmpegKit tidak ditemukan!", 0)
                    break
                    
                session = FFmpegKit.execute(cmd_string)
                
                if ReturnCode.isSuccess(session.getReturnCode()):
                    print(f"[AppThread] Sukses membuat {out_path}")
                    idx += 1
                else:
                    print(f"[AppThread] GAGAL segmen {i}: {session.getLogsAsString()}")
                    # Kita bisa tambahkan error handling di sini
                    self.update_progress(f"[ERROR] Gagal di segmen {i}. Lanjut...", (i / total) * 100)
                    idx += 1 # Tetap lanjut agar index tidak bentrok

            # Selesai
            print("[AppThread] Semua job selesai.")
            self.job_finished(output_folder_str)

        except Exception as e:
            print(f"[AppThread] Terjadi EXCEPTION: {e}")
            self.job_finished(f"Terjadi Error: {e}")

    @mainthread # Decorator ini WAJIB untuk update UI dari thread
    def update_progress(self, text, progress_value):
        # Fungsi ini aman dipanggil dari thread manapun
        if not hasattr(self, 'root') or not self.root:
            return # UI belum siap
        results_screen = self.root.get_screen('results')
        if results_screen:
            results_screen.status_label.text = text
            results_screen.progress_bar.value = progress_value

    @mainthread
    def update_output_path(self, path_text):
        if not hasattr(self, 'root') or not self.root:
            return # UI belum siap
        results_screen = self.root.get_screen('results')
        if results_screen:
            # Ubah path agar lebih ramah dibaca
            friendly_path = path_text.replace('/storage/emulated/0/', 'Internal Storage/')
            results_screen.output_folder_path = f"File disimpan di:\n{friendly_path}"

    @mainthread
    def job_finished(self, final_message):
        if not hasattr(self, 'root') or not self.root:
            return # UI belum siap
        results_screen = self.root.get_screen('results')
        if results_screen:
            if "Error" not in final_message:
                results_screen.status_label.text = "SEMUA SELESAI!"
                self.update_output_path(final_message) # Tampilkan path lagi
            else:
                results_screen.status_label.text = final_message
            
            results_screen.progress_bar.value = 100
            results_screen.done_button.disabled = False # Aktifkan tombol 'Selesai'


# --- [ INI ADALAH TAMPILAN UI (Pengganti HTML) ] ---
# Ini adalah bahasa Kivy (KV Language)
KV_STRING = """
ScreenManager:
    IndexScreen:
        name: 'index'
    ResultsScreen:
        name: 'results'

<IndexScreen>:
    # Menghubungkan widget ke variabel Python
    video_path_input: video_path
    timestamps_input: timestamps
    status_label: status_label
    start_button: start_button

    BoxLayout:
        orientation: 'vertical'
        padding: '20dp'
        spacing: '10dp'

        Label:
            text: 'Komitan Kutter'
            font_size: '24sp'
            halign: 'center'
            size_hint_y: None
            height: self.texture_size[1]

        Label:
            text: 'Masukkan path video (mis: /storage/emulated/0/DCIM/video.mp4)'
            font_size: '12sp'
            size_hint_y: None
            height: self.texture_size[1]
            
        TextInput:
            id: video_path
            text: '/storage/emulated/0/Download/video_asli.mp4' # Default value
            multiline: False
            font_size: '14sp'
            size_hint_y: None
            height: '40dp'

        Label:
            text: 'Masukkan Timestamps (satu per baris)'
            font_size: '12sp'
            size_hint_y: None
            height: self.texture_size[1]

        TextInput:
            id: timestamps
            hint_text: '00:00:05 - 00:00:10\\n00:00:15 - 00:00:20'
            multiline: True
            font_size: '14sp'

        Label:
            id: status_label
            text: 'Status: Menunggu input...'
            font_size: '12sp'
            size_hint_y: None
            height: self.texture_size[1]
            color: (1, 0.2, 0.2, 1) # Merah untuk error

        Button:
            id: start_button
            text: 'Mulai Potong Video'
            font_size: '18sp'
            size_hint_y: None
            height: '50dp'
            background_color: (0, 0.5, 1, 1)
            on_press: root.do_cut() # Memanggil fungsi Python

<ResultsScreen>:
    # Menghubungkan widget ke variabel Python
    progress_bar: progress_bar
    status_label: status_label
    done_button: done_button

    BoxLayout:
        orientation: 'vertical'
        padding: '20dp'
        spacing: '20dp'
        
        Label:
            text: 'Sedang Bekerja...'
            font_size: '24sp'
            size_hint_y: 0.2
            
        Label:
            id: status_label
            text: 'Mempersiapkan...'
            font_size: '14sp'
            size_hint_y: 0.3
            
        ProgressBar:
            id: progress_bar
            value: 0
            max: 100
            size_hint_y: None
            height: '20dp'

        Label:
            # Ini akan diisi oleh @mainthread update_output_path
            text: root.output_folder_path 
            font_size: '12sp'
            halign: 'center'
            size_hint_y: 0.3

        Button:
            id: done_button
            text: 'Selesai (Potong Video Baru)'
            font_size: '18sp'
            size_hint_y: None
            height: '50dp'
            disabled: True # Mulai dalam keadaan non-aktif
            on_press: root.go_to_index()
"""


# --- [ Mulai Aplikasi ] ---
if __name__ == '__main__':
    KutterApp().run()