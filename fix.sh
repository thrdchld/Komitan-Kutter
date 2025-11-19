#!/bin/bash
set -e

echo "🔥 MEMULAI PERBAIKAN TOTAL BERDASARKAN FILE ANDA..."

# 1. Bersihkan Folder
echo "🗑️  Menghapus file lama..."
rm -rf android ios web macos windows linux test .github
rm -f pubspec.yaml pubspec.lock lib/main.dart

# Buat ulang struktur
mkdir -p lib
mkdir -p .github/workflows

# ---------------------------------------------------------
# 2. Tulis pubspec.yaml (Sesuai yang Anda berikan)
# ---------------------------------------------------------
echo "📝 Menulis pubspec.yaml..."
cat > pubspec.yaml <<EOF
name: komitan_kutter
description: "A new Flutter project."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.10.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  file_picker: ^10.3.6
  path_provider: ^2.1.5
  permission_handler: ^12.0.1
  archive: ^4.0.7
  ffmpeg_kit_flutter_new: ^4.1.0
  video_player: ^2.10.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
EOF

# ---------------------------------------------------------
# 3. Tulis lib/main.dart (Sesuai yang Anda berikan)
# ---------------------------------------------------------
echo "📝 Menulis lib/main.dart..."
cat > lib/main.dart <<'DARTCODE'
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive_io.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:video_player/video_player.dart';

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
  final TextEditingController timestampsCtrl = TextEditingController();
  final TextEditingController mergeGapCtrl = TextEditingController(text: "0");
  bool overwrite = false;
  bool zipOutput = false;

  Future<void> pickFile() async {
    // Request permissions first for Android 13+ support
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => selectedFile = result.files.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Komitan Kutter"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ElevatedButton.icon(
            onPressed: pickFile,
            icon: const Icon(Icons.video_file),
            label: const Text("Pilih Video"),
          ),
          if (selectedFile != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.movie),
                title: Text(selectedFile!.name),
                subtitle: Text("${(selectedFile!.size / 1024 / 1024).toStringAsFixed(2)} MB"),
              ),
            ),
          const SizedBox(height: 16),
          const Text("Timestamp (satu baris = satu range):"),
          TextField(
            controller: timestampsCtrl,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: "00:00:05.000 - 00:00:20.500\n00:00:30 - 00:00:45",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text("Merge gap (detik):")),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: mergeGapCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
              )
            ],
          ),
          SwitchListTile(
            title: const Text("Overwrite output"),
            value: overwrite,
            onChanged: (v) => setState(() => overwrite = v),
          ),
          SwitchListTile(
            title: const Text("ZIP semua hasil"),
            value: zipOutput,
            onChanged: (v) => setState(() => zipOutput = v),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (selectedFile == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Pilih video terlebih dahulu")),
                );
                return;
              }
              if (timestampsCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Masukkan timestamp")),
                );
                return;
              }
              final mergeGap = double.tryParse(mergeGapCtrl.text) ?? 0.0;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PreviewPage(
                    file: selectedFile!,
                    timestamps: timestampsCtrl.text,
                    mergeGap: mergeGap,
                    overwrite: overwrite,
                    zipOutput: zipOutput,
                  ),
                ),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text("Preview Segmen"),
            ),
          ),
        ],
      ),
    );
  }
}

double? parseTimeToSeconds(String input) {
  if (input.trim().isEmpty) return null;
  var s = input.trim().replaceAll(",", ".");
  if (s.contains(":")) {
    final parts = s.split(":").map((p) => p.trim()).toList();
    try {
      if (parts.length == 3) {
        final h = double.tryParse(parts[0]) ?? 0;
        final m = double.tryParse(parts[1]) ?? 0;
        final secParts = parts[2].split(".");
        final sec = double.tryParse(secParts[0]) ?? 0;
        final ms = secParts.length > 1 ? double.tryParse("0.${secParts[1]}") ?? 0 : 0;
        return h * 3600 + m * 60 + sec + ms;
      } else if (parts.length == 2) {
        final m = double.tryParse(parts[0]) ?? 0;
        final secParts = parts[1].split(".");
        final sec = double.tryParse(secParts[0]) ?? 0;
        final ms = secParts.length > 1 ? double.tryParse("0.${secParts[1]}") ?? 0 : 0;
        return m * 60 + sec + ms;
      }
    } catch (_) {
      return double.tryParse(s);
    }
  }
  return double.tryParse(s);
}

