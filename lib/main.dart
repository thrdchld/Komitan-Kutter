import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
// [KEMBALI KE IMPORT STANDAR]
import 'package:ffmpeg_kit_flutter_full_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full_gpl/return_code.dart';
// --------------------------
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
      theme: ThemeData(primarySwatch: Colors.blue),
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
  String _statusLog = "Siap.";
  double _progress = 0.0;
  bool _isProcessing = false;

  Future<void> _pickVideo() async {
    // Versi Permission Handler lama butuh ini
    await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();

    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      setState(() {
        _selectedVideoPath = result.files.single.path;
        _statusLog = "Video: ${result.files.single.name}";
      });
    }
  }

  Future<void> _startProcessing() async {
    if (_selectedVideoPath == null) return;
    setState(() { _isProcessing = true; _statusLog = "Memproses..."; });

    final dir = await getExternalStorageDirectory();
    String outFile = "${dir!.path}/output.mp4";

    // Command FFmpeg Simple
    String cmd = "-y -i \"$_selectedVideoPath\" -c copy \"$outFile\"";

    await FFmpegKit.execute(cmd).then((session) async {
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        setState(() => _statusLog = "Sukses! Disimpan di $outFile");
      } else {
        String? logs = await session.getLogsAsString();
        print(logs);
        setState(() => _statusLog = "Gagal. Cek Log.");
      }
      setState(() => _isProcessing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Komitan Kutter (Stabil)")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(onPressed: _pickVideo, child: const Text("Pilih Video")),
            const SizedBox(height: 20),
            if (_selectedVideoPath != null)
              ElevatedButton(
                onPressed: _isProcessing ? null : _startProcessing,
                child: const Text("Mulai Potong")
              ),
            const SizedBox(height: 20),
            Text(_statusLog, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
