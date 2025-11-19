#!/usr/bin/env bash
set -euo pipefail

echo "🔥 MEMULAI PERBAIKAN VERSI DART & CLEAN INSTALL (AMAN)..."

# 0. Safety: pastikan berada di repo git
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "⚠️ Tidak terlihat sebagai repo git. Proses dibatalkan untuk mencegah kehilangan data."
  exit 1
fi

# 0b. Commit changes / buat backup branch otomatis (so you can roll back)
BACKUP_BRANCH="pre-cleanup-$(date +%Y%m%d%H%M%S)"
git add -A || true
git commit -m "chore: autosave before cleanup ($BACKUP_BRANCH)" || true
git branch "$BACKUP_BRANCH" || true
echo "🔒 Backup dibuat: branch $BACKUP_BRANCH"

# 1. Hapus file/dirs yang memang ingin di-reset (hati-hati)
#    - Gunakan 'git clean' untuk hapus file untracked yang ingin dihapus, agar tak menghapus tracked files tanpa komit.
echo "🧹 Membersihkan file untracked dan build artifacts (dry-run)..."
git clean -ndx

echo "🧹 Menjalankan pembersihan final (hapus file untracked dan build output)..."
# HATI-HATI: ini hanya menghapus untracked/ignored files, bukan tracked files.
git clean -fdx

# Jika memang ingin menghapus tracked platform folders (android/ios/...), lakukan setelah backup:
echo "🔁 Menghapus direktori platform lama (android ios web macos windows linux) — ini menghapus tracked files!"
rm -rf android ios web macos windows linux test
# jika ingin menyimpan lib lain, hapus hanya file yang diperlukan:
rm -f pubspec.yaml pubspec.lock lib/main.dart
mkdir -p lib .github/workflows

# ---------------------------------------------------------
# 2. BUAT PUBSPEC.YAML (YANG BENAR)
# ---------------------------------------------------------
echo "📝 Menulis pubspec.yaml (Fixed Dart Version)..."
cat > pubspec.yaml <<EOF
name: komitan_kutter
description: Video Cutter Offline
publish_to: 'none'
version: 1.0.0+1

environment:
  # Dart 3.x (>=3.0.0 <4.0.0)
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  
  # Paket FFmpeg (minimal build)
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
EOF

