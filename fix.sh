#!/usr/bin/env bash
set -euo pipefail

# reset_and_rewrite_repo.sh
# - Backup current repo (branch + tar.gz)
# - Remove everything except .git
# - Create minimal Flutter project skeleton (pubspec, lib/main.dart, .github workflow)
# - Commit changes (new clean history on top of existing .git)

echo
echo "======================================"
echo "  REPO FULL RESET & SKELETON REWRITE"
echo "======================================"
echo

# Safety check: inside git repo?
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Error: Tidak berada di repository git. Batalkan."
  exit 1
fi

# Confirm destructive action (non-interactive per request, but print explicit warning)
echo "⚠️ WARNING: This script will REMOVE ALL FILES in this repository EXCEPT the .git directory."
echo "A backup branch and a tarball will be created before deletion."
echo

# 1) Create backup branch and tarball
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_BRANCH="backup-before-reset-${TIMESTAMP}"
echo "🔒 Membuat backup branch: $BACKUP_BRANCH"
git add -A || true
git commit -m "[auto] backup before full reset ($TIMESTAMP)" || true
git branch "$BACKUP_BRANCH" || true

# Create a tarball of the whole repo (including history) for safety
BACKUP_TAR="../repo-backup-${TIMESTAMP}.tar.gz"
echo "📦 Membuat tarball backup (one level up): $BACKUP_TAR"
# ensure we are in repo root
REPO_ROOT="$(git rev-parse --show-toplevel)"
(
  cd "$REPO_ROOT"
  # tar up everything including .git (so full backup)
  tar -czf "$BACKUP_TAR" .
)
echo "✔ Backup tarball dibuat."

# 2) Remove everything except .git
echo
echo "🧹 Menghapus semua file/folder kecuali .git ..."
cd "$REPO_ROOT"
# double-check presence of .git
if [ ! -d ".git" ]; then
  echo "❌ .git tidak ditemukan di $REPO_ROOT. Batalkan."
  exit 1
fi

# remove all top-level entries except .git
# Note: this preserves hidden files named .git only.
shopt -s extglob
# Use find to be safer with many entries
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
shopt -u extglob

echo "✔ Semua file kecuali .git telah dihapus."

# 3) Create minimal files & folders (no flutter commands)
echo
echo "✨ Menulis ulang skeleton project minimal..."

