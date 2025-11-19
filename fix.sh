#!/bin/bash
set -e

echo "🔥 MEMULAI RESET TOTAL & PAKSA SDK 35..."

# 1. Hapus Semua
rm -rf android ios web macos windows linux test lib .github pubspec.yaml pubspec.lock
mkdir -p lib .github/workflows

# 2. Buat pubspec.yaml (Paket Pilihan Anda)
cat > pubspec.yaml <<EOF
name: komitan_kutter
description: Video Cutter
version: 1.0.0+1
environment:
  sdk: '>=3.0.0 <4.0.0'
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
  flutter_lints: ^2.0.0
flutter:
  uses-material-design: true
EOF

# 3. Buat main.dart
cat > lib/main.dart <<EOF
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
    if (await Permission.storage.request().isGranted) {
      var res = await FilePicker.platform.pickFiles(type: FileType.video);
      if (res != null) {
        setState(() => status = "Memproses...");
        String path = res.files.single.path!;
        String out = "\${(await getApplicationDocumentsDirectory()).path}/out.mp4";
        // Cut 5 detik pertama
        await FFmpegKit.execute("-y -ss 0 -t 5 -i \"\$path\" -c copy \"\$out\"");
        setState(() => status = "Selesai: \$out");
        OpenFile.open(out);
      }
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
EOF

# 4. Buat YAML GitHub Action (SOLUSI LOCAL.PROPERTIES)
cat > .github/workflows/flutter-build.yml <<EOF
name: Build Flutter APK (Force SDK 35)

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-22.04
    env:
      # Lokasi SDK Kustom di dalam workspace
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
          yes | sdkmanager "platforms;android-35" "build-tools;35.0.0" "platform-tools" --sdk_root=\$MY_SDK

      # 2. Generate Project & PAKSA LINK KE SDK BARU
      - name: Create Project & Force SDK Link
        run: |
          rm -rf android
          flutter create . --platforms=android
          
          # INI YANG KITA LEWATKAN SEBELUMNYA:
          # Kita paksa Gradle melihat ke SDK Custom kita lewat local.properties
          echo "sdk.dir=\$MY_SDK" > android/local.properties
          
          # Cek isinya
          cat android/local.properties

      # 3. Config Gradle (Kotlin & SDK Version)
      - name: Config Gradle
        run: |
          # Root Gradle: Kotlin 1.9.20
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

          # App Gradle: Force SDK 35
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

      # 4. Build Debug (Lebih aman dari error Lint)
      - name: Build APK
        run: |
          flutter pub get
          flutter build apk --debug --split-per-abi --verbose

      # 5. Upload
      - uses: actions/upload-artifact@v4
        with:
          name: KomitanKutter-SDK35-Final
          path: build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
EOF

echo "✅ SELESAI. Script siap di-push."
echo "👉 Lakukan: git add . && git commit -m 'final fix local.properties' && git push"