import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class WereadLinkException implements Exception {
  const WereadLinkException(this.message);
  final String message;

  @override
  String toString() => message;
}

bool get isMobileWereadPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// 移动端优先用 readerLink 唤起 App；PC/Web 优先用 http(s) 网页链接。
///
/// 如果接口没有返回链接，则使用微信读书的固定规则兜底：
/// - App：`weread://reading?bId=<bookId>`
/// - 网页：`https://weread.qq.com/web/reader/<bookHash>`
String? pickWereadOpenLink({
  String? readerLink,
  String? deepLink,
  String? bookId,
  required bool mobile,
}) {
  final reader = _nonEmpty(readerLink);
  final deep = _nonEmpty(deepLink);
  final id = _nonEmpty(bookId);
  if (mobile) {
    // 接口返回的 readerLink 常常是 https 网页地址；移动端应强制走 App 深链。
    if (id != null) return wereadAppDeepLink(id);
    return reader ?? deep;
  }
  return _httpLink(reader) ??
      _httpLink(deep) ??
      (id == null ? null : wereadWebReaderUrl(id));
}

Future<void> openWereadBookLink({
  String? readerLink,
  String? deepLink,
  String? bookId,
}) async {
  final mobile = isMobileWereadPlatform;
  final link = pickWereadOpenLink(
    readerLink: readerLink,
    deepLink: deepLink,
    bookId: bookId,
    mobile: mobile,
  );
  if (link == null) {
    throw WereadLinkException(mobile ? '微信读书没有返回可打开的应用链接' : '微信读书没有返回网页链接');
  }
  final uri = Uri.tryParse(link);
  if (uri == null) {
    throw const WereadLinkException('微信读书返回的链接格式不正确');
  }
  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
  if (!ok) {
    throw WereadLinkException(mobile ? '没有找到可以打开微信读书的应用' : '无法打开微信读书网页');
  }
}

/// 微信读书 App 的书籍阅读深链。
String wereadAppDeepLink(String bookId) => 'weread://reading?bId=$bookId';

/// 微信读书网页阅读器链接。bookHash 使用微信读书的 `_e(bookId)` 规则。
String wereadWebReaderUrl(String bookId) =>
    'https://weread.qq.com/web/reader/${wereadBookHash(bookId)}';

/// 复刻微信读书 Web 端的 `_e(bookId)`。
String wereadBookHash(String bookId) {
  final digest = md5.convert(utf8.encode(bookId)).toString();
  final encoded = _encodeBookId(bookId);
  var result = digest.substring(0, 3);
  result += encoded.$1;
  result += '2${digest.substring(digest.length - 2)}';
  for (var i = 0; i < encoded.$2.length; i++) {
    final chunk = encoded.$2[i];
    final length = chunk.length.toRadixString(16);
    result += length.length == 1 ? '0$length' : length;
    result += chunk;
    if (i < encoded.$2.length - 1) result += 'g';
  }
  if (result.length < 20) {
    result += digest.substring(0, 20 - result.length);
  }
  result += md5.convert(utf8.encode(result)).toString().substring(0, 3);
  return result;
}

(String, List<String>) _encodeBookId(String value) {
  if (RegExp(r'^\d*$').hasMatch(value)) {
    final chunks = <String>[];
    for (var i = 0; i < value.length; i += 9) {
      final end = i + 9 < value.length ? i + 9 : value.length;
      final part = value.substring(i, end);
      chunks.add(int.parse(part, radix: 10).toRadixString(16));
    }
    return ('3', chunks);
  }
  final buffer = StringBuffer();
  for (final code in value.codeUnits) {
    buffer.write(code.toRadixString(16));
  }
  return ('4', [buffer.toString()]);
}

String? _nonEmpty(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

String? _httpLink(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? value : null;
}
