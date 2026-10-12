import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/core/date_x.dart';
import 'package:reader_management/domain/scheduling/scheduler.dart';

void main() {
  // 2025-01-06 是周一。
  final monday = DateTime(2025, 1, 6);

  ScheduleInput input({
    required int current,
    required int total,
    required DateTime deadline,
    int dailyMinutes = 60,
    Set<int>? weekdays,
    int pace = 30,
  }) =>
      ScheduleInput(
        currentPage: current,
        totalPages: total,
        startDate: monday,
        deadline: deadline,
        dailyMinutes: dailyMinutes,
        weekdays: weekdays ?? {1, 2, 3, 4, 5, 6, 7},
        pagesPerHour: pace,
      );

  test('均摊到每个可用阅读日', () {
    // 100 页，5 天（周一到周五，排除周末），每天 60 分钟 × 30 页/小时 = 30 页容量。
    final result = buildSchedule(
      input(
        current: 0,
        total: 100,
        deadline: DateTime(2025, 1, 10),
        weekdays: {1, 2, 3, 4, 5},
      ),
      from: monday,
    );

    expect(result.readingDays, 5);
    expect(result.pagesPerReadingDay, 20);
    expect(result.oversubscribed, isFalse);
    expect(result.tasks.length, 5);
    expect(result.tasks.first.startPage, 1);
    expect(result.tasks.last.endPage, 100);
    // 20 页 / 30 页每小时 = 40 分钟
    expect(result.tasks.first.plannedMinutes, 40);
  });

  test('只落在指定的星期', () {
    final result = buildSchedule(
      input(
        current: 0,
        total: 30,
        deadline: DateTime(2025, 1, 12), // 周日
        weekdays: {1, 3, 5}, // 一三五
      ),
      from: monday,
    );
    expect(result.tasks.map((t) => t.date.weekday), everyElement(isIn({1, 3, 5})));
    expect(result.readingDays, 3);
    expect(result.tasks.first.date, monday);
  });

  test('容量不足时标记 oversubscribed 并只排能排的', () {
    // 500 页，只有 2 个阅读日，每天容量 30 页 → 只能排 60 页。
    final result = buildSchedule(
      input(
        current: 0,
        total: 500,
        deadline: DateTime(2025, 1, 7),
        weekdays: {1, 2},
      ),
      from: monday,
    );
    expect(result.readingDays, 2);
    expect(result.oversubscribed, isTrue);
    expect(result.tasks.length, 2);
    expect(result.tasks.fold<int>(0, (s, t) => s + t.pages), 60);
    expect(result.unassignedPages, 440);
  });

  test('已读完的书不产生任务', () {
    final result = buildSchedule(
      input(current: 200, total: 200, deadline: DateTime(2025, 1, 20)),
      from: monday,
    );
    expect(result.tasks, isEmpty);
    expect(result.oversubscribed, isFalse);
  });

  test('从当前进度继续排', () {
    final result = buildSchedule(
      input(current: 50, total: 100, deadline: DateTime(2025, 1, 10)),
      from: monday,
    );
    expect(result.tasks.first.startPage, 51);
    expect(result.tasks.last.endPage, 100);
  });

  test('from 晚于计划开始日时从 from 起排', () {
    final wednesday = DateTime(2025, 1, 8);
    final result = buildSchedule(
      input(current: 0, total: 60, deadline: DateTime(2025, 1, 10)),
      from: wednesday,
    );
    expect(result.tasks.first.date, wednesday);
    expect(result.readingDays, 3);
  });

  test('无截止日时按每日容量推进直到读完', () {
    final result = buildSchedule(
      ScheduleInput(
        currentPage: 0,
        totalPages: 100,
        startDate: monday,
        deadline: null,
        dailyMinutes: 60,
        weekdays: const {1, 2, 3, 4, 5, 6, 7},
        pagesPerHour: 30,
      ),
      from: monday,
    );
    expect(result.hasDeadline, isFalse);
    expect(result.oversubscribed, isFalse);
    // 容量 30 页/天：30+30+30+10 = 4 天
    expect(result.tasks.length, 4);
    expect(result.pagesPerReadingDay, 30);
    expect(result.tasks.last.endPage, 100);
    expect(result.estimatedFinish, DateTime(2025, 1, 9));
  });

  test('页数优先：固定每天页数，忽略每日时长上限', () {
    // 每天 20 页读 100 页 = 5 天；即使每日时长只够 2 页也不受限。
    final result = buildSchedule(
      ScheduleInput(
        currentPage: 0,
        totalPages: 100,
        startDate: monday,
        deadline: null,
        dailyMinutes: 5,
        dailyPages: 20,
        weekdays: const {1, 2, 3, 4, 5, 6, 7},
        pagesPerHour: 30,
      ),
      from: monday,
    );
    expect(result.tasks.length, 5);
    expect(result.pagesPerReadingDay, 20);
    expect(result.tasks.first.endPage - result.tasks.first.startPage + 1, 20);
    expect(result.tasks.last.endPage, 100);
    expect(result.oversubscribed, isFalse);
  });

  test('页数优先 + 截止日：页数不够时标记排不下', () {
    final result = buildSchedule(
      ScheduleInput(
        currentPage: 0,
        totalPages: 100,
        startDate: monday,
        deadline: DateTime(2025, 1, 10), // 5 天
        dailyMinutes: 60,
        dailyPages: 10, // 每天 10 页 × 5 天 = 50 页
        weekdays: const {1, 2, 3, 4, 5, 6, 7},
        pagesPerHour: 30,
      ),
      from: monday,
    );
    expect(result.tasks.length, 5);
    expect(result.oversubscribed, isTrue);
    expect(result.unassignedPages, 50);
  });

  test('dateRange 跨月末不丢天', () {
    final days = dateRange(DateTime(2025, 1, 30), DateTime(2025, 2, 2)).toList();
    expect(days.length, 4);
    expect(days.last, DateTime(2025, 2, 2));
  });
}
