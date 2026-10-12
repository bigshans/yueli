import 'dart:math';

import '../../core/date_x.dart';

/// 无截止日时，最多向后排多少天，避免无限生成任务。
const int kNoDeadlineHorizonDays = 366;

/// 排期输入：描述「还剩多少页、要在什么约束下读完」。
class ScheduleInput {
  const ScheduleInput({
    required this.currentPage,
    required this.totalPages,
    required this.startDate,
    required this.deadline,
    required this.dailyMinutes,
    required this.weekdays,
    required this.pagesPerHour,
    this.dailyPages,
  });

  final int currentPage;
  final int totalPages;
  final DateTime startDate;

  /// 为空表示不设截止日：按每日容量一直排到读完。
  final DateTime? deadline;

  /// 按时间排期时每天可投入的分钟数。
  final int dailyMinutes;

  /// 页数优先：每个阅读日要读多少页。非空时忽略 [dailyMinutes]。
  final int? dailyPages;

  /// ISO 星期：1=周一 .. 7=周日。
  final Set<int> weekdays;
  final int pagesPerHour;
}

/// 一个排出来的每日任务（不含数据库 id）。
class ScheduledTask {
  const ScheduledTask({
    required this.date,
    required this.startPage,
    required this.endPage,
    required this.plannedMinutes,
  });

  final DateTime date;
  final int startPage;
  final int endPage;
  final int plannedMinutes;

  int get pages => endPage - startPage + 1;
}

/// 排期结果，附带可行性与预估信息。
class ScheduleResult {
  const ScheduleResult({
    required this.tasks,
    required this.remainingPages,
    required this.pagesPerReadingDay,
    required this.capacityPagesPerDay,
    required this.readingDays,
    required this.hasDeadline,
  });

  final List<ScheduledTask> tasks;
  final int remainingPages;

  /// 每个阅读日的目标页数（有截止日=均摊值，无截止日=每日容量）。
  final int pagesPerReadingDay;

  /// 按每日时长与阅读速度，每个阅读日最多能读多少页。
  final int capacityPagesPerDay;

  /// 可用的阅读日数量。
  final int readingDays;
  final bool hasDeadline;

  int get assignedPages => tasks.fold(0, (sum, t) => sum + t.pages);

  /// 需要但未排入的页数。
  int get unassignedPages => max(0, remainingPages - assignedPages);

  /// 是否在期限内排不下（无截止日时永远为 false）。
  bool get oversubscribed => hasDeadline && unassignedPages > 0;

  /// 预计读完的日期（最后一个任务所在日）。
  DateTime? get estimatedFinish => tasks.isEmpty ? null : tasks.last.date;

  /// 预计完成所需天数（阅读日）。
  int get totalReadingDaysNeeded => tasks.length;
}

/// 核心排期算法：把剩余页数摊到可用阅读日。
///
/// - 有截止日：每天页数 = ceil(剩余页数 / 可用阅读天数)，受每日容量上限约束；
///   容量不足以按期读完时标记 oversubscribed。
/// - 无截止日：每个阅读日按每日容量排，一直排到读完（最多 [kNoDeadlineHorizonDays] 天）。
/// - [from] 给出「最早可排日」（默认今天），用于完成当天任务后从次日续排。
ScheduleResult buildSchedule(ScheduleInput input, {DateTime? from}) {
  final lower = dateOnly(from ?? DateTime.now());
  final remaining = input.totalPages - input.currentPage;
  final capacity = (input.dailyMinutes / 60.0 * input.pagesPerHour).floor();
  final hasDeadline = input.deadline != null;
  final byPages = input.dailyPages != null && input.dailyPages! > 0;

  ScheduleResult empty() => ScheduleResult(
        tasks: const [],
        remainingPages: max(0, remaining),
        pagesPerReadingDay: 0,
        capacityPagesPerDay: capacity,
        readingDays: 0,
        hasDeadline: hasDeadline,
      );

  if (remaining <= 0) return empty();

  final start = maxDate(input.startDate, lower);
  final end = hasDeadline
      ? input.deadline!
      : addDays(start, kNoDeadlineHorizonDays);
  final days = readingDays(start: start, end: end, weekdays: input.weekdays);

  // 页数优先模式不依赖每日时长，故 capacity 为 0 也能排。
  if (days.isEmpty || (!byPages && capacity <= 0)) return empty();

  final target = byPages
      ? input.dailyPages!
      : (hasDeadline ? (remaining / days.length).ceil() : capacity);

  final tasks = <ScheduledTask>[];
  var page = input.currentPage;
  for (final day in days) {
    if (page >= input.totalPages) break;
    var pages = min(target, input.totalPages - page);
    if (!byPages) pages = min(pages, capacity);
    if (pages <= 0) continue;
    final startPage = page + 1;
    final endPage = page + pages;
    final minutes = (pages / input.pagesPerHour * 60).ceil();
    tasks.add(ScheduledTask(
      date: day,
      startPage: startPage,
      endPage: endPage,
      plannedMinutes: max(minutes, 1),
    ));
    page += pages;
  }

  return ScheduleResult(
    tasks: tasks,
    remainingPages: remaining,
    pagesPerReadingDay: target,
    capacityPagesPerDay: capacity,
    readingDays: days.length,
    hasDeadline: hasDeadline,
  );
}

/// [start, end] 闭区间内、星期落在 [weekdays] 的日期列表。
List<DateTime> readingDays({
  required DateTime start,
  required DateTime end,
  required Set<int> weekdays,
}) {
  if (weekdays.isEmpty) return const [];
  final s = dateOnly(start);
  final e = dateOnly(end);
  if (s.isAfter(e)) return const [];
  return dateRange(s, e).where((d) => weekdays.contains(d.weekday)).toList();
}
