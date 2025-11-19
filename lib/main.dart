import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

// --- [IMPORT PENTING] ---
// Sesuai dokumentasi paket 'ffmpeg_kit_flutter_new'
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
// ------------------------

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

  Future<void> _pickVideo() async {
    // Minta izin storage lengkap
    if (await Permission.storage.request().isGranted || 
        await Permission.manageExternalStorage.request().isGranted ||
        await Permission.videos.request().isGranted) {
          
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedVideoPath = result.files.single.path;
          _selectedVideoName = result.files.single.name;
          _statusLog = "Video terpilih: $_selectedVideoName";
          _progress = 0.0;
        });
      }
    } else {
       setState(() => _statusLog = "Izin akses ditolak!");
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

    setState(() {
      _isProcessing = true;
      _statusLog = "Menganalisis...";
      _progress = 0.0;
    });

    // Simpan di folder App Documents agar aman di semua versi Android
    final directory = await getApplicationDocumentsDirectory(); 
    final String outDir = "${directory.path}/KomitanKutter";
    await Directory(outDir).create(recursive: true);

    List<String> lines = _timestampController.text.split('\n');
    int successCount = 0;
    
    for (int i = 0; i < lines.length; i++) {
       String line = lines[i];
       if (line.trim().isEmpty) continue;
       
       // Parse logic sederhana
       String cleanLine = line.replaceAll(' - ', ' ').replaceAll('-', ' ');
       List<String> parts = cleanLine.split(RegExp(r'\s+'));
       if (parts.length < 2) continue;

       double? start = _parseTime(parts[0]);
       double? end = _parseTime(parts[1]);
       if (start == null || end == null) continue;

       String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
       String outFile = "$outDir/cut_${i}_$timestamp.mp4";
       _lastOutputPath = outFile;

       setState(() => _statusLog = "Memproses segmen ${i+1}...");

       // Command FFmpeg
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
    }

    setState(() {
      _isProcessing = false;
      _statusLog = "Selesai. $successCount video tersimpan di aplikasi.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Komitan Kutter v4.1")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickVideo, 
              icon: const Icon(Icons.video_file),
              label: Text(_selectedVideoName ?? "Pilih Video")
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _timestampController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Timestamp (00:00:05 - 00:00:10)",
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            if (_isProcessing) const LinearProgressIndicator(),
            const SizedBox(height: 10),
            Text(_statusLog, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_isProcessing || _selectedVideoPath == null) ? null : _startProcessing, 
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text("MULAI POTONG")
            ),
            if (!_isProcessing && _lastOutputPath != null)
               TextButton(
                 onPressed: () => OpenFile.open(_lastOutputPath), 
                 child: const Text("Buka Hasil Terakhir")
               )
          ],
        ),
      ),
    );
  }
}