#!/usr/bin/env bash
set -euo pipefail

# reset_and_rewrite_min_android11.sh
# - Backup branch + tarball backup
# - Hapus semua kecuali .git
# - Tulis skeleton minimal Flutter (pubspec, lib/main.dart, .gitignore, README)
# - Tulis GitHub Actions workflow yang:
#     * menjalankan flutter create
#     * memaksa minSdkVersion = 30 (Android 11)
#     * build apk
#
# Do NOT run flutter locally. CI will run flutter.

echo
echo "======================================"
echo "  RESET REPO + SKELETON (min Android 11)"
echo "======================================"
echo

# 0. cek git
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Bukan repository git. Batalkan."
  exit 1
fi

# 1. Backup branch + tarball
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
BACKUP_BRANCH="backup-before-reset-${TIMESTAMP}"
echo "🔒 Membuat backup branch: $BACKUP_BRANCH"
git add -A || true
git commit -m "[auto] backup before reset ($TIMESTAMP)" || true
git branch "$BACKUP_BRANCH" || true

BACKUP_TAR="../repo-backup-${TIMESTAMP}.tar.gz"
REPO_ROOT="$(git rev-parse --show-toplevel)"
echo "📦 Membuat tarball backup (one level up): $BACKUP_TAR"
(
  cd "$REPO_ROOT"
  tar -czf "$BACKUP_TAR" .
)
echo "✔ Backup tarball dibuat."

# 2. Hapus semua kecuali .git
echo
echo "🧹 Menghapus semua file/folder kecuali .git ..."
cd "$REPO_ROOT"
shopt -s extglob
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
shopt -u extglob
echo "✔ Semua file kecuali .git dihapus."

# 3. Tulis skeleton minimal
echo
echo "✨ Menulis skeleton minimal (pubspec, lib, .gitignore, README)..."

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
android/.gradle/
android/app/*keystore*
android/local.properties
*.lock
*.log
.DS_Store
IGN

cat > README.md <<'MD'
# Komitan Kutter (clean skeleton - min Android 11)

Repo ini sudah di-reset ke skeleton minimal. Build APK dilakukan di CI (GitHub Actions).
MD

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
    FFmpegKitConfig.enableLogCallback((log) {});
  }

  Future<void> cut() async {
    if (Platform.isAndroid) {
      await [Permission.storage, Permission.videos, Permission.audio].request();
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

# Minimal placeholder so tools won't error
mkdir -p android/app/src/main
echo "placeholder" > android/placeholder.txt

# 4. Tulis GitHub Actions workflow (CI will create project & then force minSdkVersion=30)
echo
echo "🛠 Menulis .github/workflows/flutter-build.yml (CI will enforce minSdkVersion 30)..."
mkdir -p .github/workflows

cat > .github/workflows/flutter-build.yml <<'YAML'
name: Build Flutter APK (CI - min Android 11)

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
      MY_SDK: ${{ github.workspace }}/custom-android-sdk

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

      - name: Enforce Android 11 minSdkVersion (30) & compile/target SDK 35
        run: |
          set -euo pipefail
          APP_BUILD=android/app/build.gradle
          if [ -f "$APP_BUILD" ]; then
            # replace minSdkVersion, targetSdkVersion, compileSdkVersion safely
            perl -0777 -pe "s/compileSdkVersion\s*\d+/compileSdkVersion 35/s" -i "$APP_BUILD" || true
            perl -0777 -pe "s/targetSdkVersion\s*\d+/targetSdkVersion 35/s" -i "$APP_BUILD" || true
            perl -0777 -pe "s/minSdkVersion\s*\d+/minSdkVersion 30/s" -i "$APP_BUILD" || true
            # ensure buildToolsVersion set to 35.0.0 if present
            perl -0777 -pe "s/buildToolsVersion\s*\"[^\"]+\"/buildToolsVersion \"35.0.0\"/s" -i "$APP_BUILD" || true
            echo "Applied minSdkVersion=30, compile/targetSdkVersion=35 in $APP_BUILD"
          else
            echo "⚠️ $APP_BUILD not found (flutter create might have failed)."
            exit 1
          fi

      - name: Inject Permissions (if manifest exists)
        run: |
          set -euo pipefail
          MANIFEST=android/app/src/main/AndroidManifest.xml
          if [ -f "$MANIFEST" ]; then
            cp "$MANIFEST" "$MANIFEST.bak"
            perl -0777 -pe 's|</manifest>|    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n</manifest>|s' -i "$MANIFEST" || true
            echo "Permissions injected (backup saved)."
          else
            echo "Manifest not found; skipping permission injection."
          fi

      - name: Flutter doctor (debug)
        run: flutter doctor -v || true

      - name: Build APK (minSdkVersion=30)
        run: |
          flutter pub get
          flutter build apk --release --split-per-abi --verbose

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: KomitanKutter-APK
          path: build/app/outputs/flutter-apk/*.apk
YAML

# 5. Commit skeleton
echo
echo "📥 Commit skeleton ke repo..."
git add -A
git commit -m "chore: reset repo and create skeleton (min Android 11 / API 30)" || true

echo
echo "======================================"
echo " DONE — repo reset & skeleton written"
echo " Backup branch: $BACKUP_BRANCH"
echo " Backup tarball: $BACKUP_TAR"
echo
echo "Next steps:"
echo " 1) cek: git status && git show --name-only HEAD"
echo " 2) push: git push origin HEAD"
echo " 3) buka Actions tab di GitHub untuk lihat build (CI akan create + build)"
echo
echo "Note: jika ingin keystore signing, beri tahu supaya aku tambahkan steps (secrets)."
echo "======================================"
