#!/bin/bash
set -e

echo "============================================="
echo "🚀 MEMULAI PERBAIKAN TOTAL PROYEK FLUTTER"
echo "============================================="

# 1. BERSIH-BERSIH TOTAL
echo "🗑️  Menghapus konfigurasi lama..."
rm -rf android ios web macos windows linux test
rm -rf lib
rm -rf .github
rm -f pubspec.yaml pubspec.lock

# Buat folder lagi
mkdir -p lib
mkdir -p .github/workflows

# 2. BUAT PUBSPEC.YAML (Versi FFmpeg Min 3.1.0)
echo "📝 Membuat pubspec.yaml..."
cat > pubspec.yaml <<EOF
name: komitan_kutter
description: Video Cutter Offline
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # Paket FFmpeg Baru (Server Aktif, Butuh SDK 35)
  ffmpeg_kit_flutter_new_min: ^3.1.0

  # Utilities Standard
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

# 3. BUAT MAIN.DART (Code Logic)
echo "📝 Membuat lib/main.dart..."
cat > lib/main.dart <<EOF
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

// Import Khusus Paket New Min
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';

void main() {
  runApp(const KomitanKutterApp());
}

class KomitanKutterApp extends StatelessWidget {
  const KomitanKutterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Komitan Kutter',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selectedVideoPath;
  String? _selectedVideoName;
  final TextEditingController _timestampController = TextEditingController(text: "00:00:05 - 00:00:10");
  String _statusLog = "Siap.";
  double _progress = 0.0;
  bool _isProcessing = false;
  String? _lastOutputPath;

  @override
  void initState() {
    super.initState();
    FFmpegKitConfig.enableLogCallback((log) {}); 
  }

  Future<void> _pickVideo() async {
    if (await Permission.storage.request().isGranted || 
        await Permission.manageExternalStorage.request().isGranted ||
        await Permission.videos.request().isGranted) {
          
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedVideoPath = result.files.single.path;
          _selectedVideoName = result.files.single.name;
          _statusLog = "Video terpilih: \$_selectedVideoName";
        });
      }
    }
  }

  double? _parseTime(String timeStr) {
    try {
      timeStr = timeStr.trim().replaceAll(',', '.');
      List<String> parts = timeStr.split(':');
      double seconds = 0.0;
      if (parts.length == 3) {
        seconds = double.parse(parts[0]) * 3600 + double.parse(parts[1]) * 60 + double.parse(parts[2]);
      } else if (parts.length == 2) {
        seconds = double.parse(parts[0]) * 60 + double.parse(parts[1]);
      } else {
        seconds = double.parse(parts[0]);
      }
      return seconds;
    } catch (e) {
      return null;
    }
  }

  Future<void> _startProcessing() async {
    if (_selectedVideoPath == null) return;
    setState(() { _isProcessing = true; _statusLog = "Memproses..."; _progress = 0.0; });

    final directory = await getApplicationDocumentsDirectory(); 
    final String outDir = "\${directory.path}/KomitanKutter";
    await Directory(outDir).create(recursive: true);

    List<String> lines = _timestampController.text.split('\n');
    int successCount = 0;

    for (int i = 0; i < lines.length; i++) {
       String line = lines[i];
       if (line.trim().isEmpty) continue;
       String cleanLine = line.replaceAll(' - ', ' ').replaceAll('-', ' ');
       List<String> parts = cleanLine.split(RegExp(r'\s+'));
       if (parts.length < 2) continue;

       double? start = _parseTime(parts[0]);
       double? end = _parseTime(parts[1]);
       if (start == null || end == null) continue;

       String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
       String outFile = "\$outDir/cut_\${i}_\$timestamp.mp4";
       _lastOutputPath = outFile;

       String cmd = "-y -ss \$start -to \$end -i \"\$_selectedVideoPath\" -c copy \"\$outFile\"";
       
       await FFmpegKit.execute(cmd).then((session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          successCount++;
        } else {
          String? logs = await session.getLogsAsString();
          print("Gagal: \$logs");
        }
      });
      
      setState(() => _progress = (i + 1) / lines.length);
    }

    setState(() {
      _isProcessing = false;
      _statusLog = "Selesai. \$successCount video disimpan.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Komitan Kutter (Min)")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: _isProcessing ? null : _pickVideo, child: Text(_selectedVideoName ?? "Pilih Video")),
            const SizedBox(height: 20),
            TextField(controller: _timestampController, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "00:00:05 - 00:00:10")),
            const SizedBox(height: 20),
            if (_isProcessing) LinearProgressIndicator(value: _progress),
            const SizedBox(height: 10),
            Text(_statusLog),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _isProcessing ? null : _startProcessing, child: const Text("MULAI POTONG")),
            if (!_isProcessing && _lastOutputPath != null) TextButton(onPressed: () => OpenFile.open(_lastOutputPath), child: const Text("Buka Hasil"))
          ],
        ),
      ),
    );
  }
}
EOF

