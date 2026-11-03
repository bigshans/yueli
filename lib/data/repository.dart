import 'dart:math';

import 'package:drift/drift.dart';

import '../core/date_x.dart';
import '../domain/scheduling/scheduler.dart';
import 'book_status.dart';
import 'database.dart';

/// 任务 + 所属读物，用于列表展示。
class TaskWithBook {
  const TaskWithBook(this.task, this.book);
  final Task task;
  final Book book;
}

/// 一本书的计时统计。
class BookStats {
  const BookStats({
    required this.sessionCount,
    required this.totalSeconds,
    required this.totalPages,
    required this.timedPages,
  });

  final int sessionCount;
  final int totalSeconds;
  final int totalPages;

  /// 有计时记录的页数，用于计算阅读速度（不含手动补记的无时间页数）。
  final int timedPages;

  /// 平均阅读速度（页/小时）。数据不足时为 null。
  double? get averagePagesPerHour => (timedPages > 0 && totalSeconds > 0)
      ? timedPages / (totalSeconds / 3600)
      : null;

  /// 平均单次阅读时长（分钟）。无记录时为 null。
  double? get averageSessionMinutes =>
      sessionCount > 0 ? (totalSeconds / 60) / sessionCount : null;

  /// 平均每天阅读页数（仅统计有记录的“天”）。
  double? get averagePagesPerSession =>
      sessionCount > 0 ? totalPages / sessionCount : null;
}

/// 某一天的阅读汇总。
class DailyStat {
  const DailyStat({
    required this.date,
    required this.seconds,
    required this.pages,
    required this.sessions,
  });

  final DateTime date;
  final int seconds;
  final int pages;
  final int sessions;

  int get minutes => (seconds / 60).round();

  double? get pace =>
      (pages > 0 && seconds > 0) ? pages / (seconds / 3600) : null;
}

/// 当前正在进行的计时。
class ActiveTimer {
  const ActiveTimer({
    required this.bookId,
    required this.taskId,
    required this.startedAt,
    required this.runningSince,
    required this.accumulatedSeconds,
  });

  final int? bookId;
  final int? taskId;

  /// 整个计时会话开始时刻。
  final DateTime startedAt;

  /// 当前这段计时开始时刻；为 null 表示已暂停。
  final DateTime? runningSince;

  /// 暂停前已累计的秒数。
  final int accumulatedSeconds;

  bool get isRunning => runningSince != null;

  int elapsedSecondsAt(DateTime now) {
    final live = runningSince == null
        ? 0
        : max<int>(0, now.difference(runningSince!).inSeconds);
    return accumulatedSeconds + live;
  }
}

Set<int> parseWeekdays(String value) => value
    .split(',')
    .map((s) => int.tryParse(s.trim()))
    .whereType<int>()
    .where((d) => d >= 1 && d <= 7)
    .toSet();

String encodeWeekdays(Iterable<int> days) {
  final sorted = days.toSet().toList()..sort();
  return sorted.join(',');
}

