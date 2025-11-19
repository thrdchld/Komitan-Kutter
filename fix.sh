#!/usr/bin/env bash
set -euo pipefail

echo ""
echo "=============================================="
echo " 🚨 FULL FLUTTER PROJECT RESET & REBUILD"
echo "=============================================="
echo ""

###############################
# 0. SAFETY CHECK
###############################
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Bukan repo git! Script dibatalkan."
  exit 1
fi

echo "🔒 Membuat backup branch..."
BRANCH="backup-before-reset-$(date +%Y%m%d%H%M%S)"
git add -A || true
git commit -m "[auto] backup sebelum reset full" || true
git branch "$BRANCH"
echo "✔ Backup branch dibuat: $BRANCH"


###############################
# 1. HAPUS FILE-FILE PROJECT
###############################
echo ""
echo "🧹 Menghapus file & folder project Flutter lama..."

rm -rf android \
       ios \
       linux \
       macos \
       windows \
       web \
       build \
       test \
       .dart_tool \
       .metadata

rm -f pubspec.yaml pubspec.lock

rm -rf lib
mkdir -p lib

echo "✔ Semua platform & config lama dihapus"


###############################
# 2. REBUILD PROJECT
###############################
echo ""
echo "🔧 Membuat ulang project Flutter..."

PROJECT_NAME="komitan_kutter"
ORG="com.komitan"

flutter create . \
  --project-name="$PROJECT_NAME" \
  --org="$ORG" \
  --platforms=android

echo "✔ Flutter project berhasil direbuild"


###############################
# 3. FIX PUBSPEC (JIKA PERLU OVERRIDE)
###############################
echo ""
echo "📝 Menulis ulang pubspec.yaml..."

cat > pubspec.yaml <<EOF
name: komitan_kutter
description: Video Cutter Offline
publish_to: none
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  ffmpeg_kit_flutter_min: ^5.1.0
  file_picker: ^6.1.1
  permission_handler: ^11.0.1
  path_provider: ^2.1.1
  intl: ^0.18.1
  open_file: ^3.3.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

flutter:
  uses-material-design: true
EOF

echo "✔ pubspec.yaml selesai ditulis"


###############################
# 4. WRITE MAIN.DART
###############################
echo ""
echo "📝 Menulis ulang lib/main.dart..."

cat > lib/main.dart <<'EOF'
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_min/ffmpeg_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

void main() {
  runApp(const MaterialApp(home: HomePage()));
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String status = "Siap";

  Future<void> cut() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.videos,
        Permission.audio,
      ].request();
    }

    final pick = await FilePicker.platform.pickFiles(type: FileType.video);
    if (pick == null) return;

    setState(() => status = "Memproses...");

    final input = pick.files.single.path!;
    final docs = await getApplicationDocumentsDirectory();
    final output = "${docs.path}/cut_${DateTime.now().millisecondsSinceEpoch}.mp4";

    await FFmpegKit.execute('-y -ss 0 -t 5 -i "$input" -c copy "$output"');

    setState(() => status = "Selesai: $output");
    OpenFile.open(output);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Komitan Kutter")),
      body: Center(
        child: ElevatedButton(
          onPressed: cut,
          child: Text(status),
        ),
      ),
    );
  }
}
EOF

echo "✔ main.dart selesai ditulis"


###############################
# 5. SYNC DEPENDENCIES
###############################
echo ""
echo "📦 Menjalankan flutter pub get..."
flutter pub get
echo "✔ Dependencies siap"


###############################
# 6. FINAL MESSAGE
###############################
echo ""
echo "=============================================="
echo " 🎉 SELESAI — PROJECT SUDAH DIBANGUN ULANG"
echo "=============================================="
echo ""
echo "➜ Lakukan commit:"
echo "   git add ."
echo "   git commit -m 'feat: rebuild project full'"
echo ""
echo "➜ Jalankan APK build:"
echo "   flutter build apk --release"
echo ""