String secondsToHhmmssms(double sec) {
  final total = sec.floor();
  final ms = ((sec - total) * 1000).round();
  final s = total % 60;
  final m = (total ~/ 60) % 60;
  final h = total ~/ 3600;
  return '${h.toString().padLeft(2, "0")}:${m.toString().padLeft(2, "0")}:${s.toString().padLeft(2, "0")}.${ms.toString().padLeft(3, "0")}';
}

List<Map<String, double>> parseRanges(String text) {
  final out = <Map<String, double>>[];
  final lines = text.split('\n');
  for (var ln in lines) {
    ln = ln.trim();
    if (ln.isEmpty) continue;
    ln = ln.replaceAll('\u2013', '-').replaceAll('\u2014', '-').replaceAll('->', '-').replaceAll('\u2192', '-');
    final separators = [' to ', ',', '\t', ' - ', '-', ' '];
    bool parsed = false;
    for (var sep in separators) {
      if (ln.contains(sep)) {
        final parts = ln.split(sep);
        if (parts.length >= 2) {
          final s = parseTimeToSeconds(parts[0]);
          final e = parseTimeToSeconds(parts.sublist(1).join(sep));
          if (s != null && e != null && e > s) {
            out.add({'start': s, 'end': e});
            parsed = true;
            break;
          }
        }
      }
    }
    if (!parsed) {
      final toks = ln.split(RegExp('\\s+'));
      if (toks.length >= 2) {
        final s = parseTimeToSeconds(toks[0]);
        final e = parseTimeToSeconds(toks[1]);
        if (s != null && e != null && e > s) out.add({'start': s, 'end': e});
      }
    }
  }
  return out;
}

List<Map<String, double>> mergeRanges(List<Map<String, double>> ranges, double gap) {
  if (ranges.isEmpty) return [];
  final list = ranges.map((e) => [e['start']!, e['end']!]).toList();
  list.sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<double>>[];
  merged.add([list[0][0], list[0][1]]);
  for (var i = 1; i < list.length; i++) {
    final cur = list[i];
    final last = merged.last;
    if (cur[0] <= last[1] + gap) {
      last[1] = cur[1] > last[1] ? cur[1] : last[1];
    } else {
      merged.add([cur[0], cur[1]]);
    }
  }
  return merged.map((m) => {'start': m[0], 'end': m[1]}).toList();
}

class PreviewPage extends StatefulWidget {
  final PlatformFile file;
  final String timestamps;
  final double mergeGap;
  final bool overwrite;
  final bool zipOutput;

  const PreviewPage({
    super.key,
    required this.file,
    required this.timestamps,
    required this.mergeGap,
    required this.overwrite,
    required this.zipOutput,
  });

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late List<Map<String, double>> ranges;
  VideoPlayerController? _controller;
  bool _isEditing = false;
  int _editingIndex = -1;

