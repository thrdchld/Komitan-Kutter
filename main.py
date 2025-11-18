import os
import re
import threading
from pathlib import Path
from datetime import datetime
from typing import List, Tuple, Optional

# --- Kivy Imports ---
from kivy.app import App
from kivy.lang import Builder
from kivy.uix.screenmanager import ScreenManager, Screen
from kivy.properties import ObjectProperty, StringProperty
from kivy.clock import mainthread
from kivy.utils import platform

# --- IMPOR FFmpeg (Hanya jika di Android) ---
FFmpegKit = None
ReturnCode = None

if platform == 'android':
    try:
        from jnius import autoclass
        # Meminta izin storage saat aplikasi mulai
        from android.permissions import request_permissions, Permission
        request_permissions([Permission.READ_EXTERNAL_STORAGE, Permission.WRITE_EXTERNAL_STORAGE])
        
        FFmpegKit = autoclass('com.arthenica.ffmpegkit.FFmpegKit')
        ReturnCode = autoclass('com.arthenica.ffmpegkit.ReturnCode')
        print("[Main] FFmpegKit berhasil dimuat via pyjnius.")
    except Exception as e:
        print(f"[Main] Error loading FFmpegKit/Permissions: {e}")
else:
    print("[Main] Berjalan di Desktop (Simulasi Mode)")


# --- CONFIG PATH ---
# Di Android 10+, kita sebaiknya menulis ke folder internal app dulu,
# atau folder publik jika izin diberikan.
ANDROID_DIR = Path('/storage/emulated/0/Movies/KomitanKutter')

def get_output_dir():
    if platform == 'android':
        if not ANDROID_DIR.exists():
            try:
                ANDROID_DIR.mkdir(parents=True, exist_ok=True)
            except:
                pass # Izin mungkin belum diberikan
        return ANDROID_DIR
    return Path('outputs')

ALLOWED_EXT = {'.mp4', '.mov', '.mkv', '.avi'}

# --- UTILITIES (Fungsi Pemotong) ---
def parse_time(t_str):
    # Mengubah "00:00:05" atau "5.5" menjadi float detik
    try:
        parts = str(t_str).strip().replace(',', '.').split(':')
        if len(parts) == 1: return float(parts[0])
        if len(parts) == 2: return float(parts[0])*60 + float(parts[1])
        if len(parts) == 3: return float(parts[0])*3600 + float(parts[1])*60 + float(parts[2])
    except:
        return None
    return None

def build_cmd(video_in, start, end, video_out):
    # Membuat perintah FFmpeg
    # -y: Overwrite
    # -ss: Start time
    # -to: End time
    # -c copy: Copy codec (sangat cepat, tanpa re-encode)
    return f'-y -ss {start} -to {end} -i "{video_in}" -c copy "{video_out}"'

def get_duration_simple(video_path):
    # Fungsi dummy untuk durasi (karena ffprobe ribet via pyjnius tanpa setup extra)
    # Kita asumsikan user tahu time range-nya valid.
    return 0.0 


