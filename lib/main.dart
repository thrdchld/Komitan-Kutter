import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
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
  String? _selectedVideoPath;
  String? _selectedVideoName;
  final TextEditingController _timestampController = TextEditingController(text: "00:00:05 - 00:00:10");
  
  // Status State
  String _statusLog = "Siap.";
  double _progress = 0.0;
  bool _isProcessing = false;
  String? _lastOutputPath;

  // --- FUNGSI 1: MINTA IZIN & PILIH FILE ---
  Future<void> _pickVideo() async {
    // Minta izin storage (Android 12 ke bawah butuh ini)
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedVideoPath = result.files.single.path;
        _selectedVideoName = result.files.single.name;
        _statusLog = "Video terpilih: $_selectedVideoName";
        _progress = 0.0;
      });
    }
  }

  // --- FUNGSI 2: PARSING WAKTU (00:00:00 -> Detik) ---
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

  // --- FUNGSI 3: PROSES UTAMA ---
  Future<void> _startProcessing() async {
    if (_selectedVideoPath == null) {
      setState(() => _statusLog = "❌ Error: Pilih video dulu!");
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusLog = "Menganalisis timestamp...";
      _progress = 0.0;
    });

    // 1. Parse Timestamp baris per baris
    List<String> lines = _timestampController.text.split('\n');
    List<Map<String, double>> jobs = [];

    for (String line in lines) {
      if (line.trim().isEmpty) continue;
      // Pisahkan berdasarkan '-' atau spasi
      String cleanLine = line.replaceAll(' - ', ' ').replaceAll('-', ' ');
      List<String> parts = cleanLine.split(RegExp(r'\s+'));
      
      if (parts.length >= 2) {
        double? start = _parseTime(parts[0]);
        double? end = _parseTime(parts[1]);
        if (start != null && end != null && end > start) {
          jobs.add({'start': start, 'end': end});
        }
      }
    }

    if (jobs.isEmpty) {
      setState(() {
        _isProcessing = false;
        _statusLog = "❌ Error: Format waktu salah. Gunakan format 00:05 - 00:10";
      });
      return;
    }

    // 2. Siapkan Folder Output
    // Kita simpan di folder External App Storage (Android/data/...) agar tidak perlu izin Write Storage yang ribet di Android 11+
    final directory = await getExternalStorageDirectory(); 
    final String outDir = "${directory!.path}/KomitanKutter";
    await Directory(outDir).create(recursive: true);

    int successCount = 0;
    int total = jobs.length;

    // 3. Loop Processing
    for (int i = 0; i < total; i++) {
      double start = jobs[i]['start']!;
      double end = jobs[i]['end']!;
      
      String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      String outFile = "$outDir/cut_${i+1}_$timestamp.mp4";
      _lastOutputPath = outFile;

      setState(() {
        _statusLog = "Memotong bagian ${i+1} dari $total...";
        _progress = (i) / total;
      });

      // Command FFmpeg: Copy codec (-c copy) sangat cepat
      String cmd = "-y -ss $start -to $end -i \"$_selectedVideoPath\" -c copy \"$outFile\"";

      await FFmpegKit.execute(cmd).then((session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
          successCount++;
          print("Sukses: $outFile");
        } else {
          String? logs = await session.getLogsAsString();
          print("Gagal segmen $i: $logs");
        }
      });
    }

    setState(() {
      _isProcessing = false;
      _progress = 1.0;
      _statusLog = "✅ Selesai! $successCount/$total berhasil.\nDisimpan di: $outDir";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Komitan Kutter (Flutter)"),
        backgroundColor: Colors.blue.shade100,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: ListView(
          children: [
            // --- AREA PILIH FILE ---
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _pickVideo,
                    icon: const Icon(Icons.video_library),
                    label: Text(_selectedVideoPath == null ? "Pilih Video" : "Ganti Video"),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _selectedVideoName ?? "Belum ada video dipilih",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // --- AREA TIMESTAMP ---
            const Text("Masukkan Timestamp (Start - End):"),
            const SizedBox(height: 5),
            TextField(
              controller: _timestampController,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: "00:00:05 - 00:00:10\n00:01:20 - 00:01:30",
                filled: true,
                fillColor: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            // --- TOMBOL PROSES ---
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: (_isProcessing || _selectedVideoPath == null) ? null : _startProcessing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: _isProcessing 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("MULAI POTONG VIDEO", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 20),

            // --- PROGRESS & LOG ---
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black87,
              width: double.infinity,
              child: SelectableText(
                _statusLog,
                style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
              ),
            ),

            // --- TOMBOL BUKA HASIL ---
            if (!_isProcessing && _lastOutputPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: () => OpenFile.open(_lastOutputPath),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("Putar Hasil Terakhir"),
                ),
              )
          ],
        ),
      ),
    );
  }
}