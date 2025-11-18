[app]
title = Komitan Kutter
package.name = komitankutter
package.domain = org.komitan

# [FIX] Menambahkan versi untuk mengatasi error build
version = 0.1

source.dir = .
source.include_exts = py,png,jpg,kv,atlas

# [FIX] Mengunci versi Python & pyjnius untuk stabilitas
requirements = python3==3.11.9,kivy,pyjnius==master,android

orientation = portrait

# [FIX] Mengambil resep p4a terbaru
#p4a.branch = master

[android]
android.permissions = android.permission.READ_EXTERNAL_STORAGE, android.permission.WRITE_EXTERNAL_STORAGE, android.permission.INTERNET

# Minimal Android 7 
android.minapi = 24

# File ffmpeg
android.add_aars = libs/ffmpeg-kit-full-gpl-6.0-2.LTS.aar

# (str) Icon of the application
icon.filename = %(source.dir)s/icon.png

# Pastikan tidak ada baris 'services = ...' di sini