  @override
  void initState() {
    super.initState();
    ranges = parseRanges(widget.timestamps);
    if (widget.mergeGap > 0 && ranges.isNotEmpty) {
      ranges = mergeRanges(ranges, widget.mergeGap);
    }
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    if (widget.file.path != null) {
      _controller = VideoPlayerController.file(File(widget.file.path!));
      await _controller!.initialize();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleEdit(int index) {
    setState(() {
      if (_isEditing && _editingIndex == index) {
        _isEditing = false;
        _editingIndex = -1;
      } else {
        _isEditing = true;
        _editingIndex = index;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Segmen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: ranges.length,
                itemBuilder: (context, idx) {
                  final seg = ranges[idx];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Seg #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('${secondsToHhmmssms(seg['start']!)} — ${secondsToHhmmssms(seg['end']!)}'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_controller != null && _controller!.value.isInitialized)
                            AspectRatio(
                              aspectRatio: _controller!.value.aspectRatio,
                              child: VideoPlayer(_controller!),
                            ),
                          const SizedBox(height: 8),
                          if (_isEditing && _editingIndex == idx)
                            Column(
                              children: [
                                Row(
                                  children: [
                                    const Text('Start:'),
                                    Expanded(
                                      child: Slider(
                                        value: seg['start']!,
                                        min: 0,
                                        max: _controller?.value.duration.inSeconds.toDouble() ?? 100,
                                        onChanged: (v) {
                                          setState(() {
                                            seg['start'] = v;
                                          });
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller: TextEditingController(text: secondsToHhmmssms(seg['start']!)),
                                        onSubmitted: (v) {
                                          final parsed = parseTimeToSeconds(v);
                                          if (parsed != null) {
                                            setState(() {
                                              seg['start'] = parsed;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Text('End:'),
                                    Expanded(
                                      child: Slider(
                                        value: seg['end']!,
                                        min: 0,
                                        max: _controller?.value.duration.inSeconds.toDouble() ?? 100,
                                        onChanged: (v) {
                                          setState(() {
                                            seg['end'] = v;
                                          });
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller: TextEditingController(text: secondsToHhmmssms(seg['end']!)),
                                        onSubmitted: (v) {
                                          final parsed = parseTimeToSeconds(v);
                                          if (parsed != null) {
                                            setState(() {
                                              seg['end'] = parsed;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _toggleEdit(idx),
                              child: Text(_isEditing && _editingIndex == idx ? 'Done' : 'Edit Range'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: ranges.isEmpty
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProcessPage(
                            file: widget.file,
                            ranges: ranges,
                            overwrite: widget.overwrite,
                            zipOutput: widget.zipOutput,
                          ),
                        ),
                      );
                    },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Mulai Potong Video'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProcessPage extends StatefulWidget {
  final PlatformFile file;
  final List<Map<String, double>> ranges;
  final bool overwrite;
  final bool zipOutput;

  const ProcessPage({
    super.key,
    required this.file,
    required this.ranges,
    required this.overwrite,
    required this.zipOutput,
  });

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

class _ProcessPageState extends State<ProcessPage> {
  int totalSegments = 0;
  int doneSegments = 0;
  String status = 'Preparing...';
  Directory? outputBase;
  List<String> outputFiles = [];

  @override
  void initState() {
    super.initState();
    totalSegments = widget.ranges.length;
    _startProcessing();
  }

  Future<void> _startProcessing() async {
    setState(() => status = 'Preparing storage...');
    await _ensurePermissions();
    outputBase = await _prepareOutputFolder();
    setState(() => status = 'Starting cuts...');

    final srcPath = widget.file.path;
    if (srcPath == null) {
      setState(() => status = 'Error: No file path');
      return;
    }

    for (int segIdx = 0; segIdx < widget.ranges.length; segIdx++) {
      final r = widget.ranges[segIdx];
      final s = r['start']!;
      final e = r['end']!;
      final outName = '${segIdx + 1}.mp4';
      final outPath = '${outputBase!.path}/$outName';

      if (File(outPath).existsSync() && !widget.overwrite) {
        setState(() {
          doneSegments++;
          outputFiles.add(outPath);
        });
        continue;
      }

      setState(() => status = 'Cutting segment ${segIdx + 1}');
      final cmd = '-y -ss $s -to $e -i "$srcPath" -c copy "$outPath"';

      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();

      if (ReturnCode.isSuccess(rc)) {
        setState(() {
          doneSegments++;
          outputFiles.add(outPath);
        });
      } else {
        final failMessage = 'FFmpeg failed for segment ${segIdx + 1}';
        setState(() => status = failMessage);
      }
    }

    if (widget.zipOutput && outputFiles.isNotEmpty) {
      setState(() => status = 'Creating ZIP...');
      await _createZip(outputBase!);
    }

    setState(() => status = 'Finished. Output at: ${outputBase!.path}');
  }

  Future<void> _ensurePermissions() async {
    if (Platform.isAndroid) {
       await [
        Permission.storage,
        Permission.manageExternalStorage,
       ].request();
    }
  }

  Future<Directory> _prepareOutputFolder() async {
    // Use external storage for visibility
    Directory? doc = await getExternalStorageDirectory();
    if (doc == null) {
        doc = await getApplicationDocumentsDirectory();
    }
    
    final date = DateTime.now();
    final dateStr = '${date.year}${date.month}${date.day}_${date.hour}${date.minute}${date.second}';
    final base = Directory('${doc.path}/KomitanKutter/$dateStr');
    await base.create(recursive: true);
    return base;
  }

  Future<void> _createZip(Directory dir) async {
    final zipEncoder = ZipFileEncoder();
    final zipPath = '${dir.path}/all_results.zip';
    zipEncoder.create(zipPath);
    for (final f in dir.listSync()) {
      if (f is File && f.path.endsWith('.mp4')) {
        zipEncoder.addFile(f);
      }
    }
    zipEncoder.close();
  }

  @override
  Widget build(BuildContext context) {
    final pct = totalSegments == 0 ? 0.0 : (doneSegments / totalSegments);
    return Scaffold(
      appBar: AppBar(title: const Text('Processing')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(status, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: pct),
            const SizedBox(height: 12),
            Text('Done: $doneSegments / $totalSegments'),
            const Spacer(),
            if (status.startsWith('Finished'))
              ElevatedButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('Selesai'),
              ),
          ],
        ),
      ),
    );
  }
}
DARTCODE

# ---------------------------------------------------------
# 4. Tulis GitHub Action (SOLUSI PRIVATE SDK 35)
# ---------------------------------------------------------
echo "📝 Menulis .github/workflows/flutter-build.yml..."
cat > .github/workflows/flutter-build.yml <<'YAMLCODE'
name: Build Flutter APK (Private SDK 35)

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-22.04

    env:
      JAVA_VERSION: '17'
      FLUTTER_VERSION: '3.19.0'
      # Lokasi SDK Kustom (Agar bersih)
      MY_SDK_ROOT: ${{ github.workspace }}/android-sdk-custom

    steps:
      - uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: ${{ env.JAVA_VERSION }}

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: 'stable'
          cache: true

      # 1. Setup Private Android SDK 35
      - name: Setup Clean Android SDK 35
        run: |
          echo "🛠️ Preparing Private Android SDK 35..."
          mkdir -p $MY_SDK_ROOT/cmdline-tools
          
          wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline.zip
          unzip -q cmdline.zip -d $MY_SDK_ROOT/cmdline-tools
          mv $MY_SDK_ROOT/cmdline-tools/cmdline-tools $MY_SDK_ROOT/cmdline-tools/latest
          
          # Export ENV untuk step ini & selanjutnya
          echo "ANDROID_HOME=$MY_SDK_ROOT" >> $GITHUB_ENV
          echo "ANDROID_SDK_ROOT=$MY_SDK_ROOT" >> $GITHUB_ENV
          echo "$MY_SDK_ROOT/cmdline-tools/latest/bin" >> $GITHUB_PATH
          echo "$MY_SDK_ROOT/platform-tools" >> $GITHUB_PATH
          
          # Install
          export PATH=$MY_SDK_ROOT/cmdline-tools/latest/bin:$PATH
          yes | sdkmanager --licenses > /dev/null
          
          # Install paket wajib untuk ffmpeg_kit_new (SDK 35 & Build Tools 34/35)
          yes | sdkmanager "platforms;android-35" "build-tools;35.0.0" "platform-tools"

      # 2. Generate Project
      - name: Create Android Platform
        run: flutter create . --platforms=android

      # 3. Konfigurasi Gradle untuk SDK 35 (Hard Overwrite)
      - name: Configure Gradle for SDK 35
        run: |
          # Root build.gradle (Kotlin 1.9.20 + AGP 8.2.0)
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

          # App build.gradle (MinSDK 24, Target 35)
          cat > android/app/build.gradle <<APPGRADLE
          def localProperties = new Properties()
          def localPropertiesFile = rootProject.file('local.properties')
          if (localPropertiesFile.exists()) {
              localPropertiesFile.withReader('UTF-8') { reader -> localProperties.load(reader) }
          }
          def flutterRoot = localProperties.getProperty('flutter.sdk')
          if (flutterRoot == null) throw new GradleException("Flutter SDK not found.")
          
          def flutterVersionCode = localProperties.getProperty('flutter.versionCode')
          if (flutterVersionCode == null) flutterVersionCode = '1'
          def flutterVersionName = localProperties.getProperty('flutter.versionName')
          if (flutterVersionName == null) flutterVersionName = '1.0'

          apply plugin: 'com.android.application'
          apply plugin: 'kotlin-android'
          apply from: "\$flutterRoot/packages/flutter_tools/gradle/flutter.gradle"

          android {
              namespace "com.komitan.komitan_kutter"
              compileSdkVersion 35
              buildToolsVersion "35.0.0"
              
              compileOptions { sourceCompatibility JavaVersion.VERSION_1_8; targetCompatibility JavaVersion.VERSION_1_8 }
              kotlinOptions { jvmTarget = '1.8' }
              sourceSets { main.java.srcDirs += 'src/main/kotlin' }
              
              defaultConfig {
                  applicationId "com.komitan.komitan_kutter"
                  minSdkVersion 24
                  targetSdkVersion 35
                  versionCode flutterVersionCode.toInteger()
                  versionName flutterVersionName
                  multiDexEnabled true
              }
              buildTypes { release { signingConfig signingConfigs.debug } }
          }
          flutter { source '../..' }
          dependencies {
              implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:\$kotlin_version"
              implementation "androidx.multidex:multidex:2.0.1"
          }
APPGRADLE

          # Update Wrapper ke 8.5
          mkdir -p android/gradle/wrapper
          echo "distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-all.zip" > android/gradle/wrapper/gradle-wrapper.properties

      # 4. Inject Izin ke Manifest
      - name: Inject Permissions
        run: |
          MANIFEST="android/app/src/main/AndroidManifest.xml"
          cat > $MANIFEST <<EOF
          <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.komitan.komitan_kutter">
              <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
              <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
              <uses-permission android:name="android.permission.INTERNET"/>
              <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
              <application
                  android:label="Komitan Kutter"
                  android:name="\${applicationName}"
                  android:icon="@mipmap/ic_launcher">
                  <activity
                      android:name=".MainActivity"
                      android:exported="true"
                      android:launchMode="singleTop"
                      android:theme="@style/LaunchTheme"
                      android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
                      android:hardwareAccelerated="true"
                      android:windowSoftInputMode="adjustResize">
                      <meta-data android:name="io.flutter.embedding.android.NormalTheme" android:resource="@style/NormalTheme"/>
                      <intent-filter>
                          <action android:name="android.intent.action.MAIN"/>
                          <category android:name="android.intent.category.LAUNCHER"/>
                      </intent-filter>
                  </activity>
                  <meta-data android:name="flutterEmbedding" android:value="2" />
              </application>
          </manifest>
EOF

      # 5. Build
      - name: Build APK
        run: |
          flutter pub get
          flutter build apk --release --split-per-abi --verbose

      # 6. Upload
      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: KomitanKutter-Final
          path: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
YAMLCODE

echo "===================================================="
echo "✅ SELESAI! SEMUA FILE TELAH DIPERBAHARUI."
echo "===================================================="
echo "👉 Lakukan perintah ini sekarang:"
echo "   git add ."
echo "   git commit -m 'fix: Total rebuild with correct files'"
echo "   git push"
echo "===================================================="