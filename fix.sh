#!/usr/bin/env bash
set -euo pipefail

# CONFIG
DO_COMMIT=false   # ubah ke true jika mau auto-commit & push
GIT_COMMIT_MSG="chore(ci): full repo cleanup + rebuild (minSdk 30) (auto)"
BACKUP_NAME="repo_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
MY_SDK_PATH="${MY_SDK:-$HOME/android-sdk-custom}"   # optional SDK path used in workflow file

# Paths to remove (clean)
REMOVE_PATHS=(android ios web macos windows linux test .github)
REMOVE_FILES=(pubspec.yaml pubspec.lock lib/main.dart)

echo "==> Membuat backup cepat sebelum membersihkan: $BACKUP_NAME"
tar -czf "$BACKUP_NAME" "${REMOVE_PATHS[@]}" "${REMOVE_FILES[@]}" 2>/dev/null || echo "Backup: beberapa file/dir mungkin tidak ada, lanjut..."

echo "==> Menghapus file & folder yang ditentukan..."
for p in "${REMOVE_PATHS[@]}"; do
  if [ -e "$p" ]; then
    rm -rf "$p"
    echo "  removed: $p"
  fi
done

for f in "${REMOVE_FILES[@]}"; do
  if [ -e "$f" ]; then
    rm -f "$f"
    echo "  removed: $f"
  fi
done

echo "==> Membuat struktur dasar"
mkdir -p lib .github/workflows android/app/src/main || true

# ---------------------------
# 1) PUBSPEC.YAML minimal (pakai ffmpeg_kit dari pub.dev)
# ---------------------------
cat > pubspec.yaml <<'YAML'
name: komitan_kutter
description: Video Cutter Offline
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  # gunakan ffmpeg_kit dari pub.dev (tidak memakai sumber lain)
  ffmpeg_kit_flutter_new_min: ^3.1.0

  # dependensi pendukung (opsional — tetap berguna untuk fungsi file picking dan open)
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
YAML

echo "=> pubspec.yaml dibuat."

# ---------------------------
# 2) lib/main.dart (simple UI + ffmpeg cut example)
# ---------------------------
cat > lib/main.dart <<'DART'
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

void main() => runApp(const MaterialApp(home: HomePage()));

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String status = "Pilih video";

  @override
  void initState() {
    super.initState();
    // optional: enable logs if needed
    // FFmpegKitConfig.enableLogCallback((log) {});
  }

  Future<void> cut() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
    }

    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null) {
      setState(() => status = "Batal memilih");
      return;
    }

    setState(() => status = "Memproses...");
    final path = res.files.single.path!;
    final dir = await getApplicationDocumentsDirectory();
    final out = '${dir.path}/out_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // Potong 5 detik pertama (copy codec agar cepat)
    final cmd = '-y -ss 0 -t 5 -i "$path" -c copy "$out"';
    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();
    if (returnCode != null && returnCode.isValueSuccess()) {
      setState(() => status = 'Selesai: $out');
      OpenFile.open(out);
    } else {
      setState(() => status = 'Gagal proses (lihat log)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Komitan Kutter')),
      body: Center(
        child: ElevatedButton(
          onPressed: cut,
          child: Text(status),
        ),
      ),
    );
  }
}
DART

echo "=> lib/main.dart dibuat."

# ---------------------------
# 3) Buat workflow CI yang memaksa minSdkVersion=30 (jika mau)
# ---------------------------
mkdir -p .github/workflows
cat > .github/workflows/flutter-build.yml <<YAML
name: Build Flutter APK (CI - enforce minSdk 30)

on:
  push:
    paths:
      - '.github/workflows/flutter-build.yml'
      - 'pubspec.yaml'
      - 'lib/**'
  workflow_dispatch:

