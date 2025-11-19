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
          _statusLog = "Video terpilih: $_selectedVideoName";
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
    final String outDir = "${directory.path}/KomitanKutter";
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
       String outFile = "$outDir/cut_${i}_$timestamp.mp4";
       _lastOutputPath = outFile;

       String cmd = "-y -ss $start -to $end -i \"$_selectedVideoPath\" -c copy \"$outFile\"";
       
       await FFmpegKit.execute(cmd).then((session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          successCount++;
        } else {
          String? logs = await session.getLogsAsString();
          print("Gagal: $logs");
        }
      });
      
      setState(() => _progress = (i + 1) / lines.length);
    }

    setState(() {
      _isProcessing = false;
      _statusLog = "Selesai. $successCount video disimpan.";
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