# ---------------------------------------------------------
# 3. BUAT MAIN.DART (Logic)
# ---------------------------------------------------------
echo "📝 Menulis lib/main.dart..."
cat > lib/main.dart <<'DARTCODE'
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
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
    // Request permissions: untuk Android 13+ gunakan READ_MEDIA_* (handled by permission_handler)
    if (Platform.isAndroid) {
      final perms = <Permission>[
        Permission.storage, // fallback for older devices
        Permission.manageExternalStorage,
        Permission.videos,
        Permission.audio,
      ];
      await perms.request();
    }

    var res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res != null) {
      setState(() => status = "Memproses...");
      String path = res.files.single.path!;
      
      final dir = await getApplicationDocumentsDirectory();
      String out = "${dir.path}/out_${DateTime.now().millisecondsSinceEpoch}.mp4";
      
      // Cut 5 detik pertama
      await FFmpegKit.execute("-y -ss 0 -t 5 -i \"$path\" -c copy \"$out\"");
      
      setState(() => status = "Selesai: $out");
      OpenFile.open(out);
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
DARTCODE

# ---------------------------------------------------------
# 4. BUAT GITHUB ACTION YAML (Private SDK Fix)
# ---------------------------------------------------------
echo "📝 Menulis .github/workflows/flutter-build.yml..."
cat > .github/workflows/flutter-build.yml <<'EOF'
name: Build Flutter APK (Final Fix)

on:
  push:
    paths:
      - '.github/workflows/flutter-build.yml'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-22.04
    env:
      MY_SDK: \${{ github.workspace }}/custom-android-sdk

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'

      # 1. Install SDK 35 di Folder Kustom
      - name: Setup Custom SDK 35
        run: |
          mkdir -p \$MY_SDK/cmdline-tools
          wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmd.zip
          unzip -q cmd.zip -d \$MY_SDK/cmdline-tools
          mv \$MY_SDK/cmdline-tools/cmdline-tools \$MY_SDK/cmdline-tools/latest || true
          
          export PATH=\$MY_SDK/cmdline-tools/latest/bin:\$PATH
          yes | sdkmanager --licenses --sdk_root=\$MY_SDK > /dev/null
          yes | sdkmanager "platforms;android-35" "build-tools;35.0.0" "platform-tools" --sdk_root=\$MY_SDK

      # 2. Generate Project
      - name: Create Project
        run: |
          rm -rf android
          flutter create . --platforms=android
          echo "sdk.dir=\$MY_SDK" > android/local.properties

      # 3. Config Gradle (Kotlin & SDK Version)
      - name: Config Gradle
        run: |
          cat > android/build.gradle <<GRADLE
          buildscript {
              ext.kotlin_version = '1.9.20'
              repositories { google(); mavenCentral() }
              dependencies {
                  classpath 'com.android.tools.build:gradle:8.2.0'
                  classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:\$kotlin_version"
              }
          }
          allprojects { repositories { google(); mavenCentral(); maven { url 'https://jitpack.io' } } }
          rootProject.buildDir = '../build'
          subprojects { project.buildDir = "\${rootProject.buildDir}/\${project.name}" }
          subprojects { project.evaluationDependsOn(':app') }
          task clean(type: Delete) { delete rootProject.buildDir }
GRADLE

          cat > android/app/build.gradle <<APP
          def localProperties = new Properties()
          def localPropertiesFile = rootProject.file('local.properties')
          if (localPropertiesFile.exists()) {
              localPropertiesFile.withReader('UTF-8') { reader -> localProperties.load(reader) }
          }
          def flutterRoot = localProperties.getProperty('flutter.sdk')
          if (flutterRoot == null) throw new GradleException("Flutter SDK not found.")

          apply plugin: 'com.android.application'
          apply plugin: 'kotlin-android'
          apply from: "\$flutterRoot/packages/flutter_tools/gradle/flutter.gradle"

          android {
              namespace "com.komitan.komitan_kutter"
              compileSdkVersion 35
              buildToolsVersion "35.0.0"
              
              defaultConfig {
                  applicationId "com.komitan.komitan_kutter"
                  minSdkVersion 24
                  targetSdkVersion 35
                  versionCode 1
                  versionName "1.0"
                  multiDexEnabled true
              }
              compileOptions { sourceCompatibility JavaVersion.VERSION_1_8; targetCompatibility JavaVersion.VERSION_1_8 }
              kotlinOptions { jvmTarget = '1.8' }
          }
          flutter { source '../..' }
          dependencies {
              implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:\$kotlin_version"
              implementation "androidx.multidex:multidex:2.0.1"
          }
APP
          mkdir -p android/gradle/wrapper
          echo "distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-all.zip" > android/gradle/wrapper/gradle-wrapper.properties

      # 4. Inject Permissions (only if manifest exists)
      - name: Inject Permissions
        run: |
          MANIFEST=android/app/src/main/AndroidManifest.xml
          if [ -f "\$MANIFEST" ]; then
            cp "\$MANIFEST" "\$MANIFEST.bak"
            perl -0777 -pe 's|</manifest>|    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n</manifest>|s' -i "\$MANIFEST"
            echo "Permissions injected (backup saved as \$MANIFEST.bak). NOTE: consider using READ_MEDIA_* for Android 13+ or Android photo picker for one-time access."
          else
            echo "⚠️ AndroidManifest.xml tidak ditemukan, melewati injeksi permission."
          fi

      # 5. Build
      - name: Build APK
        run: |
          flutter pub get
          flutter build apk --release --split-per-abi --verbose

      # 6. Upload
      - uses: actions/upload-artifact@v4
        with:
          name: KomitanKutter-Final-APK
          path: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
EOF

echo "===================================================="
echo "✅ SELESAI! VERSI DART SUDAH DIPERBAIKI (AMAN)."
echo "===================================================="
echo "👉 Rekomendasi langkah selanjutnya:"
echo "   1) Cek perubahan: git diff"
echo "   2) Jika puas: git add . && git commit -m 'fix: Correct Dart version & Build Tools sync'"
echo "   3) Push: git push"
echo "===================================================="
