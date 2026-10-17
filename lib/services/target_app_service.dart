import 'package:flutter/foundation.dart';
import 'package:installed_apps/installed_apps.dart';

/// 安卓端「计时时自动打开指定应用」。
///
/// 非安卓平台或缺少平台插件时静默失败，不影响计时。
class TargetAppService {
  TargetAppService._();

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 已安装且可启动的应用（带图标），按名称排序。
  static Future<List<AppInfo>> installedApps() async {
    if (!isAndroid) return const [];
    try {
      final apps = await InstalledApps.getInstalledApps(
        excludeSystemApps: true,
        excludeNonLaunchableApps: true,
        withIcon: true,
      );
      apps.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return apps;
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> open(String packageName) async {
    if (!isAndroid) return false;
    try {
      final ok = await InstalledApps.startApp(packageName);
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }
}