/// 把逗号分隔的标签字符串解析成列表。
List<String> parseTags(String? value) {
  if (value == null) return const [];
  return value
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

String encodeTags(Iterable<String> tags) =>
    tags.map((t) => t.trim()).where((t) => t.isNotEmpty).join(',');

/// 有效阅读速度：手填 > 自动学习 > 全局默认。
int effectivePace(Book book, AppSetting settings) {
  final measured = book.measuredPagesPerHour;
  return book.manualPagesPerHour ??
      (measured != null && measured > 0 ? measured.round() : null) ??
      settings.pagesPerHour;
}

class ReadingRepository {
  ReadingRepository(this.db);

  final AppDatabase db;

  // ---------- 读物 ----------

  Stream<List<Book>> watchBooks() {
    return (db.select(db.books)..orderBy([
          (t) => OrderingTerm.asc(t.priority),
          (t) => OrderingTerm.desc(t.createdAt),
        ]))
        .watch();
  }

  Future<List<Book>> allBooks() => db.select(db.books).get();

  Future<Book?> getBook(int id) {
    return (db.select(
      db.books,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Book?> watchBook(int id) {
    return (db.select(
      db.books,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<WereadLink?> getWereadLink(int bookId) {
    return (db.select(
      db.wereadLinks,
    )..where((t) => t.bookId.equals(bookId))).getSingleOrNull();
  }

  Stream<WereadLink?> watchWereadLink(int bookId) {
    return (db.select(
      db.wereadLinks,
    )..where((t) => t.bookId.equals(bookId))).watchSingleOrNull();
  }

  Future<List<WereadLink>> allWereadLinks() => db.select(db.wereadLinks).get();

  Future<WereadLink?> getWereadLinkByWereadId(String wereadBookId) {
    return (db.select(
      db.wereadLinks,
    )..where((t) => t.wereadBookId.equals(wereadBookId))).getSingleOrNull();
  }

  Future<void> linkWereadBook({
    required int bookId,
    required String wereadBookId,
    String? readerLink,
    String? deepLink,
    int remoteProgress = 0,
    int? remoteReadSeconds,
    bool remoteFinished = false,
    DateTime? remoteUpdatedAt,
  }) async {
    await (db.delete(
      db.wereadLinks,
    )..where((t) => t.bookId.equals(bookId))).go();
    await db
        .into(db.wereadLinks)
        .insert(
          WereadLinksCompanion.insert(
            bookId: bookId,
            wereadBookId: wereadBookId,
            readerLink: Value(readerLink),
            deepLink: Value(deepLink),
            remoteProgress: Value(remoteProgress),
            remoteReadSeconds: Value(remoteReadSeconds),
            remoteFinished: Value(remoteFinished),
            remoteUpdatedAt: Value(remoteUpdatedAt),
            lastSyncedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> updateWereadLinkUrls(
    int bookId, {
    String? readerLink,
    String? deepLink,
  }) async {
    await (db.update(
      db.wereadLinks,
    )..where((t) => t.bookId.equals(bookId))).write(
      WereadLinksCompanion(
        readerLink: Value(readerLink),
        deepLink: Value(deepLink),
      ),
    );
  }

  Future<void> updateWereadLinkSync(
    int bookId, {
    required int remoteProgress,
    int? remoteReadSeconds,
    required bool remoteFinished,
    DateTime? remoteUpdatedAt,
  }) async {
    await (db.update(
      db.wereadLinks,
    )..where((t) => t.bookId.equals(bookId))).write(
      WereadLinksCompanion(
        remoteProgress: Value(remoteProgress),
        remoteReadSeconds: Value(remoteReadSeconds),
        remoteFinished: Value(remoteFinished),
        remoteUpdatedAt: Value(remoteUpdatedAt),
        lastSyncedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> unlinkWereadBook(int bookId) async {
    await (db.delete(
      db.wereadLinks,
    )..where((t) => t.bookId.equals(bookId))).go();
  }

  Future<int> createBook({
    required String title,
    String? author,
    required int totalPages,
    int currentPage = 0,
    int priority = 2,
    int? manualPagesPerHour,
    String? tags,
    String status = BookStatus.reading,
    String? coverUrl,
    String? coverPath,
    String? description,
    String? translator,
    String? publisher,
    String? publishDate,
    String? isbn,
    int? wordCount,
    double? rating,
    int? ratingCount,
    String metadataSource = 'manual',
    DateTime? metadataUpdatedAt,
  }) async {
    final wanted = BookStatus.normalize(status);
    final finished =
        wanted == BookStatus.finished ||
        (totalPages > 0 && currentPage >= totalPages);
    final effectiveStatus = finished ? BookStatus.finished : wanted;
    final effectivePage = finished
        ? totalPages
        : currentPage.clamp(0, totalPages);
    final now = DateTime.now();
    final id = await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            title: title,
            author: Value(author),
            coverUrl: Value(coverUrl),
            coverPath: Value(coverPath),
            description: Value(description),
            translator: Value(translator),
            publisher: Value(publisher),
            publishDate: Value(publishDate),
            isbn: Value(isbn),
            wordCount: Value(wordCount),
            rating: Value(rating),
            ratingCount: Value(ratingCount),
            metadataSource: Value(metadataSource),
            metadataUpdatedAt: Value(metadataUpdatedAt),
            totalPages: totalPages,
            currentPage: Value(effectivePage),
            priority: Value(priority),
            manualPagesPerHour: Value(manualPagesPerHour),
            tags: Value(tags),
            status: Value(effectiveStatus),
          ),
        );
    await db
        .into(db.readings)
        .insert(
          ReadingsCompanion.insert(
            bookId: id,
            round: 1,
            startedAt: now,
            finishedAt: Value(finished ? now : null),
            completed: Value(finished),
          ),
        );
    return id;
  }

  Future<void> updateBook(int id, BooksCompanion patch) async {
    final current = await getBook(id);
    if (current == null) return;
    var effective = patch;
    final nextStatus = patch.status.present
        ? BookStatus.normalize(patch.status.value)
        : current.status;
    if (nextStatus == BookStatus.finished && current.totalPages > 0) {
      effective = patch.copyWith(currentPage: Value(current.totalPages));
    }
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(effective);
    final book = await getBook(id);
    if (book == null) return;
    await _syncBookCompletion(book);
  }

  /// 根据当前进度自动判定「已读」。
  ///
  /// 进度达到总页数时自动标为已读；如果之后进度被调低（例如撤销任务），
  /// 已读状态会自动回到在读。
  Future<void> _syncBookCompletion(Book book) async {
    if (book.totalPages <= 0) return;
    if (book.currentPage >= book.totalPages) {
      await _finishRound(book.id, book.round, completed: true);
    } else if (book.status == BookStatus.finished) {
      await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
        const BooksCompanion(status: Value(BookStatus.reading)),
      );
    }
  }

  Future<void> deleteBook(int id) async {
    await (db.delete(db.books)..where((t) => t.id.equals(id))).go();
  }

  /// 从所有书籍中删除一个标签。返回受影响的书籍数量。
  Future<int> deleteTagGlobally(String tag) async {
    final target = tag.trim();
    if (target.isEmpty) return 0;
    final books = await db.select(db.books).get();
    var changed = 0;
    await db.transaction(() async {
      for (final book in books) {
        final tags = parseTags(book.tags);
        if (!tags.contains(target)) continue;
        final next = tags.where((item) => item != target).toList();
        final encoded = encodeTags(next);
        await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
          BooksCompanion(tags: Value(encoded.isEmpty ? null : encoded)),
        );
        changed++;
      }
    });
    return changed;
  }

  /// 修改阅读状态。
  ///
  /// 只有「在读」会生成待读任务；切到其他状态会停止计时并清掉待读任务。
  /// 标记为「已读」会把进度补到总页数。
  /// 修改优先级。1 = 高，2 = 中，3 = 低。
  Future<void> setBookPriority(int bookId, int priority) async {
    final value = priority.clamp(1, 3);
    await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(priority: Value(value)),
    );
  }

  Future<void> setBookStatus(int bookId, String status) async {
    final next = BookStatus.normalize(status);
    final book = await getBook(bookId);
    if (book == null || book.status == next) return;

    if (book.status == BookStatus.reading && next != BookStatus.reading) {
      final settings = await db.loadSettings();
      if (settings.activeBookId == bookId) await cancelTimer();
    }

    if (next == BookStatus.finished && book.totalPages > 0) {
      await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(
          status: const Value(BookStatus.finished),
          currentPage: Value(book.totalPages),
        ),
      );
      await _finishRound(bookId, book.round, completed: true);
    } else {
      await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
        BooksCompanion(status: Value(next)),
      );
    }

    final plan = await getPlanForBook(bookId);
    if (plan == null) return;
    if (next == BookStatus.reading) {
      await reschedulePlan(plan.id);
      return;
    }

    await (db.delete(db.tasks)
          ..where((t) => t.planId.equals(plan.id) & t.status.equals('pending')))
        .go();
    if (next == BookStatus.finished) {
      await (db.update(db.plans)..where((t) => t.id.equals(plan.id))).write(
        const PlansCompanion(status: Value('completed')),
      );
    }
  }

  /// 兼容旧调用：搁置 / 恢复。
  Future<void> setBookShelved(int bookId, bool shelved) =>
      setBookStatus(bookId, shelved ? BookStatus.shelved : BookStatus.reading);

  // ---------- 重读 / 轮次 ----------

  /// 某本书的各遍阅读记录（按轮次升序）。
  Stream<List<Reading>> watchReadings(int bookId) {
    return (db.select(db.readings)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.asc(t.round)]))
        .watch();
  }

  /// 开始重读：结束当前轮次，轮次 +1，进度归零并重排。
  Future<void> startReread(int bookId) async {
    final book = await getBook(bookId);
    if (book == null) return;
    final now = DateTime.now();
    await _finishRound(bookId, book.round, at: now);
    final next = book.round + 1;
    await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(
        round: Value(next),
        currentPage: const Value(0),
        status: const Value(BookStatus.reading),
      ),
    );
    await db
        .into(db.readings)
        .insert(
          ReadingsCompanion.insert(bookId: bookId, round: next, startedAt: now),
        );
    final plan = await getPlanForBook(bookId);
    if (plan != null) await reschedulePlan(plan.id);
  }

  Future<void> _finishRound(
    int bookId,
    int round, {
    DateTime? at,
    bool completed = false,
  }) async {
    await (db.update(db.readings)..where(
          (t) =>
              t.bookId.equals(bookId) &
              t.round.equals(round) &
              t.finishedAt.isNull(),
        ))
        .write(
          ReadingsCompanion(
            finishedAt: Value(at ?? DateTime.now()),
            completed: Value(completed),
          ),
        );
    if (completed) {
      await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
        const BooksCompanion(status: Value(BookStatus.finished)),
      );
    }
  }

  /// 该书的有效阅读速度。
  Future<int> paceForBook(int bookId) async {
    final book = await getBook(bookId);
    final settings = await db.loadSettings();
    if (book == null) return settings.pagesPerHour;
    return effectivePace(book, settings);
  }

  // ---------- 计划 ----------

  Future<Plan?> getPlanForBook(int bookId) {
    return (db.select(db.plans)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<Plan?> watchPlanForBook(int bookId) {
    return (db.select(db.plans)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<Plan?> getPlan(int id) {
    return (db.select(
      db.plans,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 全部计划，用于全局统计中的预计完成日期。
  Stream<List<Plan>> watchAllPlans() => db.select(db.plans).watch();

  /// 全部计划的休息日，按计划 id 分组。
  Stream<Map<int, Set<DateTime>>> watchAllRestDates() {
    return db.select(db.restDays).watch().map((rows) {
      final result = <int, Set<DateTime>>{};
      for (final r in rows) {
        result.putIfAbsent(r.planId, () => <DateTime>{}).add(dateOnly(r.date));
      }
      return result;
    });
  }

  /// 为一本书创建（替换）计划并立即生成每日任务。[deadline] 为空表示不设期限。
  Future<ScheduleResult> savePlan({
    required int bookId,
    required DateTime startDate,
    required DateTime? deadline,
    required int dailyMinutes,
    required Set<int> weekdays,
    int? dailyPages,
  }) async {
    await (db.delete(db.plans)..where((t) => t.bookId.equals(bookId))).go();
    final planId = await db
        .into(db.plans)
        .insert(
          PlansCompanion.insert(
            bookId: bookId,
            startDate: dateOnly(startDate),
            deadline: Value(deadline == null ? null : dateOnly(deadline)),
            dailyMinutes: dailyMinutes,
            dailyPages: Value(dailyPages),
            weekdays: encodeWeekdays(weekdays),
          ),
        );
    return reschedulePlan(planId);
  }

  Future<void> deletePlan(int planId) async {
    await (db.delete(db.plans)..where((t) => t.id.equals(planId))).go();
  }

  // ---------- 休息日 ----------

  Stream<Set<DateTime>> watchRestDates(int planId) {
    return (db.select(db.restDays)..where((t) => t.planId.equals(planId)))
        .watch()
        .map((rows) => rows.map((r) => dateOnly(r.date)).toSet());
  }

  Future<Set<DateTime>> restDates(int planId) async {
    final rows = await (db.select(
      db.restDays,
    )..where((t) => t.planId.equals(planId))).get();
    return rows.map((r) => dateOnly(r.date)).toSet();
  }

  Future<void> addRestDay(int planId, DateTime date) async {
    final d = dateOnly(date);
    final existing =
        await (db.select(db.restDays)
              ..where((t) => t.planId.equals(planId) & t.date.equals(d)))
            .getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.restDays)
          .insert(RestDaysCompanion.insert(planId: planId, date: d));
    }
    await reschedulePlan(planId);
  }

  Future<void> removeRestDay(int planId, DateTime date) async {
    await (db.delete(db.restDays)..where(
          (t) => t.planId.equals(planId) & t.date.equals(dateOnly(date)),
        ))
        .go();
    await reschedulePlan(planId);
  }

  /// 自愈式重排：清掉该计划所有 pending 任务，从当前进度重新排到今天之后。
  Future<ScheduleResult> reschedulePlan(int planId, {DateTime? now}) async {
    final plan = await getPlan(planId);
    if (plan == null) return _emptyResult;
    final book = await getBook(plan.bookId);
    if (book == null) return _emptyResult;
    if (book.status != BookStatus.reading) {
      await (db.delete(
            db.tasks,
          )..where((t) => t.planId.equals(planId) & t.status.equals('pending')))
          .go();
      return _emptyResult;
    }

    await (db.delete(
      db.tasks,
    )..where((t) => t.planId.equals(planId) & t.status.equals('pending'))).go();

    final settings = await db.loadSettings();
    final nowDate = logicalDate(
      now ?? DateTime.now(),
      settings.settlementMinutes,
    );
    // 今天若已有已完成/已跳过的任务，视为当天额度已用完，从明天续排。
    final handledToday =
        await (db.select(db.tasks)..where(
              (t) =>
                  t.planId.equals(planId) &
                  t.date.equals(nowDate) &
                  t.status.isNotValue('pending'),
            ))
            .get();
    final from = handledToday.isEmpty ? nowDate : addDays(nowDate, 1);

    final rests = await restDates(planId);
    final result = buildSchedule(
      ScheduleInput(
        currentPage: book.currentPage,
        totalPages: book.totalPages,
        startDate: plan.startDate,
        deadline: plan.deadline,
        dailyMinutes: plan.dailyMinutes,
        weekdays: parseWeekdays(plan.weekdays),
        pagesPerHour: effectivePace(book, settings),
        dailyPages: plan.dailyPages,
        restDates: rests,
      ),
      from: from,
    );

    if (result.tasks.isNotEmpty) {
      await db.batch((b) {
        b.insertAll(
          db.tasks,
          result.tasks.map(
            (t) => TasksCompanion.insert(
              planId: planId,
              bookId: book.id,
              date: t.date,
              startPage: t.startPage,
              endPage: t.endPage,
              plannedMinutes: t.plannedMinutes,
            ),
          ),
        );
      });
    }

    final completed = book.currentPage >= book.totalPages;
    if (completed) {
      await _finishRound(book.id, book.round, completed: true);
    }
    await (db.update(db.plans)..where((t) => t.id.equals(planId))).write(
      PlansCompanion(
        status: Value(
          completed
              ? 'completed'
              : (result.oversubscribed ? 'oversubscribed' : 'active'),
        ),
      ),
    );
    return result;
  }

  /// 重新排期所有 active / oversubscribed 计划（设置变更后调用）。
  Future<void> rescheduleAll({DateTime? now}) async {
    final active = await (db.select(
      db.plans,
    )..where((t) => t.status.isIn(['active', 'oversubscribed']))).get();
    for (final p in active) {
      await reschedulePlan(p.id, now: now);
    }
  }

  // ---------- 任务 ----------

  Stream<List<TaskWithBook>> watchTasksBetween(DateTime from, DateTime to) {
    return _taskQuery(from, to).watch().map(_toTaskWithBook);
  }

  Future<List<TaskWithBook>> tasksBetween(DateTime from, DateTime to) async {
    final rows = await _taskQuery(from, to).get();
    return _toTaskWithBook(rows);
  }

  JoinedSelectStatement _taskQuery(DateTime from, DateTime to) {
    return db.select(db.tasks).join([
        innerJoin(db.books, db.books.id.equalsExp(db.tasks.bookId)),
      ])
      ..where(
        db.tasks.date.isBetweenValues(dateOnly(from), dateOnly(to)) &
            db.books.status.equals(BookStatus.reading),
      )
      ..orderBy([
        OrderingTerm.asc(db.tasks.date),
        OrderingTerm.asc(db.tasks.id),
      ]);
  }

  List<TaskWithBook> _toTaskWithBook(List<TypedResult> rows) => [
    for (final r in rows)
      TaskWithBook(r.readTable(db.tasks), r.readTable(db.books)),
  ];

  Future<Task?> getTask(int id) {
    return (db.select(
      db.tasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// 完成任务：更新书本进度并重排后续计划。
  /// [reachedPage] 为当天实际读到的页码，缺省则视为任务末页。
  Future<void> completeTask(
    int taskId, {
    int? reachedPage,
    int? actualMinutes,
    bool skipped = false,
  }) async {
    final task = await getTask(taskId);
    if (task == null) return;

    // 若正在为这次任务计时，先停掉，避免残留指向已完成任务的计时。
    final settings = await db.loadSettings();
    if (settings.activeTaskId == taskId) {
      await cancelTimer();
    }

    if (skipped) {
      await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
        const TasksCompanion(status: Value('skipped')),
      );
      await reschedulePlan(task.planId);
      return;
    }

    final effectiveReached = reachedPage ?? task.endPage;
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        status: const Value('done'),
        actualMinutes: Value(actualMinutes),
        reachedPage: Value(effectiveReached),
      ),
    );

    final book = await getBook(task.bookId);
    if (book != null) {
      await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
        BooksCompanion(
          currentPage: Value(effectiveReached.clamp(0, book.totalPages)),
        ),
      );
      final updated = await getBook(book.id);
      if (updated != null) await _syncBookCompletion(updated);
    }
    await reschedulePlan(task.planId);
  }

  /// 取消当天的跳过：把 skipped 任务恢复为待读并重新排期。
  ///
  /// 与 [reopenTask] 不同，这里不会回退书本进度：跳过本身不影响进度，
  /// 若之后又通过手动补记读到了后面的页码，取消跳过也不应把进度改回去。
  Future<void> unskipTask(int taskId, {DateTime? now}) async {
    final task = await getTask(taskId);
    if (task == null || task.status != 'skipped') return;

    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      const TasksCompanion(
        status: Value('pending'),
        actualMinutes: Value(null),
        reachedPage: Value(null),
      ),
    );
    await reschedulePlan(task.planId, now: now);
  }

  /// 撤销完成，回到 pending，并重排。
  Future<void> reopenTask(int taskId) async {
    final task = await getTask(taskId);
    if (task == null) return;
    await (db.update(db.tasks)..where((t) => t.id.equals(taskId))).write(
      const TasksCompanion(
        status: Value('pending'),
        actualMinutes: Value(null),
        reachedPage: Value(null),
      ),
    );

    final book = await getBook(task.bookId);
    if (book != null && book.currentPage > task.startPage - 1) {
      await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
        BooksCompanion(currentPage: Value(task.startPage - 1)),
      );
      final updated = await getBook(book.id);
      if (updated != null) await _syncBookCompletion(updated);
    }
    await reschedulePlan(task.planId);
  }

  // ---------- 计时 ----------

  /// 读取当前计时状态（无则为 null）。书可以不先选。
  Future<ActiveTimer?> activeTimer() async {
    final s = await db.loadSettings();
    if (s.activeStartedAt == null) return null;
    return ActiveTimer(
      bookId: s.activeBookId,
      taskId: s.activeTaskId,
      startedAt: s.activeStartedAt!,
      runningSince: s.activeRunningSince,
      accumulatedSeconds: s.activeAccumulatedSeconds,
    );
  }

  /// 开始计时。[bookId] / [taskId] 可先留空，之后再补。
  Future<void> startTimer({int? bookId, int? taskId, DateTime? now}) async {
    await db.loadSettings();
    final at = now ?? DateTime.now();
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(
        activeBookId: Value(bookId),
        activeTaskId: Value(taskId),
        activeStartedAt: Value(at),
        activeRunningSince: Value(at),
        activeAccumulatedSeconds: const Value(0),
      ),
    );
  }

  /// 给当前正在进行的计时指定书本（先计时后选书）。
  Future<void> setTimerBook(int bookId) async {
    await db.loadSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(activeBookId: Value(bookId)),
    );
  }

  /// 暂停计时，累计已用时长。
  Future<void> pauseTimer({DateTime? now}) async {
    final s = await db.loadSettings();
    final runningSince = s.activeRunningSince;
    if (runningSince == null) return;
    final n = now ?? DateTime.now();
    final elapsed =
        s.activeAccumulatedSeconds +
        max<int>(0, n.difference(runningSince).inSeconds);
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(
        activeRunningSince: const Value(null),
        activeAccumulatedSeconds: Value(elapsed),
      ),
    );
  }

  /// 继续计时。
  Future<void> resumeTimer({DateTime? now}) async {
    final s = await db.loadSettings();
    if (s.activeRunningSince != null || s.activeStartedAt == null) return;
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(activeRunningSince: Value(now ?? DateTime.now())),
    );
  }

  /// 放弃当前计时，不记录。
  Future<void> cancelTimer() async {
    await db.loadSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      const AppSettingsCompanion(
        activeBookId: Value(null),
        activeTaskId: Value(null),
        activeStartedAt: Value(null),
        activeRunningSince: Value(null),
        activeAccumulatedSeconds: Value(0),
      ),
    );
  }

  /// 手动补记阅读页数（不记录时间）。
  ///
  /// 会写入一条 durationSeconds = 0 的历史记录，进度、任务、日历与页数统计都会更新，
  /// 但不会影响阅读速度。
  Future<int> logPagesRead({
    required int bookId,
    required int reachedPage,
    DateTime? at,
  }) async {
    final settings = await db.loadSettings();
    final when = at ?? DateTime.now();
    final book = await getBook(bookId);
    if (book == null || book.totalPages <= 0) return 0;
    final reached = reachedPage.clamp(0, book.totalPages);
    final pages = max<int>(0, reached - book.currentPage);
    if (pages <= 0) return 0;

    final date = logicalDate(when, settings.settlementMinutes);
    final task = await taskForBookOnDate(bookId, date);
    final status = book.status == BookStatus.finished
        ? book.status
        : BookStatus.reading;

    await db
        .into(db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: bookId,
            taskId: Value(task?.id),
            startedAt: when,
            endedAt: when,
            durationSeconds: 0,
            pagesRead: Value(pages),
            round: Value(book.round),
          ),
        );

    await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(currentPage: Value(reached), status: Value(status)),
    );

    if (task != null) {
      final readToday = await pagesReadOn(bookId, date);
      final targetPages = task.endPage - task.startPage + 1;
      if (reached >= task.endPage || readToday >= targetPages) {
        await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
          const TasksCompanion(status: Value('done')),
        );
      }
    }

    final updated = await getBook(bookId);
    if (updated != null) await _syncBookCompletion(updated);
    if (reached < book.totalPages && status == BookStatus.reading) {
      final plan = await getPlanForBook(bookId);
      if (plan != null) await reschedulePlan(plan.id);
    }
    return pages;
  }

  /// 结束计时：写一条 session，把时长累加到「这本书今天的任务」，更新进度并重排。
  ///
  /// 无论计时从哪开始（任务卡 / 读物详情），只要这本书今天有任务，
  /// 时长就会计进该任务；[completeTask] 为 true 时同时把任务标记完成。
  Future<void> stopTimer({
    int? reachedPage,
    bool completeTask = false,
    DateTime? now,
    int? fallbackBookId,
    int? durationSeconds,
  }) async {
    final settings = await db.loadSettings();
    final startedAt = settings.activeStartedAt;
    final bookId = settings.activeBookId ?? fallbackBookId;
    if (startedAt == null || bookId == null) return;

    final endedAt = now ?? DateTime.now();
    final runningSince = settings.activeRunningSince;
    final live = runningSince == null
        ? 0
        : max<int>(0, endedAt.difference(runningSince).inSeconds);
    final seconds = max<int>(
      1,
      durationSeconds ?? (settings.activeAccumulatedSeconds + live),
    );
    final recordedEnd = durationSeconds == null
        ? endedAt
        : startedAt.add(Duration(seconds: seconds));
    final startedTaskId = settings.activeTaskId;

    final book = await getBook(bookId);
    // 阅读归属日：按计时开始时刻和结算时间判断，跨过结算点后仍归前一天。
    final timerDate = logicalDate(startedAt, settings.settlementMinutes);

    // 归属任务：计时时绑定的任务优先；否则归到这本书「今天」的任务。
    Task? task;
    if (startedTaskId != null) {
      task = await getTask(startedTaskId);
    } else {
      task = await taskForBookOnDate(bookId, timerDate);
    }

    // 本次读到的页码（绝对值），以及本次推进的页数（相对上次进度的增量）。
    // 用增量而非任务起始页，避免同一任务多次计时重复计数。
    final previousPage =
        book?.currentPage ?? ((task != null ? task.startPage : 1) - 1);
    int? effectiveReached;
    if (task != null) {
      effectiveReached = reachedPage ?? (completeTask ? task.endPage : null);
    } else if (reachedPage != null && book != null) {
      effectiveReached = reachedPage.clamp(0, book.totalPages);
    }
    final pagesRead = effectiveReached == null
        ? null
        : max<int>(0, effectiveReached - previousPage);

    await db
        .into(db.readingSessions)
        .insert(
          ReadingSessionsCompanion.insert(
            bookId: bookId,
            taskId: Value(task?.id),
            startedAt: startedAt,
            endedAt: recordedEnd,
            durationSeconds: seconds,
            pagesRead: Value(pagesRead),
            round: Value(book?.round ?? 1),
          ),
        );

    await cancelTimer();

    if (task != null) {
      final target = task;
      await (db.update(db.tasks)..where((t) => t.id.equals(target.id))).write(
        TasksCompanion(
          status: completeTask ? const Value('done') : const Value.absent(),
          // 仅完成任务时写入；否则会用「按天聚合的 session」展示实际用时，
          // 以免被重排（删建 pending 任务）抹掉。
          actualMinutes: completeTask
              ? Value((target.actualMinutes ?? 0) + (seconds / 60).round())
              : const Value.absent(),
          reachedPage: reachedPage == null
              ? const Value.absent()
              : Value(reachedPage),
        ),
      );
      final newPage = completeTask
          ? (reachedPage ?? target.endPage)
          : reachedPage;
      if (newPage != null && book != null) {
        await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
          BooksCompanion(currentPage: Value(newPage.clamp(0, book.totalPages))),
        );
      }
    } else if (effectiveReached != null && book != null) {
      await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
        BooksCompanion(currentPage: Value(effectiveReached)),
      );
    }
    final updatedBook = await getBook(bookId);
    if (updatedBook != null) await _syncBookCompletion(updatedBook);

    // 达到今天的目标页数就自动完成任务。
    if (task != null && !completeTask) {
      final targetPages = task.endPage - task.startPage + 1;
      final readToday = await pagesReadOn(bookId, timerDate);
      if (readToday >= targetPages) {
        await (db.update(db.tasks)..where((t) => t.id.equals(task!.id))).write(
          const TasksCompanion(status: Value('done')),
        );
      }
    }

    await recomputeMeasuredPace(bookId);
    final plan = await getPlanForBook(bookId);
    if (plan != null) await reschedulePlan(plan.id);
  }

  /// 某本书在某天的任务（优先未完成的）。
  Future<Task?> taskForBookOnDate(int bookId, DateTime date) {
    return (db.select(db.tasks)
          ..where(
            (t) =>
                t.bookId.equals(bookId) &
                t.date.equals(dateOnly(date)) &
                t.status.isNotValue('skipped'),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 监听某本书某天的任务。
  Stream<Task?> watchTaskForBookOnDate(int bookId, DateTime date) {
    return (db.select(db.tasks)
          ..where(
            (t) =>
                t.bookId.equals(bookId) &
                t.date.equals(dateOnly(date)) &
                t.status.isNotValue('skipped'),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(1))
        .watchSingleOrNull();
  }

  /// 某本书某个「结算日」累计读了多少页。
  Future<int> pagesReadOn(
    int bookId,
    DateTime date, {
    int? settlementMinutes,
  }) async {
    final minutes =
        settlementMinutes ?? (await db.loadSettings()).settlementMinutes;
    final start = logicalDayStart(date, minutes);
    final end = logicalDayStart(addDays(dateOnly(date), 1), minutes);
    final sessions =
        await (db.select(db.readingSessions)..where(
              (t) =>
                  t.bookId.equals(bookId) &
                  t.startedAt.isBiggerOrEqualValue(start) &
                  t.startedAt.isSmallerThanValue(end),
            ))
            .get();
    var total = 0;
    for (final s in sessions) {
      total += s.pagesRead ?? 0;
    }
    return total;
  }

  /// 根据该书所有计时记录重算自动学习速度。
  Future<void> recomputeMeasuredPace(int bookId) async {
    final sessions =
        await (db.select(db.readingSessions)..where(
              (t) =>
                  t.bookId.equals(bookId) &
                  t.pagesRead.isNotNull() &
                  t.durationSeconds.isBiggerThanValue(0),
            ))
            .get();
    final totalPages = sessions.fold<int>(0, (s, e) => s + (e.pagesRead ?? 0));
    final totalSeconds = sessions.fold<int>(0, (s, e) => s + e.durationSeconds);
    if (totalPages <= 0 || totalSeconds <= 0) return;

    final pace = totalPages / (totalSeconds / 3600);
    await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(
      BooksCompanion(measuredPagesPerHour: Value(pace)),
    );
  }

  Stream<List<ReadingSession>> watchSessions(int bookId) {
    return (db.select(db.readingSessions)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
        .watch();
  }

  /// 全部书的计时记录（按时间倒序），用于全局统计。
  Stream<List<ReadingSession>> watchAllSessions() {
    return (db.select(
      db.readingSessions,
    )..orderBy([(t) => OrderingTerm.desc(t.startedAt)])).watch();
  }

  /// [from, to] 结算日范围内开始的计时记录。
  Stream<List<ReadingSession>> watchSessionsBetween(
    DateTime from,
    DateTime to, {
    int settlementMinutes = 0,
  }) {
    final start = logicalDayStart(from, settlementMinutes);
    final end = logicalDayStart(addDays(dateOnly(to), 1), settlementMinutes);
    return (db.select(db.readingSessions)
          ..where(
            (t) =>
                t.startedAt.isBiggerOrEqualValue(start) &
                t.startedAt.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
        .watch();
  }

  /// 按结算日聚合的阅读统计（倒序，最近的在前面）。
  Stream<List<DailyStat>> watchDailyStats(
    int bookId, {
    int settlementMinutes = 0,
  }) {
    return watchSessions(bookId).map((sessions) {
      final acc = <DateTime, _DayAcc>{};
      for (final s in sessions) {
        final d = logicalDate(s.startedAt, settlementMinutes);
        final a = acc.putIfAbsent(d, _DayAcc.new);
        a.seconds += s.durationSeconds;
        a.pages += s.pagesRead ?? 0;
        a.sessions += 1;
      }
      final list = [
        for (final e in acc.entries)
          DailyStat(
            date: e.key,
            seconds: e.value.seconds,
            pages: e.value.pages,
            sessions: e.value.sessions,
          ),
      ]..sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Future<BookStats> bookStats(int bookId) async {
    final sessions = await (db.select(
      db.readingSessions,
    )..where((t) => t.bookId.equals(bookId))).get();
    return BookStats(
      sessionCount: sessions.length,
      totalSeconds: sessions.fold<int>(0, (s, e) => s + e.durationSeconds),
      totalPages: sessions.fold<int>(0, (s, e) => s + (e.pagesRead ?? 0)),
      timedPages: sessions
          .where((s) => s.durationSeconds > 0)
          .fold<int>(0, (sum, s) => sum + (s.pagesRead ?? 0)),
    );
  }

  Stream<BookStats> watchBookStats(int bookId) {
    return watchSessions(bookId).map(
      (sessions) => BookStats(
        sessionCount: sessions.length,
        totalSeconds: sessions.fold<int>(0, (s, e) => s + e.durationSeconds),
        totalPages: sessions.fold<int>(0, (s, e) => s + (e.pagesRead ?? 0)),
        timedPages: sessions
            .where((s) => s.durationSeconds > 0)
            .fold<int>(0, (sum, s) => sum + (s.pagesRead ?? 0)),
      ),
    );
  }

  // ---------- 设置 ----------

  /// 设置「计时时自动打开指定应用」。
  Future<void> updateAutoOpenApp({
    bool? enabled,
    String? packageName,
    String? appName,
  }) async {
    await db.loadSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(
        autoOpenApp: enabled == null ? const Value.absent() : Value(enabled),
        autoOpenPackage: packageName == null
            ? const Value.absent()
            : Value(packageName),
        autoOpenAppName: appName == null
            ? const Value.absent()
            : Value(appName),
      ),
    );
  }

  Future<void> updateSettings({
    int? pagesPerHour,
    int? defaultDailyMinutes,
    String? defaultWeekdays,
    int? settlementMinutes,
  }) async {
    await db.loadSettings();
    await (db.update(db.appSettings)..where((t) => t.id.equals(1))).write(
      AppSettingsCompanion(
        pagesPerHour: pagesPerHour == null
            ? const Value.absent()
            : Value(pagesPerHour),
        defaultDailyMinutes: defaultDailyMinutes == null
            ? const Value.absent()
            : Value(defaultDailyMinutes),
        defaultWeekdays: defaultWeekdays == null
            ? const Value.absent()
            : Value(defaultWeekdays),
        settlementMinutes: settlementMinutes == null
            ? const Value.absent()
            : Value(clampSettlementMinutes(settlementMinutes)),
      ),
    );
    await rescheduleAll();
  }

  static const _emptyResult = ScheduleResult(
    tasks: [],
    remainingPages: 0,
    pagesPerReadingDay: 0,
    capacityPagesPerDay: 0,
    readingDays: 0,
    hasDeadline: false,
  );
}

class _DayAcc {
  int seconds = 0;
  int pages = 0;
  int sessions = 0;
}
