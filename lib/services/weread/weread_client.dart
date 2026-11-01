import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 微信读书官方 Agent API Gateway 客户端。
///
/// 规范：
/// - POST https://i.weread.qq.com/api/agent/gateway
/// - Authorization: Bearer `apiKey`
/// - body 中 api_name、skill_version 与业务参数平铺
/// - 业务错误看响应体 errcode，不能只看 HTTP 状态码
class WereadClient {
  WereadClient({
    http.Client? httpClient,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client(),
       endpoint = endpoint ?? Uri.parse(_defaultEndpoint);

  static const _defaultEndpoint = 'https://i.weread.qq.com/api/agent/gateway';
  // 对应官方 weread-skills 1.0.5（Tencent/WeChatReading）。
  static const skillVersion = '1.0.5';

  final http.Client _http;
  final Uri endpoint;
  final Duration timeout;

  /// 调用任意 Gateway 接口，返回解析后的 JSON Map。
  Future<Map<String, dynamic>> call(
    String apiName, {
    required String apiKey,
    Map<String, Object?> params = const {},
  }) async {
    final key = apiKey.trim();
    _validateApiKeyFormat(key);

    final payload = <String, Object?>{
      'api_name': apiName,
      'skill_version': skillVersion,
      ...params,
    };

    http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $key',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const WereadNetworkException('连接微信读书超时，请稍后重试');
    } on http.ClientException catch (e) {
      throw WereadNetworkException(_networkMessage(e.message));
    } catch (e) {
      throw WereadNetworkException(_networkMessage(e.toString()));
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const WereadAuthException('API Key 无效或已过期，请重新生成');
    }

    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('响应不是 JSON 对象');
      }
      decoded = value;
    } on FormatException {
      throw WereadHttpException(response.statusCode, '微信读书返回了无法解析的数据');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WereadHttpException(
        response.statusCode,
        _messageOf(decoded) ?? '微信读书请求失败（HTTP ${response.statusCode}）',
      );
    }

    final upgrade = decoded['upgrade_info'];
    if (upgrade != null && upgrade != false) {
      final message = upgrade is Map
          ? (upgrade['message']?.toString() ?? '').trim()
          : upgrade.toString().trim();
      throw WereadUpgradeException(
        message.isEmpty ? '微信读书 Skill 需要升级，请更新后再同步' : message,
      );
    }

    final errcode = _asInt(decoded['errcode']);
    if (errcode != null && errcode != 0) {
      final message = _messageOf(decoded) ?? '微信读书返回错误（errcode $errcode）';
      if (errcode == 401 || errcode == 403 || errcode == -2012) {
        throw WereadAuthException(message);
      }
      throw WereadApiException(errcode, message);
    }

