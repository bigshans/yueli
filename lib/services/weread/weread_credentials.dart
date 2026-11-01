import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 微信读书 API Key 的安全存储，不进入数据库和备份。
class WereadCredentials {
  WereadCredentials({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _apiKeyName = 'weread_api_key';

  final FlutterSecureStorage _storage;

  Future<String?> readApiKey() async {
    final value = await _storage.read(key: _apiKeyName);
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveApiKey(String apiKey) async {
    final value = apiKey.trim();
    if (value.isEmpty) {
      await clearApiKey();
      return;
    }
    await _storage.write(key: _apiKeyName, value: value);
  }

  Future<void> clearApiKey() => _storage.delete(key: _apiKeyName);
}
