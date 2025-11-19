#!/bin/bash
set -e

echo "🔥 MEMULAI PERBAIKAN VERSI DART & CLEAN INSTALL..."

# 1. Hapus Semua Konfigurasi Salah
rm -rf android ios web macos windows linux test .github
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
  # [FIX] Dart 3.0.0 (Flutter 3.10+) sampai sebelum 4.0.0
  # Kemarin salah tulis 3.10.0 (Itu versi Flutter, bukan Dart)
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  
  # Paket FFmpeg Pilihan Anda
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
    // Request multiple permissions for Android 13+ compliance
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.videos,
        Permission.audio,
      ].request();
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
cat > .github/workflows/flutter-build.yml <<EOF
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
          mv \$MY_SDK/cmdline-tools/cmdline-tools \$MY_SDK/cmdline-tools/latest
          
          export PATH=\$MY_SDK/cmdline-tools/latest/bin:\$PATH
          yes | sdkmanager --licenses --sdk_root=\$MY_SDK > /dev/null
          # Install SDK 35 dan Build Tools 35.0.0 (Bukan 34)
          yes | sdkmanager "platforms;android-35" "build-tools;35.0.0" "platform-tools" --sdk_root=\$MY_SDK

      # 2. Generate Project
      - name: Create Project
        run: |
          rm -rf android
          flutter create . --platforms=android
          # PAKSA SDK PATH DI LOCAL.PROPERTIES
          echo "sdk.dir=\$MY_SDK" > android/local.properties

      # 3. Config Gradle (Kotlin & SDK Version)
      - name: Config Gradle
        run: |
          # Root Gradle: Kotlin 1.9.20 & AGP 8.2.0
          cat > android/build.gradle <<GRADLE
          buildscript {
              ext.kotlin_version = '1.9.20'
              repositories { google(); mavenCentral() }
              dependencies {
                  classpath 'com.android.tools.build:gradle:8.2.0'
                  classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:\\\$kotlin_version"
              }
          }
          allprojects { repositories { google(); mavenCentral(); maven { url 'https://jitpack.io' } } }
          rootProject.buildDir = '../build'
          subprojects { project.buildDir = "\\\${rootProject.buildDir}/\\\${project.name}" }
          subprojects { project.evaluationDependsOn(':app') }
          task clean(type: Delete) { delete rootProject.buildDir }
GRADLE

          # App Gradle: Force SDK 35 & BuildTools 35.0.0
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
          apply from: "\\\$flutterRoot/packages/flutter_tools/gradle/flutter.gradle"

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
              implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:\\\$kotlin_version"
              implementation "androidx.multidex:multidex:2.0.1"
          }
APP
          # Wrapper 8.5 (Wajib untuk AGP 8.2)
          mkdir -p android/gradle/wrapper
          echo "distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-all.zip" > android/gradle/wrapper/gradle-wrapper.properties

      # 4. Inject Permissions
      - name: Inject Permissions
        run: |
          sed -i '/<manifest/a \    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>' android/app/src/main/AndroidManifest.xml
          sed -i '/<manifest/a \    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>' android/app/src/main/AndroidManifest.xml
          sed -i '/<manifest/a \    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>' android/app/src/main/AndroidManifest.xml

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
echo "✅ SELESAI! VERSI DART SUDAH DIPERBAIKI."
echo "===================================================="
echo "👉 Lakukan perintah ini sekarang:"
echo "   git add ."
echo "   git commit -m 'fix: Correct Dart version & Build Tools sync'"
echo "   git push"
echo "===================================================="