jobs:
  build:
    name: Build APK (minSdk=30)
    runs-on: ubuntu-22.04
    env:
      MY_SDK: ${MY_SDK_PATH}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java (Temurin 17)
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Flutter (3.19.0)
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'

      - name: Setup custom Android SDK 35
        run: |
          set -euo pipefail
          mkdir -p "\$MY_SDK/cmdline-tools"
          wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmd.zip
          unzip -q cmd.zip -d "\$MY_SDK/cmdline-tools"
          if [ -d "\$MY_SDK/cmdline-tools/cmdline-tools" ]; then
            mv "\$MY_SDK/cmdline-tools/cmdline-tools" "\$MY_SDK/cmdline-tools/latest" || true
          else
            mkdir -p "\$MY_SDK/cmdline-tools/latest"
            mv "\$MY_SDK/cmdline-tools"/* "\$MY_SDK/cmdline-tools/latest" 2>/dev/null || true
          fi
          export PATH="\$MY_SDK/cmdline-tools/latest/bin:\$PATH"
          yes | sdkmanager --licenses --sdk_root="\$MY_SDK" >/dev/null 2>&1 || true
          yes | sdkmanager "platforms;android-35" "build-tools;35.0.0" "platform-tools" --sdk_root="\$MY_SDK" >/dev/null 2>&1 || true
        shell: bash

      - name: Create android project (flutter create)
        run: |
          set -euo pipefail
          rm -rf android
          flutter create . --platforms=android --project-name komitan_kutter --org com.komitan
          echo "sdk.dir=\$MY_SDK" > android/local.properties
        shell: bash

      - name: Enforce minSdkVersion=30, compile/target 35
        run: |
          set -euo pipefail
          APP_BUILD=android/app/build.gradle
          if [ ! -f "\$APP_BUILD" ]; then
            echo "ERROR: \$APP_BUILD not found"
            exit 1
          fi
          perl -0777 -pe '
            s/minSdkVersion\s*\d+/minSdkVersion 30/g;
            s/compileSdkVersion\s*\d+/compileSdkVersion 35/g;
            s/targetSdkVersion\s*\d+/targetSdkVersion 35/g;
            s/buildToolsVersion\s*\"[^\"]+\"/buildToolsVersion "35.0.0"/g;
          ' -i "\$APP_BUILD"
          sed -n '/defaultConfig/,/}/p' "\$APP_BUILD" || true
        shell: bash

      - name: Flutter pub get & build
        run: |
          set -euo pipefail
          flutter pub get
          flutter build apk --release --split-per-abi --verbose
        shell: bash

      - name: Upload APKs
        uses: actions/upload-artifact@v4
        with:
          name: KomitanKutter-APK
          path: build/app/outputs/flutter-apk/*.apk
YAML

echo "=> .github/workflows/flutter-build.yml dibuat."

# ---------------------------
# 4) Local rebuild: check flutter existence, run flutter clean/get/build if present
# ---------------------------
if command -v flutter >/dev/null 2>&1; then
  echo "==> Flutter ditemukan: menjalankan flutter clean/pub get..."
  flutter clean || true
  flutter pub get
  # pastikan android/app/build.gradle minSdkVersion di-file lokal (jika ada android/)
  if [ -f "android/app/build.gradle" ]; then
    echo "Enforcing minSdkVersion 30 in android/app/build.gradle (local)..."
    perl -0777 -pe 's/minSdkVersion\s*\d+/minSdkVersion 30/g; s/compileSdkVersion\s*\d+/compileSdkVersion 35/g; s/targetSdkVersion\s*\d+/targetSdkVersion 35/g;' -i android/app/build.gradle || true
  fi

  echo "==> Mencoba build release APK (akan membutuhkan Android SDK di PATH atau local.properties pointing to SDK)"
  if command -v sdkmanager >/dev/null 2>&1 || [ -d "$ANDROID_HOME" ] || [ -d "$ANDROID_SDK_ROOT" ]; then
    echo "Building (this can take several minutes)..."
    flutter build apk --release --split-per-abi --verbose || echo "Build gagal — lihat output di atas."
  else
    echo "WARNING: Android SDK tidak terdeteksi (sdkmanager not found). Lewati build. CI workflow bisa menjalankan build di Actions."
  fi
else
  echo "WARNING: flutter CLI tidak terdeteksi di PATH. File sudah dibuat tetapi rebuild lokal dilewati."
  echo "Install Flutter atau jalankan ini di CI (workflow dibuat di .github/workflows)."
fi

# ---------------------------
# 5) Optional: git commit & push
# ---------------------------
if [ "$DO_COMMIT" = true ]; then
  if command -v git >/dev/null 2>&1; then
    git add -A
    git commit -m "$GIT_COMMIT_MSG" || echo "Nothing to commit"
    git push || echo "Push failed — cek auth/remote"
  else
    echo "DO_COMMIT=true tetapi git tidak ditemukan"
  fi
else
  echo "DO_COMMIT=false (tidak melakukan commit otomatis)."
  echo "Jika ingin commit otomatis, set DO_COMMIT=true di script atau commit manual."
fi

echo "==> Selesai. Backup: $BACKUP_NAME"
