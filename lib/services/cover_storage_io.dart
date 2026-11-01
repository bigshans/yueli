import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 保存上传的封面，返回本地绝对路径。
Future<String?> saveCoverFile(Uint8List bytes, String fileName) async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/covers');
  await dir.create(recursive: true);
  final ext = _extension(fileName);
  final name = 'cover_${DateTime.now().microsecondsSinceEpoch}$ext';
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> deleteCoverFile(String? path) async {
  if (path == null || path.isEmpty || path.startsWith('data:image')) return;
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

String _extension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '.jpg';
  final ext = fileName.substring(dot).toLowerCase();
  const allowed = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
  return allowed.contains(ext) ? ext : '.jpg';
}
