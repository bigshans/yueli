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
String? pickWereadOpenLink({
  String? readerLink,
  String? deepLink,
  required bool mobile,
}) {
  final reader = _nonEmpty(readerLink);
  final deep = _nonEmpty(deepLink);
  if (mobile) return reader ?? deep;
  return _httpLink(reader) ?? _httpLink(deep);
}

Future<void> openWereadBookLink({String? readerLink, String? deepLink}) async {
  final mobile = isMobileWereadPlatform;
  final link = pickWereadOpenLink(
    readerLink: readerLink,
    deepLink: deepLink,
    mobile: mobile,
  );
  if (link == null) {
    throw WereadLinkException(
      mobile ? '微信读书没有返回可打开的应用链接' : '微信读书没有返回网页链接，无法在当前设备打开',
    );
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
