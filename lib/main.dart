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
