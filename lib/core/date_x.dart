import 'package:intl/intl.dart';

/// 把任意时间归一化到「当天零点」，用作纯日期。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 今天（本地时区，零点）。
DateTime today([DateTime? now]) => dateOnly(now ?? DateTime.now());

/// 在日期上加减天数，用组件构造以避开夏令时导致的偏移。
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// 取较晚的一天。
DateTime maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// 闭区间 [start, end] 上每一天（零点）的序列，DST 安全。
Iterable<DateTime> dateRange(DateTime start, DateTime end) sync* {
  var d = dateOnly(start);
  final e = dateOnly(end);
  while (!d.isAfter(e)) {
    yield d;
    d = addDays(d, 1);
  }
}

String formatDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

String formatDateCn(DateTime d) => DateFormat('M月d日 EEE', 'zh_CN').format(d);

String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes 分钟';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h 小时' : '$h 小时 $m 分';
}
