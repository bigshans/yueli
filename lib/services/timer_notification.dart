import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 把正在进行的阅读计时显示为系统通知栏常驻通知。
///
/// 计时「正在跑」时使用 Android 原生 chronometer，由系统实时走秒，
/// 因此息屏 / 切后台也会继续显示，不需要我们频繁刷新。
/// 所有调用都是尽力而为：平台不支持或缺少权限时静默失败。
class TimerNotificationService {
  TimerNotificationService._();
  static final TimerNotificationService instance = TimerNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _id = 4711;
  static const String _channelId = 'reading_timer';
  static const String _channelName = '阅读计时';

  bool _ready = false;
  bool _initTried = false;

  static String _fmt(int seconds) {
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> init() async {
    if (_initTried) return;
    _initTried = true;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: '显示正在进行的阅读计时',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 请求通知权限（Android 13+ / iOS）。首次进入时调用。
  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: false, sound: false);
    } catch (_) {
      // 忽略
    }
  }

  AndroidNotificationDetails _details({required bool running, int elapsed = 0}) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: '显示正在进行的阅读计时',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
      silent: true,
      onlyAlertOnce: true,
      channelShowBadge: false,
      showWhen: running,
      usesChronometer: running,
      when: running
          ? DateTime.now()
              .subtract(Duration(seconds: elapsed))
              .millisecondsSinceEpoch
          : null,
    );
  }

  Future<void> showRunning({
    required String bookTitle,
    required int elapsedSeconds,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id,
        title: '正在阅读《$bookTitle》',
        body: '点击回到应用',
        notificationDetails: NotificationDetails(
          android: _details(running: true, elapsed: elapsedSeconds),
        ),
      );
    } catch (_) {
      // 忽略
    }
  }

  Future<void> showPaused({
    required String bookTitle,
    required int elapsedSeconds,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _id,
        title: '已暂停 · 用时 ${_fmt(elapsedSeconds)}',
        body: '《$bookTitle》',
        notificationDetails: NotificationDetails(
          android: _details(running: false),
        ),
      );
    } catch (_) {
      // 忽略
    }
  }

  Future<void> cancel() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {
      // 忽略
    }
  }
}
