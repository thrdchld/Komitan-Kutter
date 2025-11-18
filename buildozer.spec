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
p4a.branch = master

[android]
android.permissions = android.permission.READ_EXTERNAL_STORAGE, android.permission.WRITE_EXTERNAL_STORAGE, android.permission.INTERNET

# [PENTING] Menyertakan 'spesialis' ffmpeg-kit
android.gradle_dependencies = 'com.arthenica:ffmpeg-kit-full:5.1'

# Pastikan tidak ada baris 'services = ...' di sini