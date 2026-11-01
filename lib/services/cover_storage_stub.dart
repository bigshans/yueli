import 'dart:convert';
import 'dart:typed_data';

/// Web 端没有可写文件系统，把图片存成 data URI，随数据库/备份保存。
Future<String?> saveCoverFile(Uint8List bytes, String fileName) async {
  final mime = _mimeType(fileName);
  return 'data:$mime;base64,${base64Encode(bytes)}';
}

Future<void> deleteCoverFile(String? path) async {}

String _mimeType(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  return 'image/jpeg';
}
