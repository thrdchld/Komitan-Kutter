import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
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
  
  @override
  void initState() {
    super.initState();
    FFmpegKitConfig.enableLogCallback((log) {});
  }

  Future<void> cut() async {
    if (Platform.isAndroid) {
      await [Permission.storage, Permission.videos, Permission.audio].request();
    }

    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null) return;

    setState(() => status = "Memproses...");
    final path = res.files.single.path!;
    final dir = await getApplicationDocumentsDirectory();
    final out = "\${dir.path}/out_\${DateTime.now().millisecondsSinceEpoch}.mp4";

    final session = await FFmpegKit.execute('-y -ss 0 -t 5 -i "$path" -c copy "$out"');
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      setState(() => status = "Selesai: $out");
      OpenFile.open(out);
    } else {
      setState(() => status = "Gagal memproses (kode: \$returnCode)");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Komitan Kutter")),
      body: Center(child: ElevatedButton(onPressed: cut, child: Text(status))),
    );
  }
}
