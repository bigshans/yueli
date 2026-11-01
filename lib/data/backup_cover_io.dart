import 'dart:convert';
import 'dart:io';

/// 把本地上传的封面转成 data URI，便于完整写入 JSON 备份。
/// 已经是 data URI 的封面直接返回。
Future<String?> readCoverDataUri(String? path) async {
  final value = path?.trim();
  if (value == null || value.isEmpty) return null;
  if (value.startsWith('data:image')) return value;
  final file = File(value);
  if (!await file.exists()) return null;
  try {
    final bytes = await file.readAsBytes();
    return 'data:${_mimeType(value)};base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

String _mimeType(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  return 'image/jpeg';
}
