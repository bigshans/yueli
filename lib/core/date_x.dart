import 'package:intl/intl.dart';

/// 把任意时间归一化到「当天零点」，用作纯日期。
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// 今天（本地时区，零点）。这里指自然日；需要按用户设置的结算时间
/// 归属日期时请使用 [logicalDate]。
DateTime today([DateTime? now]) => dateOnly(now ?? DateTime.now());

/// 用户设置的每日结算时间（0:00 起的分钟数）。例如 240 表示凌晨 4:00
/// 开始新的一天，4:00 前的阅读仍属于前一天。
int clampSettlementMinutes(int minutes) => minutes.clamp(0, 24 * 60 - 1);

/// 某一天在结算时间下的起点。
DateTime logicalDayStart(DateTime date, [int settlementMinutes = 0]) {
  final d = dateOnly(date);
  final m = clampSettlementMinutes(settlementMinutes);
  return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
}

/// 把真实时刻映射到它所属的「结算日」（零点）。
///
/// 默认 0:00 结算，等同于自然日；设置为 4:00 时，凌晨 3:59 仍算前一天。
DateTime logicalDate(DateTime instant, [int settlementMinutes = 0]) {
  final d = dateOnly(instant);
  final start = logicalDayStart(d, settlementMinutes);
  return instant.isBefore(start) ? addDays(d, -1) : d;
}

/// 把分钟数格式化为 HH:mm，用于设置页展示。
String formatSettlementTime(int settlementMinutes) {
  final m = clampSettlementMinutes(settlementMinutes);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

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
