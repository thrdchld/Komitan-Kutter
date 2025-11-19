import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
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
    // Request multiple permissions for Android 13+ compliance
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.videos,
        Permission.audio,
      ].request();
    }

    var res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res != null) {
      setState(() => status = "Memproses...");
      String path = res.files.single.path!;
      
      final dir = await getApplicationDocumentsDirectory();
      String out = "${dir.path}/out_${DateTime.now().millisecondsSinceEpoch}.mp4";
      
      // Cut 5 detik pertama
      await FFmpegKit.execute("-y -ss 0 -t 5 -i \"$path\" -c copy \"$out\"");
      
      setState(() => status = "Selesai: $out");
      OpenFile.open(out);
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
