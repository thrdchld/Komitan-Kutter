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