# --- UI SCREEN ---
class IndexScreen(Screen):
    path_input = ObjectProperty(None)
    time_input = ObjectProperty(None)
    status_lbl = ObjectProperty(None)

    def do_cut(self):
        video_path = self.path_input.text.strip()
        time_txt = self.time_input.text.strip()
        
        if not video_path or not os.path.exists(video_path):
            self.status_lbl.text = "Error: File video tidak ditemukan!"
            return
            
        # Parsing simpel: Baris 1 = Start, Baris 2 = End (atau dipisah spasi/dash)
        # Format yang diharapkan user: "00:05 - 00:10"
        ranges = []
        for line in time_txt.splitlines():
            parts = line.replace('-', ' ').split()
            if len(parts) >= 2:
                s = parse_time(parts[0])
                e = parse_time(parts[1])
                if s is not None and e is not None and e > s:
                    ranges.append((s, e))
        
        if not ranges:
            self.status_lbl.text = "Error: Format waktu salah (Gunakan: 00:05 - 00:10)"
            return

        self.manager.current = 'results'
        # Jalankan di background thread
        threading.Thread(target=self.run_ffmpeg, args=(video_path, ranges)).start()

    def run_ffmpeg(self, v_in, ranges):
        app = App.get_running_app()
        out_dir = get_output_dir()
        out_dir.mkdir(parents=True, exist_ok=True)
        
        res_screen = self.manager.get_screen('results')
        total = len(ranges)
        
        for i, (start, end) in enumerate(ranges, start=1):
            fname = f"potongan_{i}_{datetime.now().strftime('%H%M%S')}.mp4"
            v_out = str(out_dir / fname)
            
            msg = f"Memotong bagian {i}/{total}..."
            self.update_ui(res_screen, msg, int((i-1)/total*100))
            
            cmd = build_cmd(v_in, start, end, v_out)
            print(f"Executing: {cmd}")
            
            if platform == 'android' and FFmpegKit:
                session = FFmpegKit.execute(cmd)
                if ReturnCode.isSuccess(session.getReturnCode()):
                    print(f"Sukses: {v_out}")
                else:
                    print(f"Gagal: {session.getLogsAsString()}")
            else:
                # Simulasi di PC (Hanya print)
                time.sleep(1) 
                print("Simulasi sukses (bukan Android).")

        self.update_ui(res_screen, f"Selesai! Cek folder:\n{out_dir}", 100, True)

    @mainthread
    def update_ui(self, screen, txt, val, enable_btn=False):
        screen.status_lbl.text = txt
        screen.prog_bar.value = val
        if enable_btn:
            screen.back_btn.disabled = False


class ResultsScreen(Screen):
    status_lbl = ObjectProperty(None)
    prog_bar = ObjectProperty(None)
    back_btn = ObjectProperty(None)
    
    def go_back(self):
        self.manager.current = 'index'


class KutterApp(App):
    def build(self):
        return Builder.load_string(KV_CODE)

KV_CODE = """
ScreenManager:
    IndexScreen:
        name: 'index'
    ResultsScreen:
        name: 'results'

<IndexScreen>:
    path_input: path_in
    time_input: time_in
    status_lbl: stat
    
    BoxLayout:
        orientation: 'vertical'
        padding: 20
        spacing: 15
        
        Label:
            text: 'Komitan Kutter (Native)'
            font_size: '24sp'
            size_hint_y: None
            height: 50
            
        TextInput:
            id: path_in
            text: '/storage/emulated/0/Download/video.mp4'
            hint_text: 'Path Video'
            size_hint_y: None
            height: 50
            multiline: False
            
        Label:
            text: 'Masukkan Waktu (Start - End):'
            size_hint_y: None
            height: 30
            
        TextInput:
            id: time_in
            hint_text: '00:00:05 - 00:00:10'
            size_hint_y: None
            height: 100
            
        Button:
            text: 'POTONG VIDEO'
            background_color: 0, 0.6, 1, 1
            size_hint_y: None
            height: 60
            on_release: root.do_cut()
            
        Label:
            id: stat
            text: 'Siap.'
            color: 1,1,0,1

<ResultsScreen>:
    status_lbl: res_stat
    prog_bar: pbar
    back_btn: bbtn
    
    BoxLayout:
        orientation: 'vertical'
        padding: 30
        spacing: 20
        
        Label:
            text: 'Memproses...'
            font_size: '20sp'
        
        ProgressBar:
            id: pbar
            max: 100
            value: 0
            
        Label:
            id: res_stat
            text: 'Mohon tunggu...'
            halign: 'center'
            
        Button:
            id: bbtn
            text: 'Kembali'
            disabled: True
            size_hint_y: None
            height: 50
            on_release: root.go_back()
"""

if __name__ == '__main__':
    KutterApp().run()