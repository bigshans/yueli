import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/core/date_x.dart';
import 'package:reader_management/data/database.dart';
import 'package:reader_management/data/repository.dart';

void main() {
  late AppDatabase db;
  late ReadingRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReadingRepository(db);
  });

  tearDown(() => db.close());

  test('创建读物并排期后生成每日任务', () async {
    final id = await repo.createBook(title: '测试书', totalPages: 100);
    final result = await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60, // 容量 30 页/天 @30 页/小时
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    expect(result.oversubscribed, isFalse);
    expect(result.tasks.length, 5);

    final stored = await repo.tasksBetween(today(), addDays(today(), 4));
    expect(stored.length, 5);
    expect(stored.first.task.startPage, 1);
    expect(stored.last.task.endPage, 100);
  });

  test('完成任务后更新进度并从次日续排', () async {
    final id = await repo.createBook(title: '测试书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    final before = await repo.tasksBetween(today(), addDays(today(), 4));
    final first = before.first;
    await repo.completeTask(first.task.id, actualMinutes: 50);

    final book = await repo.getBook(id);
    expect(book!.currentPage, first.task.endPage);

    final after = await repo.tasksBetween(today(), addDays(today(), 4));
    // 今天已完成的任务保留
    final doneToday = after.where((t) => t.task.date == today());
    expect(doneToday.length, 1);
    expect(doneToday.first.task.status, 'done');
    // 不会在已完成当天再塞新任务
    expect(
      after.where((t) => t.task.date == today() && t.task.status == 'pending'),
      isEmpty,
    );
    // 剩余页数被重新摊到之后的日子
    final pendingPages = after
        .where((t) => t.task.status == 'pending')
        .fold<int>(0, (s, t) => s + (t.task.endPage - t.task.startPage + 1));
    expect(pendingPages, 100 - first.task.endPage);
  });

  test('期限内排不下时标记 oversubscribed', () async {
    final id = await repo.createBook(title: '大书', totalPages: 1000);
    final result = await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: today(),
      dailyMinutes: 30, // 容量 15 页
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    expect(result.oversubscribed, isTrue);
    final plan = await repo.getPlanForBook(id);
    expect(plan!.status, 'oversubscribed');
  });

  test('跳过任务后页数被重新分配，进度不变', () async {
    final id = await repo.createBook(title: '测试书', totalPages: 30);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 2),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    final before = await repo.tasksBetween(today(), addDays(today(), 2));
    final first = before.first;
    await repo.completeTask(first.task.id, skipped: true);

    final book = await repo.getBook(id);
    expect(book!.currentPage, 0); // 跳过不影响进度

    final after = await repo.tasksBetween(today(), addDays(today(), 2));
    final pendingPages = after
        .where((t) => t.task.status == 'pending')
        .fold<int>(0, (s, t) => s + (t.task.endPage - t.task.startPage + 1));
    expect(pendingPages, 30); // 30 页全部重新排入后续任务
    expect(after.any((t) => t.task.status == 'skipped'), isTrue);
  });

  test('修改阅读速度后所有活动计划重算', () async {
    final id = await repo.createBook(title: '测试书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 30,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final before = await repo.tasksBetween(today(), addDays(today(), 4));
    // 30 分钟 @30 页/小时 = 15 页/天 → 每天任务 15 页
    expect(before.first.task.endPage - before.first.task.startPage + 1, 15);

    await repo.updateSettings(pagesPerHour: 60);
    final after = await repo.tasksBetween(today(), addDays(today(), 4));
    // 30 分钟 @60 页/小时 = 每天容量 30 页；
    // 但均摊目标为 ceil(100/5)=20 页/天，低于容量，故每天 20 页。
    expect(after.first.task.endPage - after.first.task.startPage + 1, 20);
    expect(after.length, 5);
  });

  test('自由计时：记录 session、累加进度并学习速度', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    final t0 = DateTime(2025, 1, 6, 20, 0);
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: 20,
      now: t0.add(const Duration(minutes: 30)),
    );

    final book = await repo.getBook(id);
    expect(book!.currentPage, 20);
    // 20 页 / 0.5 小时 = 40 页每小时
    expect(book.measuredPagesPerHour, closeTo(40, 0.001));

    final stats = await repo.bookStats(id);
    expect(stats.sessionCount, 1);
    expect(stats.totalSeconds, 1800);
    expect(stats.totalPages, 20);
  });

  test('任务计时：完成后进度到任务末页，速度被学习', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final tasks = await repo.tasksBetween(today(), addDays(today(), 4));
    final first = tasks.first;
    final t0 = DateTime(2025, 1, 6, 20, 0);

    await repo.startTimer(bookId: id, taskId: first.task.id, now: t0);
    await repo.stopTimer(
      completeTask: true,
      now: t0.add(const Duration(minutes: 40)),
    );

    final book = await repo.getBook(id);
    expect(book!.currentPage, first.task.endPage);
    expect(book.measuredPagesPerHour, isNotNull);

    final task = await repo.getTask(first.task.id);
    expect(task!.status, 'done');
    expect(task.actualMinutes, 40);
  });

  test('完成当天任务可记录实际读到的页码', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final tasks = await repo.tasksBetween(today(), addDays(today(), 4));
    final first = tasks.first; // 计划 1..起

    await repo.completeTask(first.task.id, reachedPage: 12);

    final book = await repo.getBook(id);
    expect(book!.currentPage, 12); // 按实际读到的页码，而不是计划末页
    final done = await repo.getTask(first.task.id);
    expect(done!.status, 'done');
    expect(done.reachedPage, 12);
  });

  test('自由计时按绝对页码更新进度，并记录增量', () async {
    final id = await repo.createBook(
      title: '书',
      totalPages: 100,
      currentPage: 30,
    );
    final t0 = DateTime(2025, 1, 6, 20, 0);
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: 55,
      now: t0.add(const Duration(minutes: 30)),
    );

    final book = await repo.getBook(id);
    expect(book!.currentPage, 55); // 直接设为读到的页码
    final stats = await repo.bookStats(id);
    expect(stats.totalPages, 25); // 本次增量 55 - 30
  });

  test('手动速度优先于自动学习值', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    final t0 = DateTime(2025, 1, 6, 20, 0);
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: 20,
      now: t0.add(const Duration(minutes: 30)),
    );

    var book = await repo.getBook(id);
    var settings = await db.loadSettings();
    expect(effectivePace(book!, settings), 40); // 自动学习

    await repo.updateBook(
      id,
      const BooksCompanion(manualPagesPerHour: Value(15)),
    );
    book = await repo.getBook(id);
    settings = await db.loadSettings();
    expect(effectivePace(book!, settings), 15); // 手动覆盖
  });

  test('取消计时不产生 session', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.startTimer(bookId: id, now: DateTime(2025, 1, 6, 20, 0));
    await repo.cancelTimer();
    final stats = await repo.bookStats(id);
    expect(stats.sessionCount, 0);
  });

  test('按页数排期：每天固定页数，与时长无关', () async {
    final id = await repo.createBook(title: '书', totalPages: 60);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 5),
      dailyMinutes: 30, // 容量 15 页，应被页数目标覆盖
      dailyPages: 20,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    final tasks = await repo.tasksBetween(today(), addDays(today(), 5));
    expect(tasks.first.task.endPage - tasks.first.task.startPage + 1, 20);

    final plan = await repo.getPlanForBook(id);
    expect(plan!.dailyPages, 20);
  });

  test('自由计时也会计入今天这本书的任务', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final todayTask = await repo.taskForBookOnDate(id, DateTime.now());
    expect(todayTask, isNotNull);

    // 不绑定任务，就像从读物详情页开始计时
    final t0 = today().add(const Duration(hours: 20));
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(now: t0.add(const Duration(minutes: 25)));

    // 时长归到今天这本书的任务上
    final sessions = await repo.watchSessions(id).first;
    expect(sessions.single.taskId, todayTask!.id);

    // 按天聚合能反映出来
    final daily = await repo.watchDailyStats(id).first;
    expect(daily.single.minutes, 25);
  });

  test('同一天多次计时按天聚合', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final t0 = today().add(const Duration(hours: 20));
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(now: t0.add(const Duration(minutes: 20)));
    await repo.startTimer(bookId: id, now: t0.add(const Duration(hours: 1)));
    await repo.stopTimer(now: t0.add(const Duration(hours: 1, minutes: 15)));

    final daily = await repo.watchDailyStats(id).first;
    expect(daily.length, 1);
    expect(daily.single.minutes, 35);
    expect(daily.single.sessions, 2);
  });

  test('读满当天目标页数后自动完成任务', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60, // 100 页 / 5 天 → 每天 20 页
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final task = await repo.taskForBookOnDate(id, DateTime.now());
    final targetPages = task!.endPage - task.startPage + 1;
    expect(targetPages, 20);

    final t0 = today().add(const Duration(hours: 20));
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: targetPages,
      now: t0.add(const Duration(minutes: 30)),
    );

    final after = await repo.getTask(task.id);
    expect(after!.status, 'done'); // 自动完成
  });

  test('未读满当天目标页数则不自动完成', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final task = await repo.taskForBookOnDate(id, DateTime.now());
    final targetPages = task!.endPage - task.startPage + 1;

    final t0 = today().add(const Duration(hours: 20));
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: targetPages - 5,
      now: t0.add(const Duration(minutes: 20)),
    );

    final today2 = await repo.taskForBookOnDate(id, DateTime.now());
    expect(today2!.status, 'pending');
  });

  test('超额阅读会提前进度，后续每天页数相应减少', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60, // 100 页 / 5 天 → 每天 20 页
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    // 今天目标 20 页，实际读了 50 页
    final t0 = today().add(const Duration(hours: 20));
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: 50,
      now: t0.add(const Duration(minutes: 60)),
    );

    final book = await repo.getBook(id);
    expect(book!.currentPage, 50); // 超出部分计入进度

    final next = await repo.tasksBetween(
      addDays(today(), 1),
      addDays(today(), 4),
    );
    // 剩余 50 页 / 4 天 = 13 页/天，从第 51 页继续
    expect(next.first.task.startPage, 51);
    expect(next.first.task.endPage - next.first.task.startPage + 1, 13);
  });

  test('同一任务多次计时，页数按增量累计不重复', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final t0 = today().add(const Duration(hours: 18));
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: 20,
      now: t0.add(const Duration(minutes: 20)),
    );
    await repo.startTimer(bookId: id, now: t0.add(const Duration(hours: 1)));
    await repo.stopTimer(
      reachedPage: 32,
      now: t0.add(const Duration(hours: 1, minutes: 15)),
    );

    final daily = await repo.watchDailyStats(id).first;
    expect(daily.single.pages, 32); // 不是 20 + 32 = 52
  });

  test('设为休息日后那天不再排阅读，页数重新分配', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final plan = await repo.getPlanForBook(id);
    final restDate = addDays(today(), 1);

    await repo.addRestDay(plan!.id, restDate);

    final tasks = await repo.tasksBetween(today(), addDays(today(), 4));
    expect(tasks.any((t) => t.task.date == restDate), isFalse);
    expect(await repo.restDates(plan.id), contains(restDate));
    // 100 页摊到剩余 4 天 → 25 页/天
    expect(tasks.first.task.endPage - tasks.first.task.startPage + 1, 25);
  });

  test('先计时后选书：结束后补选书本并记录', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    final t0 = DateTime(2025, 1, 6, 20, 0);
    await repo.startTimer(now: t0); // 不先选书

    var timer = await repo.activeTimer();
    expect(timer, isNotNull);
    expect(timer!.bookId, isNull);

    await repo.setTimerBook(id);
    timer = await repo.activeTimer();
    expect(timer!.bookId, id);

    await repo.stopTimer(
      reachedPage: 15,
      now: t0.add(const Duration(minutes: 30)),
    );
    final book = await repo.getBook(id);
    expect(book!.currentPage, 15);
    final sessions = await repo.watchSessions(id).first;
    expect(sessions.single.durationSeconds, 1800);
  });

  test('标签保存与解析', () async {
    final id = await repo.createBook(
      title: '书',
      totalPages: 100,
      tags: encodeTags(['技术', '心理学']),
    );
    final book = await repo.getBook(id);
    expect(parseTags(book!.tags), ['技术', '心理学']);
    expect(parseTags(null), isEmpty);
  });

  test('重读：轮次递增、进度归零、保留旧记录', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    // 第一遍读完
    await repo.updateBook(id, const BooksCompanion(currentPage: Value(100)));
    var readings = await repo.watchReadings(id).first;
    expect(readings.length, 1);
    expect(readings.single.round, 1);
    expect(readings.single.finishedAt, isNotNull);
    expect(readings.single.completed, isTrue);

    await repo.startReread(id);
    final book = await repo.getBook(id);
    expect(book!.round, 2);
    expect(book.currentPage, 0);

    readings = await repo.watchReadings(id).first;
    expect(readings.length, 2);
    expect(readings.last.round, 2);
    expect(readings.last.finishedAt, isNull);
  });

  test('未读完也能重读，旧轮次标为未读完', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.updateBook(id, const BooksCompanion(currentPage: Value(30)));

    await repo.startReread(id);

    final book = await repo.getBook(id);
    expect(book!.round, 2);
    expect(book.currentPage, 0);
    final readings = await repo.watchReadings(id).first;
    expect(readings.length, 2);
    expect(readings.first.round, 1);
    expect(readings.first.finishedAt, isNotNull);
    expect(readings.first.completed, isFalse);
    expect(readings.last.round, 2);
    expect(readings.last.finishedAt, isNull);
  });

  test('重读后新会话记录到新轮次', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    await repo.updateBook(id, const BooksCompanion(currentPage: Value(100)));
    await repo.startReread(id);

    final t0 = DateTime(2025, 1, 6, 20, 0);
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: 10,
      now: t0.add(const Duration(minutes: 30)),
    );

    final sessions = await repo.watchSessions(id).first;
    expect(sessions.single.round, 2);
  });

  test('暂停/继续：只累计真正在跑的时长', () async {
    final id = await repo.createBook(title: '书', totalPages: 100);
    final t0 = DateTime(2025, 1, 6, 20, 0);
    await repo.startTimer(bookId: id, now: t0);
    await repo.pauseTimer(now: t0.add(const Duration(minutes: 10)));
    // 暂停中它不跑： 到 20 分钟时累计应仍是 10 分钟
    var timer = await repo.activeTimer();
    expect(timer!.isRunning, isFalse);
    expect(timer.elapsedSecondsAt(t0.add(const Duration(minutes: 20))), 600);

    await repo.resumeTimer(now: t0.add(const Duration(minutes: 20)));
    timer = await repo.activeTimer();
    expect(timer!.isRunning, isTrue);
    // 再跑 15 分钟，总共 25 分钟（1500 秒）
    await repo.stopTimer(
      reachedPage: 10,
      now: t0.add(const Duration(minutes: 35)),
    );
    final stats = await repo.bookStats(id);
    expect(stats.totalSeconds, 1500);
  });

  test('搁置后隐藏任务并停止计时，恢复后重新排期', () async {
    final id = await repo.createBook(title: '搁置书', totalPages: 100);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 4),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    expect(await repo.tasksBetween(today(), addDays(today(), 4)), isNotEmpty);

    await repo.startTimer(
      bookId: id,
      now: today().add(const Duration(hours: 9)),
    );
    await repo.setBookShelved(id, true);

    expect((await repo.getBook(id))!.shelved, isTrue);
    expect(await repo.activeTimer(), isNull);
    expect(await repo.tasksBetween(today(), addDays(today(), 4)), isEmpty);

    await repo.setBookShelved(id, false);

    expect((await repo.getBook(id))!.shelved, isFalse);
    expect(await repo.tasksBetween(today(), addDays(today(), 4)), isNotEmpty);
  });
}
