import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';

/// 全局数据库实例。
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = Provider<ReadingRepository>((ref) {
  return ReadingRepository(ref.watch(databaseProvider));
});

final settingsProvider = StreamProvider<AppSetting>((ref) {
  return ref.watch(databaseProvider).watchSettings();
});

final booksProvider = StreamProvider<List<Book>>((ref) {
  return ref.watch(repositoryProvider).watchBooks();
});

final bookProvider = StreamProvider.family<Book?, int>((ref, bookId) {
  return ref.watch(repositoryProvider).watchBook(bookId);
});

final planForBookProvider = StreamProvider.family<Plan?, int>((ref, bookId) {
  return ref.watch(repositoryProvider).watchPlanForBook(bookId);
});

/// 今天的任务。
final todayTasksProvider = StreamProvider<List<TaskWithBook>>((ref) {
  final repo = ref.watch(repositoryProvider);
  final t = today();
  return repo.watchTasksBetween(t, t);
});

/// [from, to] 闭区间内的任务。
final tasksInRangeProvider =
    StreamProvider.family<List<TaskWithBook>, (DateTime, DateTime)>((ref, range) {
  return ref.watch(repositoryProvider).watchTasksBetween(range.$1, range.$2);
});

/// 当前正在进行的计时（无则为 null）。
final activeTimerProvider = Provider<ActiveTimer?>((ref) {
  final s = ref.watch(settingsProvider).valueOrNull;
  if (s == null || s.activeStartedAt == null || s.activeBookId == null) {
    return null;
  }
  return ActiveTimer(
    bookId: s.activeBookId!,
    taskId: s.activeTaskId,
    startedAt: s.activeStartedAt!,
    runningSince: s.activeRunningSince,
    accumulatedSeconds: s.activeAccumulatedSeconds,
  );
});

/// 一本书的计时统计。
final bookStatsProvider = StreamProvider.family<BookStats, int>((ref, bookId) {
  return ref.watch(repositoryProvider).watchBookStats(bookId);
});

/// 一本书的计时明细（按时间倒序）。
final sessionsProvider =
    StreamProvider.family<List<ReadingSession>, int>((ref, bookId) {
  return ref.watch(repositoryProvider).watchSessions(bookId);
});

/// 一本书按天聚合的阅读统计（倒序）。
final dailyStatsProvider =
    StreamProvider.family<List<DailyStat>, int>((ref, bookId) {
  return ref.watch(repositoryProvider).watchDailyStats(bookId);
});
