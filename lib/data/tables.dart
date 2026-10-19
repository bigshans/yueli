import 'package:drift/drift.dart';

/// 读物。MVP 以「页」为粒度，预留章节扩展。
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  IntColumn get totalPages => integer()();

  /// 已读到的页码（读完的页数），下一页从 currentPage + 1 开始。
  IntColumn get currentPage => integer().withDefault(const Constant(0))();

  /// 1 = 高，2 = 中，3 = 低。
  IntColumn get priority => integer().withDefault(const Constant(2))();

  /// 标签，逗号分隔。
  TextColumn get tags => text().nullable()();

  /// 当前是第几遍阅读（重读会递增）。
  IntColumn get round => integer().withDefault(const Constant(1))();

  /// 是否搁置。搁置后不再生成/展示待读任务，恢复时从当前进度继续排期。
  BoolColumn get shelved => boolean().withDefault(const Constant(false))();

  /// 用户手填的阅读速度（页/小时）。留空则用自动学习值或全局默认。
  IntColumn get manualPagesPerHour => integer().nullable()();

  /// 从计时记录自动学习的阅读速度（页/小时）。
  RealColumn get measuredPagesPerHour => real().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// 阅读排期计划：把一本书在时间上摊开。
class Plans extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startDate => dateTime()();

  /// 截止日。为空表示不设期限：按每日容量一直排到读完。
  DateTimeColumn get deadline => dateTime().nullable()();

  /// 每天可投入的阅读时长（分钟）。按时间排期时使用。
  IntColumn get dailyMinutes => integer()();

  /// 页数优先：每个阅读日要读多少页。非空时忽略 dailyMinutes。
  IntColumn get dailyPages => integer().nullable()();

  /// 允许阅读的星期，ISO 1=周一 .. 7=周日，逗号分隔。
  TextColumn get weekdays => text()();

  /// active | oversubscribed | completed | archived
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// 每日阅读任务，排期的最小单元。
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId =>
      integer().references(Plans, #id, onDelete: KeyAction.cascade)();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();

  /// 闭区间 [startPage, endPage]，1-based。
  IntColumn get startPage => integer()();
  IntColumn get endPage => integer()();
  IntColumn get plannedMinutes => integer()();
  IntColumn get actualMinutes => integer().nullable()();

  /// 完成当天任务时实际读到的页码（可能与计划末页不同）。
  IntColumn get reachedPage => integer().nullable()();

  /// pending | done | skipped
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// 一次计时阅读记录，用于统计与学习个人阅读速度。
class ReadingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();

  /// 关联的任务（可空）。任务会被重排删建，故不设外键。
  IntColumn get taskId => integer().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get durationSeconds => integer()();
  IntColumn get pagesRead => integer().nullable()();

  /// 属于第几遍阅读。
  IntColumn get round => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// 一本书的每一遍阅读记录。
class Readings extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId =>
      integer().references(Books, #id, onDelete: KeyAction.cascade)();
  IntColumn get round => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  /// 这一遍是否读完了（中途开始重读则为 false）。
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// 指定某计划中某天休息（不安排阅读）。
class RestDays extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get planId =>
      integer().references(Plans, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}

/// 全局偏好，单行（id 恒为 1）。也保存当前正在进行的计时。
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();

  /// 个人阅读速度：页/小时，作为未单独设置的书的默认值。
  IntColumn get pagesPerHour => integer().withDefault(const Constant(30))();
  IntColumn get defaultDailyMinutes =>
      integer().withDefault(const Constant(30))();
  TextColumn get defaultWeekdays =>
      text().withDefault(const Constant('1,2,3,4,5,6,7'))();

  /// 正在进行的计时：书籍 / 任务 / 开始时刻。三者同时为空表示未计时。
  IntColumn get activeBookId => integer().nullable()();
  IntColumn get activeTaskId => integer().nullable()();

  /// 整个计时会话开始的时刻（含暂停前的时间，用于 session 记录）。
  DateTimeColumn get activeStartedAt => dateTime().nullable()();

  /// 当前这一段「正在跑」的起点；为 null 表示已暂停。
  DateTimeColumn get activeRunningSince => dateTime().nullable()();

  /// 暂停前已累计的秒数。
  IntColumn get activeAccumulatedSeconds =>
      integer().withDefault(const Constant(0))();

  /// 安卓端：计时开始时自动打开指定应用。
  BoolColumn get autoOpenApp => boolean().withDefault(const Constant(false))();
  TextColumn get autoOpenPackage => text().nullable()();
  TextColumn get autoOpenAppName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