    return decoded;
  }

  /// 拉取书架电子书列表。albums/mp 暂不导入。
  Future<List<WereadShelfBook>> fetchShelf(String apiKey) async {
    final data = await call('/shelf/sync', apiKey: apiKey);
    final books = data['books'];
    if (books is! List) return const [];
    return [
      for (final item in books)
        if (item is Map<String, dynamic>) WereadShelfBook.fromJson(item),
    ];
  }

  /// 获取单本书的元数据。
  Future<WereadBookInfo> fetchBookInfo(
    String apiKey, {
    required String bookId,
  }) async {
    final data = await call(
      '/book/info',
      apiKey: apiKey,
      params: {'bookId': bookId},
    );
    return WereadBookInfo.fromJson(data);
  }

  /// 获取单本书的阅读进度。
  Future<WereadProgress> fetchProgress(
    String apiKey, {
    required String bookId,
  }) async {
    final data = await call(
      '/book/getprogress',
      apiKey: apiKey,
      params: {'bookId': bookId},
    );
    final book = data['book'];
    return WereadProgress.fromJson(
      book is Map<String, dynamic> ? book : const {},
      bookId: bookId,
    );
  }

  /// 通过 /shelf/sync 验证 Key。成功时顺带返回书架概览。
  Future<WereadShelfSummary> validateApiKey(String apiKey) async {
    final data = await call('/shelf/sync', apiKey: apiKey);
    final books = data['books'];
    final albums = data['albums'];
    final mp = data['mp'];
    final bookCount = books is List ? books.length : 0;
    final albumCount = albums is List ? albums.length : 0;
    final hasMp =
        mp != null &&
        mp != false &&
        (mp is! Map || mp.isNotEmpty) &&
        (mp is! List || mp.isNotEmpty);
    return WereadShelfSummary(
      bookCount: bookCount,
      albumCount: albumCount,
      hasMp: hasMp,
    );
  }

  void close() => _http.close();

  static void _validateApiKeyFormat(String key) {
    if (key.isEmpty) {
      throw const WereadAuthException('请先填写微信读书 API Key');
    }
    if (key.contains('upgrade_url') ||
        key.contains('SKILL.md') ||
        key.contains('Skill 有新版本')) {
      throw const WereadAuthException(
        '这是微信读书 Skill 的升级提示，不是 API Key。'
        '请到 weread.qq.com/r/weread-skills 重新获取以 wrk- 开头的 Key。',
      );
    }
    if (!RegExp(r'^[\x21-\x7E]+$').hasMatch(key)) {
      throw const WereadAuthException(
        'API Key 格式不正确：只能包含英文字母、数字和符号，不能包含空格或中文。'
        '请粘贴以 wrk- 开头的 Key。',
      );
    }
    if (key.length > 512) {
      throw const WereadAuthException('API Key 过长，请确认只粘贴了 Key 本身。');
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _messageOf(Map<String, dynamic> data) {
    for (final key in const ['errmsg', 'message', 'msg']) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

String _networkMessage(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('failed host lookup') ||
      text.contains('nodename nor servname') ||
      text.contains('no address associated')) {
    return '无法解析微信读书服务器域名。'
        '请检查手机网络、DNS 或代理设置；如果使用正式版，请确认应用有网络权限。';
  }
  if (text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('network is unreachable')) {
    return '无法连接微信读书服务器，请检查网络或代理设置。';
  }
  return '连接微信读书失败：$raw';
}

Map<String, dynamic> _bookPayload(Map<String, dynamic> json) {
  final nested = json['bookInfo'];
  if (nested is Map<String, dynamic>) return nested;
  return json;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _string(json[key]);
    if (value != null) return value;
  }
  return null;
}

String? _string(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  return null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool _boolish(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.toLowerCase();
    return text == '1' || text == 'true';
  }
  return false;
}

DateTime? _dateTimeFromSeconds(Object? value) {
  final seconds = _int(value);
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

String? _publishDate(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  final date = _dateTimeFromSeconds(value);
  if (date == null) return null;
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

class WereadShelfBook {
  const WereadShelfBook({
    required this.bookId,
    required this.title,
    this.author,
    this.cover,
    this.category,
    this.readerLink,
    this.deepLink,
    this.readUpdateTime,
    this.finishReading = false,
  });

  final String bookId;
  final String title;
  final String? author;
  final String? cover;
  final String? category;
  final String? readerLink;
  final String? deepLink;
  final DateTime? readUpdateTime;
  final bool finishReading;

  factory WereadShelfBook.fromJson(Map<String, dynamic> json) {
    final data = _bookPayload(json);
    return WereadShelfBook(
      bookId: _string(data['bookId']) ?? '',
      title: _string(data['title']) ?? '未命名书籍',
      author: _string(data['author']),
      cover: _string(data['cover']),
      category: _string(data['category']),
      readerLink: _firstString(data, const [
        'readerLink',
        'reader_link',
        'readerUrl',
        'reader_url',
      ]),
      deepLink: _firstString(data, const [
        'deepLink',
        'deep_link',
        'deepUrl',
        'deep_url',
      ]),
      readUpdateTime: _dateTimeFromSeconds(data['readUpdateTime']),
      finishReading: _boolish(data['finishReading']),
    );
  }
}

class WereadBookInfo {
  const WereadBookInfo({
    required this.bookId,
    required this.title,
    this.author,
    this.translator,
    this.cover,
    this.intro,
    this.category,
    this.publisher,
    this.publishDate,
    this.isbn,
    this.wordCount,
    this.rating,
    this.ratingCount,
    this.readerLink,
    this.deepLink,
  });

  final String bookId;
  final String title;
  final String? author;
  final String? translator;
  final String? cover;
  final String? intro;
  final String? category;
  final String? publisher;
  final String? publishDate;
  final String? isbn;
  final int? wordCount;

  /// 官方 newRating 是百分制，0-100。
  final double? rating;
  final int? ratingCount;
  final String? readerLink;
  final String? deepLink;

  factory WereadBookInfo.fromJson(Map<String, dynamic> json) {
    final data = _bookPayload(json);
    return WereadBookInfo(
      bookId: _string(data['bookId']) ?? '',
      title: _string(data['title']) ?? '未命名书籍',
      author: _string(data['author']),
      translator: _string(data['translator']),
      cover: _string(data['cover']),
      intro: _string(data['intro']),
      category: _string(data['category']),
      publisher: _string(data['publisher']),
      publishDate: _publishDate(data['publishTime']),
      isbn: _string(data['isbn']),
      wordCount: _int(data['wordCount']),
      rating: _double(data['newRating']),
      ratingCount: _int(data['newRatingCount']),
      readerLink: _firstString(data, const [
        'readerLink',
        'reader_link',
        'readerUrl',
        'reader_url',
      ]),
      deepLink: _firstString(data, const [
        'deepLink',
        'deep_link',
        'deepUrl',
        'deep_url',
      ]),
    );
  }
}

class WereadProgress {
  const WereadProgress({
    required this.bookId,
    required this.progress,
    this.recordReadingTime = 0,
    this.updateTime,
    this.finishTime,
  });

  final String bookId;

  /// 0-100。只有 100 且有 finishTime 才表示读完。
  final int progress;
  final int recordReadingTime;
  final DateTime? updateTime;
  final DateTime? finishTime;

  factory WereadProgress.fromJson(
    Map<String, dynamic> json, {
    required String bookId,
  }) {
    return WereadProgress(
      bookId: bookId,
      progress: (_int(json['progress']) ?? 0).clamp(0, 100),
      recordReadingTime: _int(json['recordReadingTime']) ?? 0,
      updateTime: _dateTimeFromSeconds(json['updateTime']),
      finishTime: _dateTimeFromSeconds(json['finishTime']),
    );
  }
}

class WereadShelfSummary {
  const WereadShelfSummary({
    required this.bookCount,
    this.albumCount = 0,
    this.hasMp = false,
  });

  /// 电子书数量（books[]）。
  final int bookCount;

  /// 专辑/有声书数量（albums[]）。
  final int albumCount;

  /// 是否有文章收藏入口（mp 非空）。
  final bool hasMp;

  /// 官方口径：books + albums + (mp 非空 ? 1 : 0)。
  int get totalCount => bookCount + albumCount + (hasMp ? 1 : 0);
}

sealed class WereadException implements Exception {
  const WereadException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WereadAuthException extends WereadException {
  const WereadAuthException(super.message);
}

class WereadUpgradeException extends WereadException {
  const WereadUpgradeException(super.message);
}

class WereadApiException extends WereadException {
  const WereadApiException(this.code, super.message);
  final int code;
}

class WereadHttpException extends WereadException {
  const WereadHttpException(this.statusCode, super.message);
  final int statusCode;
}

class WereadNetworkException extends WereadException {
  const WereadNetworkException(super.message);
}
