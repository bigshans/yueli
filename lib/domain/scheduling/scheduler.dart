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
    this.restDates = const {},
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

  /// 指定休息的日子（不排阅读）。
  final Set<DateTime> restDates;

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
  final days = readingDays(
    start: start,
    end: end,
    weekdays: input.weekdays,
    except: input.restDates,
  );

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
    tasks.add(
      ScheduledTask(
        date: day,
        startPage: startPage,
        endPage: endPage,
        plannedMinutes: max(minutes, 1),
      ),
    );
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

/// [start, end] 闭区间内、星期落在 [weekdays]、且不在 [except] 中的日期列表。
List<DateTime> readingDays({
  required DateTime start,
  required DateTime end,
  required Set<int> weekdays,
  Set<DateTime> except = const {},
}) {
  if (weekdays.isEmpty) return const [];
  final s = dateOnly(start);
  final e = dateOnly(end);
  if (s.isAfter(e)) return const [];
  return dateRange(
    s,
    e,
  ).where((d) => weekdays.contains(d.weekday) && !except.contains(d)).toList();
}

/// 计划的进度投影：领先/落后、预计读完。
class PlanProgress {
  const PlanProgress({
    required this.hasDeadline,
    this.aheadPages,
    this.estimatedFinish,
    this.pagesPerReadingDay = 0,
  });

  final bool hasDeadline;

  /// >0 领先计划，<0 落后计划（页）。无截止日时为 null。
  final int? aheadPages;
  final DateTime? estimatedFinish;
  final int pagesPerReadingDay;
}

/// 按当前进度重新投影：与「从开始日到截止日均匀推进」的理想线相比领先/落后多少，
/// 以及按当前速度预计什么时候读完。
PlanProgress computeProgress({
  required int currentPage,
  required int totalPages,
  required DateTime startDate,
  required DateTime? deadline,
  required int dailyMinutes,
  required int? dailyPages,
  required Set<int> weekdays,
  required int pagesPerHour,
  Set<DateTime> restDates = const {},
  DateTime? now,
}) {
  final today = dateOnly(now ?? DateTime.now());
  final result = buildSchedule(
    ScheduleInput(
      currentPage: currentPage,
      totalPages: totalPages,
      startDate: startDate,
      deadline: deadline,
      dailyMinutes: dailyMinutes,
      dailyPages: dailyPages,
      weekdays: weekdays,
      pagesPerHour: pagesPerHour,
      restDates: restDates,
    ),
    from: today,
  );

  int? ahead;
  if (deadline != null) {
    final totalDays = readingDays(
      start: startDate,
      end: deadline,
      weekdays: weekdays,
      except: restDates,
    ).length;
    final endOfElapsed = today.isAfter(deadline) ? deadline : today;
    final elapsedDays = readingDays(
      start: startDate,
      end: endOfElapsed,
      weekdays: weekdays,
      except: restDates,
    ).length;
    if (totalDays > 0) {
      final ideal = (totalPages * elapsedDays / totalDays).round();
      ahead = currentPage - ideal;
    }
  }

  return PlanProgress(
    hasDeadline: deadline != null,
    aheadPages: ahead,
    estimatedFinish: result.estimatedFinish,
    pagesPerReadingDay: result.pagesPerReadingDay,
  );
}

/// 基于历史统计的完成时间预估。
///
/// 用「平均阅读速度（页/小时）」和「平均每个阅读日的阅读时长」推算每天能读多少页，
/// 再沿阅读日排到剩余页数读完为止。
class PaceForecast {
  const PaceForecast({
    required this.remainingPages,
    required this.pagesPerHour,
    required this.averageDailyMinutes,
    required this.finish,
    required this.readingDaysNeeded,
  });

  final int remainingPages;
  final double? pagesPerHour;
  final double? averageDailyMinutes;
  final DateTime? finish;
  final int readingDaysNeeded;

  /// 统计样本不足（没有页数或日均时长）时为 false。
  bool get hasStats =>
      pagesPerHour != null &&
      pagesPerHour! > 0 &&
      averageDailyMinutes != null &&
      averageDailyMinutes! > 0;

  double? get pagesPerDay =>
      hasStats ? pagesPerHour! * averageDailyMinutes! / 60 : null;
}

/// 按统计速度和日均阅读时长估算读完日期。
///
/// 没有计划时默认每天都可阅读；有计划时沿用计划的阅读日和休息日。
PaceForecast forecastAtCurrentPace({
  required int currentPage,
  required int totalPages,
  required double? pagesPerHour,
  required double? averageDailyMinutes,
  required Set<int> weekdays,
  Set<DateTime> restDates = const {},
  DateTime? now,
}) {
  final today = dateOnly(now ?? DateTime.now());
  final remaining = max<int>(0, totalPages - currentPage);

  PaceForecast result({DateTime? finish, int readingDaysNeeded = 0}) =>
      PaceForecast(
        remainingPages: remaining,
        pagesPerHour: pagesPerHour,
        averageDailyMinutes: averageDailyMinutes,
        finish: finish,
        readingDaysNeeded: readingDaysNeeded,
      );

  if (remaining <= 0) return result(finish: today);
  if (pagesPerHour == null ||
      pagesPerHour <= 0 ||
      averageDailyMinutes == null ||
      averageDailyMinutes <= 0) {
    return result();
  }

  final dailyMinutes = max<int>(1, averageDailyMinutes.round());
  final pace = max<int>(1, pagesPerHour.round());
  final schedule = buildSchedule(
    ScheduleInput(
      currentPage: currentPage,
      totalPages: totalPages,
      startDate: today,
      deadline: null,
      dailyMinutes: dailyMinutes,
      weekdays: weekdays.isEmpty ? const {1, 2, 3, 4, 5, 6, 7} : weekdays,
      pagesPerHour: pace,
      restDates: restDates,
    ),
    from: today,
  );

  return result(
    finish: schedule.estimatedFinish,
    readingDaysNeeded: schedule.tasks.length,
  );
}