# 4. BUAT GITHUB ACTION YAML (Private SDK Strategy)
echo "📝 Membuat .github/workflows/flutter-build.yml..."
cat > .github/workflows/flutter-build.yml <<EOF
name: Build Flutter APK (Final)

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-22.04

    env:
      JAVA_VERSION: '17'
      FLUTTER_VERSION: '3.19.0'
      MY_SDK_ROOT: \${{ github.workspace }}/android-sdk-custom

    steps:
      - uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: \${{ env.JAVA_VERSION }}

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: \${{ env.FLUTTER_VERSION }}
          channel: 'stable'
          cache: true

      # 1. Install SDK 35 Secara Private (Anti Korup)
      - name: Setup Clean Android SDK 35
        run: |
          echo "🛠️ Preparing Private Android SDK 35..."
          mkdir -p \$MY_SDK_ROOT/cmdline-tools
          
          wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline.zip
          unzip -q cmdline.zip -d \$MY_SDK_ROOT/cmdline-tools
          mv \$MY_SDK_ROOT/cmdline-tools/cmdline-tools \$MY_SDK_ROOT/cmdline-tools/latest
          
          echo "ANDROID_HOME=\$MY_SDK_ROOT" >> \$GITHUB_ENV
          echo "ANDROID_SDK_ROOT=\$MY_SDK_ROOT" >> \$GITHUB_ENV
          echo "\$MY_SDK_ROOT/cmdline-tools/latest/bin" >> \$GITHUB_PATH
          echo "\$MY_SDK_ROOT/platform-tools" >> \$GITHUB_PATH
          
          export PATH=\$MY_SDK_ROOT/cmdline-tools/latest/bin:\$PATH
          yes | sdkmanager --licenses > /dev/null
          # Paket wajib untuk ffmpeg_kit_new
          yes | sdkmanager "platforms;android-35" "build-tools;34.0.0" "platform-tools"

      # 2. Reset Project Android
      - name: Re-generate Android Project
        run: |
          rm -rf android
          flutter create . --project-name=komitan_kutter --org=com.komitan --platforms=android

      # 3. Inject Konfigurasi Modern (Kotlin 1.9 + AGP 8)
      - name: Configure Gradle for SDK 35
        run: |
          # Root build.gradle
          cat > android/build.gradle <<GRADLE
          buildscript {
              ext.kotlin_version = '1.9.20'
              repositories {
                  google()
                  mavenCentral()
              }
              dependencies {
                  classpath 'com.android.tools.build:gradle:8.2.0'
                  classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:\\\$kotlin_version"
              }
          }
          allprojects {
              repositories {
                  google()
                  mavenCentral()
                  maven { url 'https://jitpack.io' }
              }
          }
          rootProject.buildDir = '../build'
          subprojects {
              project.buildDir = "\\\${rootProject.buildDir}/\\\${project.name}"
          }
          subprojects {
              project.evaluationDependsOn(':app')
          }
          task clean(type: Delete) {
              delete rootProject.buildDir
          }
GRADLE

          # Gradle Wrapper 8.5
          mkdir -p android/gradle/wrapper
          echo "distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-all.zip" > android/gradle/wrapper/gradle-wrapper.properties

      # 4. Inject Izin & MinSDK
      - name: Inject Permissions & MinSDK
        run: |
          # Manifest
          sed -i '/<manifest/a \    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>' android/app/src/main/AndroidManifest.xml
          sed -i '/<manifest/a \    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>' android/app/src/main/AndroidManifest.xml
          
          # App Gradle
          sed -i 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 24/' android/app/build.gradle
          sed -i 's/compileSdkVersion flutter.compileSdkVersion/compileSdkVersion 35/' android/app/build.gradle
          sed -i 's/targetSdkVersion flutter.targetSdkVersion/targetSdkVersion 35/' android/app/build.gradle
          sed -i '/android {/a \    namespace "com.komitan.komitan_kutter"' android/app/build.gradle

      # 5. Install & Build
      - name: Build APK
        run: |
          flutter pub get
          flutter build apk --release --split-per-abi --verbose

      # 6. Upload
      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: KomitanKutter-NewMin-APK
          path: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
EOF

echo "============================================="
echo "✅ SEMUA FILE BERHASIL DIBUAT!"
echo "============================================="
echo "👉 Jalankan perintah ini sekarang:"
echo "   git add ."
echo "   git commit -m 'fix: Rebuild all files with Private SDK strategy'"
echo "   git push"
echo "============================================="