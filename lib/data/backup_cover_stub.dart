/// Web 端没有本地文件路径；data URI 直接复用。
Future<String?> readCoverDataUri(String? path) async {
  final value = path?.trim();
  if (value == null || value.isEmpty) return null;
  return value.startsWith('data:image') ? value : null;
}