# .gitignore
cat > .gitignore <<'IGN'
# Flutter / Dart
.dart_tool/
.packages
.pub/
build/
.flutter-plugins
.flutter-plugins-deps
.pub-cache/
.idea/
*.iml
*.ipr
*.iws
android/.gradle/
android/app/*keystore*
android/local.properties
*.lock
*.log
.DS_Store
IGN

# README
cat > README.md <<'MD'
# Komitan Kutter (skeleton)

Repo telah di-reset dan ditulis ulang dengan skeleton minimal.
Build dan pembuatan APK dilakukan di CI (GitHub Actions) — tidak perlu Flutter terinstall di repo lokal.
MD

# pubspec.yaml (forces valid package name)
cat > pubspec.yaml <<'YAML'
name: komitan_kutter
description: Video Cutter Offline
publish_to: none
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  # Only use FFmpeg from pub.dev
  ffmpeg_kit_flutter_new_min: ^3.1.0

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

# lib/main.dart
mkdir -p lib
cat > lib/main.dart <<'DART'
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
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
  
  @override
  void initState() {
    super.initState();
    FFmpegKitConfig.enableLogCallback((log) {
      // optional: forward logs if needed
    });
  }

  Future<void> cut() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.videos,
        Permission.audio,
      ].request();
    }

    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null) return;

    setState(() => status = "Memproses...");
    final path = res.files.single.path!;
    final dir = await getApplicationDocumentsDirectory();
    final out = "\${dir.path}/out_\${DateTime.now().millisecondsSinceEpoch}.mp4";

    final session = await FFmpegKit.execute('-y -ss 0 -t 5 -i "$path" -c copy "$out"');
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      setState(() => status = "Selesai: $out");
      OpenFile.open(out);
    } else {
      setState(() => status = "Gagal memproses (kode: \$returnCode)");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Komitan Kutter")),
      body: Center(child: ElevatedButton(onPressed: cut, child: Text(status))),
    );
  }
}
DART

# 3b) Minimal android placeholders so some tools won't error (these will be overwritten by CI if needed)
mkdir -p android/app/src/main
cat > android/placeholder.txt <<'TXT'
This repo was reset to a minimal Flutter skeleton. Android files are generated in CI.
TXT

# 4) Write GitHub Actions workflow so CI will build APK (uses previous safe workflow style)
mkdir -p .github/workflows
cat > .github/workflows/flutter-build.yml <<'YAML'
name: Build Flutter APK (CI build)

on:
  push:
    paths:
      - '.github/workflows/flutter-build.yml'
      - 'pubspec.yaml'
      - 'lib/**'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-22.04
    env:
      MY_SDK: \${{ github.workspace }}/custom-android-sdk

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Java (Temurin 17)
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'

      - name: Setup Custom SDK 35
        run: |
          set -euo pipefail
          mkdir -p "$MY_SDK/cmdline-tools"
          wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmd.zip
          unzip -q cmd.zip -d "$MY_SDK/cmdline-tools"
          if [ -d "$MY_SDK/cmdline-tools/cmdline-tools" ]; then
            mv "$MY_SDK/cmdline-tools/cmdline-tools" "$MY_SDK/cmdline-tools/latest" || true
          else
            mkdir -p "$MY_SDK/cmdline-tools/latest"
            mv "$MY_SDK/cmdline-tools"/* "$MY_SDK/cmdline-tools/latest" 2>/dev/null || true
          fi
          SDKMANAGER="$MY_SDK/cmdline-tools/latest/bin/sdkmanager"
          export PATH="$MY_SDK/cmdline-tools/latest/bin:$PATH"
          { yes | "$SDKMANAGER" --licenses --sdk_root="$MY_SDK" >/dev/null 2>&1 || true; }
          { yes | "$SDKMANAGER" "platforms;android-35" "build-tools;35.0.0" "platform-tools" --sdk_root="$MY_SDK" >/dev/null 2>&1 || true; }

      - name: Create/regen android project (force valid package)
        run: |
          set -euo pipefail
          PROJECT_NAME="komitan_kutter"
          ORG="com.komitan"
          rm -rf android
          flutter create . --project-name "$PROJECT_NAME" --org "$ORG" --platforms=android
          echo "sdk.dir=$MY_SDK" > android/local.properties

      - name: Inject Permissions (if manifest exists)
        run: |
          set -euo pipefail
          MANIFEST=android/app/src/main/AndroidManifest.xml
          if [ -f "$MANIFEST" ]; then
            cp "$MANIFEST" "$MANIFEST.bak"
            perl -0777 -pe 's|</manifest>|    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n</manifest>|s' -i "$MANIFEST" || true
            echo "Permissions injected (backup saved)."
          else
            echo "Manifest tidak ditemukan; skipping permissions."
          fi

      - name: Flutter doctor
        run: flutter doctor -v || true

      - name: Build APK
        run: |
          flutter pub get
          flutter build apk --release --split-per-abi --verbose

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: KomitanKutter-APK
          path: build/app/outputs/flutter-apk/*.apk
YAML

# 5) Git commit new skeleton
echo
echo "✅ Menambahkan file skeleton dan workflow. Membuat commit baru..."
git add -A
git commit -m "chore: reset repo to clean skeleton; use ffmpeg_kit_flutter_new_min from pub.dev" || true

echo
echo "======================================"
echo " DONE — repo cleaned and skeleton written"
echo " Backup branch: $BACKUP_BRANCH"
echo " Backup tarball: $BACKUP_TAR"
echo
echo "Next steps:"
echo " 1) Periksa perubahan: git status && git show --name-only HEAD"
echo " 2) Jika OK: git push origin HEAD"
echo " 3) Pantau GitHub Actions (Actions tab) — CI akan create + build APK"
echo
echo "If you want, I can also add keystore/signing steps to the workflow (use secrets)."
echo "======================================"
