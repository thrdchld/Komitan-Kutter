#!/bin/bash
set -e

echo "🔥 MEMULAI RESET TOTAL (SINTAKS FIXED)..."

# 1. CLEANUP
rm -rf android ios web macos windows linux test lib .github
rm -f pubspec.yaml pubspec.lock analysis_options.yaml
mkdir -p lib
mkdir -p .github/workflows

# 2. PUBSPEC.YAML
echo "📝 Writing pubspec.yaml..."
cat > pubspec.yaml <<'END_PUBSPEC'
name: komitan_kutter
description: Video Cutter Offline
version: 1.0.0+1
publish_to: 'none'

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  ffmpeg_kit_flutter_new_min: ^3.1.0
  file_picker: ^6.1.1
  permission_handler: ^11.0.1
  path_provider: ^2.1.1
  archive: ^4.0.7
  video_player: ^2.10.1
  intl: ^0.18.1
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

flutter:
  uses-material-design: true
END_PUBSPEC

# 3. MAIN.DART
echo "📝 Writing lib/main.dart..."
cat > lib/main.dart <<'END_DART'
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';

void main() {
  runApp(const KomitanKutterApp());
}

class KomitanKutterApp extends StatelessWidget {
  const KomitanKutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Komitan Kutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
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
  PlatformFile? selectedFile;
  final TextEditingController timestampsCtrl = TextEditingController(text: "00:00:05 - 00:00:10");
  String status = "Siap";

  @override
  void initState() {
    super.initState();
    FFmpegKitConfig.enableLogCallback((log) {});
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.videos,
        Permission.audio,
      ].request();
    }
  }

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      setState(() => selectedFile = result.files.first);
    }
  }

  Future<void> startCut() async {
    if (selectedFile == null) return;
    setState(() => status = "Memproses...");
    
    try {
        final dir = await getApplicationDocumentsDirectory();
        final outFile = "${dir.path}/cut_${DateTime.now().millisecondsSinceEpoch}.mp4";
        final cmd = "-y -ss 0 -t 5 -i \"${selectedFile!.path}\" -c copy \"$outFile\"";
        
        final session = await FFmpegKit.execute(cmd);
        final rc = await session.getReturnCode();
        
        if (ReturnCode.isSuccess(rc)) {
            setState(() => status = "Sukses: $outFile");
        } else {
            setState(() => status = "Gagal.");
        }
    } catch (e) {
        setState(() => status = "Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Komitan Kutter")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: pickFile, child: const Text("Pilih Video")),
            if (selectedFile != null) Text("File: ${selectedFile!.name}"),
            const SizedBox(height: 20),
            TextField(controller: timestampsCtrl, decoration: const InputDecoration(labelText: "Waktu")),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: startCut, child: Text(status)),
          ],
        ),
      ),
    );
  }
}
END_DART

# 4. GITHUB ACTION YAML (Private SDK Strategy)
echo "📝 Writing .github/workflows/flutter-build.yml..."
cat > .github/workflows/flutter-build.yml <<'END_YAML'
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
      # Lokasi SDK Kustom di dalam workspace
      MY_SDK: ${{ github.workspace }}/custom-android-sdk

    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
          
      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.0'

      # 1. Install SDK 35 di Folder Kustom
      - name: Setup Custom SDK 35
        run: |
          mkdir -p $MY_SDK/cmdline-tools
          wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmd.zip
          unzip -q cmd.zip -d $MY_SDK/cmdline-tools
          mv $MY_SDK/cmdline-tools/cmdline-tools $MY_SDK/cmdline-tools/latest
          
          export PATH=$MY_SDK/cmdline-tools/latest/bin:$PATH
          yes | sdkmanager --licenses --sdk_root=$MY_SDK > /dev/null
          # Install SDK 35 dan Build Tools 35.0.0
          yes | sdkmanager "platforms;android-35" "build-tools;35.0.0" "platform-tools" --sdk_root=$MY_SDK

      # 2. Generate Project & PAKSA LINK KE SDK BARU
      - name: Create Project & Force SDK Link
        run: |
          rm -rf android
          flutter create . --platforms=android
          
          # PAKSA Gradle melihat ke SDK Custom lewat local.properties
          echo "sdk.dir=$MY_SDK" > android/local.properties

      # 3. Config Gradle (Kotlin & SDK Version)
      - name: Config Gradle
        run: |
          # Root Gradle
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

          # App Gradle
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
          # Wrapper 8.5
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
END_YAML

echo "===================================================="
echo "✅ SCRIPT SELESAI TANPA ERROR SINTAKS."
echo "===================================================="
echo "👉 Lakukan perintah ini sekarang:"
echo "   git add ."
echo "   git commit -m 'fix: Final structure fix'"
echo "   git push"