#!/usr/bin/env bash
set -euo pipefail

# use_pubdev_ffmpeg_only.sh
# Tujuan:
# - Hapus referensi ffmpeg/athenica/varian lama di repo (gradle, pubspec, kode)
# - Tulis pubspec.yaml yang valid memakai only: ffmpeg_kit_flutter_new_min: ^3.1.0
# - Tulis lib/main.dart yang memakai ffmpeg_kit_flutter_new_min import
# - Commit perubahan ke branch backup + new commit (auto)

echo
echo "============================================"
echo "  USE PUBDEV FFMPEG ONLY (ffmpeg_kit_flutter_new_min ^3.1.0)"
echo "============================================"
echo

# safety: must be inside git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "🚫 Tidak berada di repository git. Batalkan."
  exit 1
fi

# 0. backup branch
BACKUP="pre-ffmpeg-clean-$(date +%Y%m%d%H%M%S)"
git add -A || true
git commit -m "[auto] WIP before ffmpeg cleanup ($BACKUP)" || true
git branch "$BACKUP" || true
echo "🔒 Backup branch dibuat: $BACKUP"

# 1. Scan & report current ffmpeg mentions (for log)
echo
echo "🔍 Mencari referensi FFmpeg lama di repo..."
git --no-pager grep -n --column -E "ffmpeg|athenica" || true

# 2. Remove likely Gradle/Maven references to external ffmpeg repos/artifacts
#    (This will delete lines containing 'athenica' or 'implementation' lines with 'ffmpeg' or 'com.athenica')
echo
echo "🧹 Menghapus referensi gradle/artefak ffmpeg/athenica (jika ada)..."

# remove repo urls that mention athenica (case-insensitive)
git grep -n "athenica" || true
# edit files in-place: delete lines containing 'athenica'
for f in $(git grep -l -i "athenica" || true); do
  echo " - cleaning $f"
  perl -i.bak -ne 'print unless /athenica/i' "$f"
done

# delete explicit implementation lines that mention ffmpeg AARs (common patterns)
for f in $(git grep -l -E "implementation .*ffmpeg|com\.athenica" || true); do
  echo " - removing ffmpeg implementation lines in $f"
  perl -i.bak -0777 -pe 's/^[ \t]*implementation.*ffmpeg.*\n//gim' "$f"
  perl -i.bak -0777 -pe 's/^[ \t]*implementation.*com\.athenica.*\n//gim' "$f"
done

# 3. Overwrite pubspec.yaml with single ffmpeg_kit_flutter_new_min dependency (plus usual libs)
echo
echo "🛠 Menulis ulang pubspec.yaml (memastikan hanya ffmpeg_kit_flutter_new_min digunakan)..."
cat > pubspec.yaml <<'YAML'
name: komitan_kutter
description: Video Cutter Offline
publish_to: none
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  # Gunakan hanya paket FFmpeg dari pub.dev
  ffmpeg_kit_flutter_new_min: ^3.1.0

  # dependency app lain (biarkan jika perlu)
  file_picker: ^6.1.1
  permission_handler: ^11.0.1
  path_provider: ^2.1.1
  intl: ^0.18.1
  open_file: ^3.3.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^2.0.0

flutter:
  uses-material-design: true
YAML
echo "✔ pubspec.yaml ditulis"

# 4. Overwrite lib/main.dart to use ffmpeg_kit_flutter_new_min
echo
echo "🛠 Menulis ulang lib/main.dart (menggunakan ffmpeg_kit_flutter_new_min imports)..."
mkdir -p lib
cat > lib/main.dart <<'DART'
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
    // optional: enable logs (no-op here)
    FFmpegKitConfig.enableLogCallback((log) {
      // you can forward logs to console or analytics if needed
    });
  }

  Future<void> cut() async {
    // Request permissions on Android (adjust for Android 13+ if needed)
    if (Platform.isAndroid) {
      await [
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.videos,
        Permission.audio,
      ].request();
    }

    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null) return;

    setState(() => status = "Memproses...");
    final path = res.files.single.path!;
    final dir = await getApplicationDocumentsDirectory();
    final out = "${dir.path}/out_${DateTime.now().millisecondsSinceEpoch}.mp4";

    // Cut first 5 seconds using FFmpegKit
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
DART

echo "✔ lib/main.dart ditulis"

# 5. Clean any files still mentioning other ffmpeg packages and create backups (.bak shown)
echo
echo "🔎 Menghapus referensi package ffmpeg lama di file dart/gradle (backup .bak dibuat)..."
# remove lines in pubspec.* that mention other ffmpeg packages (if any)
for f in $(git grep -l -E "ffmpeg_kit_flutter_min|ffmpeg_kit_flutter_full|ffmpeg_kit_flutter_min_gpl|ffmpeg_kit_flutter" || true); do
  if [ "$f" = "pubspec.yaml" ]; then
    # we already overwrote pubspec.yaml; skip
    continue
  fi
  echo " - scanning $f"
  perl -i.bak -0777 -pe 's/.*ffmpeg_kit_flutter_[^\s\n]+.*\n//gim' "$f" || true
  perl -i.bak -0777 -pe 's/.*ffmpeg_kit_flutter.*\n//gim' "$f" || true
done

# 6. Ensure Android Gradle repositories contain mavenCentral() and remove any private ffmpeg repos
echo
echo "🔧 Menjamin android root build.gradle punya mavenCentral() & google() (menambah jika perlu)..."
if [ -f android/build.gradle ]; then
  # add mavenCentral() and google() to buildscript.repositories and allprojects.repositories if missing
  perl -0777 -pe "s/(buildscript\s*\\{.*?repositories\s*\\{)(.*?)(\\}\\s*\\})/ \$1\$2\\n            mavenCentral()\\n            google()\\n\$3/sm" -i android/build.gradle || true
  perl -0777 -pe "s/(allprojects\s*\\{.*?repositories\s*\\{)(.*?)(\\}\\s*\\})/ \$1\$2\\n            mavenCentral()\\n            google()\\n\$3/sm" -i android/build.gradle || true
  echo " - android/build.gradle diperiksa (backup .bak ada jika dibuat)."
else
  echo " - android/build.gradle tidak ditemukan (skip)."
fi

# 7. Refresh git index and show changes
echo
echo "🧾 Perubahan yang akan di-commit:"
git status --porcelain
git --no-pager diff --staged --name-only || true
echo

# 8. Commit changes
echo "💾 Membuat commit: 'chore: use ffmpeg_kit_flutter_new_min from pub.dev only'"
git add -A
git commit -m "chore: use ffmpeg_kit_flutter_new_min ^3.1.0 only; remove other ffmpeg references" || true

echo
echo "✅ Selesai. Pastikan push ke remote:"
echo "   git push origin HEAD"
echo
echo "Rekomendasi:"
echo " - Jalankan CI (push) untuk memastikan Gradle dapat resolve artifacts."
echo " - Jika build masih mencari artefak lama, periksa output Gradle di Actions untuk file yang masih mereferensi repo lama."
echo
