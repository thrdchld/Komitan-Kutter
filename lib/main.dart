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
