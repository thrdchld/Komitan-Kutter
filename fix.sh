#!/usr/bin/env bash
set -euo pipefail

# prepare_for_ci_rebuild.sh
# - Menghapus platform files lokal
# - Menulis ulang pubspec, main.dart, gradle files minimal
# - Menulis GitHub Actions workflow untuk build di CI (runner akan install Flutter)

echo ""
echo "=========================================="
echo " Prepare repo for CI-only rebuild (SAFE)"
echo "=========================================="
echo ""

# 0. Safety: require git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ Bukan repository git. Batalkan."
  exit 1
fi

# 0b. Backup commit & branch
echo "🔒 Membuat backup commit & branch..."
git add -A || true
git commit -m "[auto] backup before CI-prep" || true
BACKUP_BRANCH="backup-ci-prep-$(date +%Y%m%d%H%M%S)"
git branch "$BACKUP_BRANCH" || true
echo "✔ Backup branch: $BACKUP_BRANCH"

# 1. Remove platform dirs & build artefacts (keamanan: tidak menghapus .git)
echo "🧹 Menghapus direktori platform & build lokal..."
rm -rf android ios linux macos windows web build test .dart_tool .package .packages .metadata
rm -f pubspec.lock
# keep .git and other config files

# ensure directories
mkdir -p lib android/app/src/main

# 2. Write pubspec.yaml (valid package name)
echo "📝 Menulis pubspec.yaml..."
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
YAML

# 3. Write lib/main.dart
echo "📝 Menulis lib/main.dart..."
cat > lib/main.dart <<'DART'
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
      await [Permission.storage, Permission.videos, Permission.audio].request();
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
DART

# 4. Minimal Android Gradle files (will be overwritten by CI's flutter create if used,
#    but having them avoids some missing-file errors in certain tools)
echo "📝 Menulis android/build.gradle & android/app/build.gradle (minimal placeholders)..."

cat > android/build.gradle <<'GRADLE'
buildscript {
    ext.kotlin_version = '1.9.20'
    repositories { google(); mavenCentral() }
    dependencies {
        classpath 'com.android.tools.build:gradle:8.2.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:${kotlin_version}"
    }
}
allprojects { repositories { google(); mavenCentral(); maven { url 'https://jitpack.io' } } }
rootProject.buildDir = '../build'
subprojects { project.buildDir = "${rootProject.buildDir}/${project.name}" }
subprojects { project.evaluationDependsOn(':app') }
task clean(type: Delete) { delete rootProject.buildDir }
GRADLE

cat > android/app/build.gradle <<'GRADLE_APP'
def localProperties = new Properties()
def localPropertiesFile = rootProject.file('local.properties')
if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader('UTF-8') { reader -> localProperties.load(reader) }
}
def flutterRoot = localProperties.getProperty('flutter.sdk')
if (flutterRoot == null) throw new GradleException("Flutter SDK not found.")

apply plugin: 'com.android.application'
apply plugin: 'kotlin-android'
apply from: "${flutterRoot}/packages/flutter_tools/gradle/flutter.gradle"

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
    implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:${kotlin_version}"
    implementation "androidx.multidex:multidex:2.0.1"
}
GRADLE_APP

# 5. Write GitHub Actions workflow file (CI will install Flutter & run create+build)
echo "📝 Menulis .github/workflows/flutter-build.yml (CI build)..."
mkdir -p .github/workflows

cat > .github/workflows/flutter-build.yml <<'YAML'
name: Build Flutter APK (CI build)

on:
  push:
    paths:
      - '.github/workflows/flutter-build.yml'
      - '**.dart'
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

      - name: Debug info
        run: |
          echo "WORKSPACE: $GITHUB_WORKSPACE"
          flutter --version || true

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
          # Force valid project name so Dart package name is valid
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
            echo "Permissions injected (backup saved as $MANIFEST.bak)."
          else
            echo "Manifest tidak ditemukan; melewati injeksi permission."
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

# 6. Final instructions
echo ""
echo "=========================================="
echo " DONE: repo prepared for CI-only rebuild"
echo "=========================================="
echo ""
echo "Langkah selanjutnya (lokal):"
echo " 1) cek perubahan: git status"
echo " 2) commit & push:"
echo "      git add ."
echo "      git commit -m 'ci: prepare repo for CI-only flutter rebuild'"
echo "      git push origin HEAD"
echo ""
echo "Setelah push, GitHub Actions akan menjalankan workflow dan membangun APK di runner."
echo ""
