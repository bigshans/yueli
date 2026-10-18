import 'dart:convert';

import 'package:drift/drift.dart';

import 'database.dart';

/// 备份文件格式不合法（不是阅历导出的 JSON、版本不支持、字段缺失等）。
class BackupFormatException implements Exception {
  BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次导入的结果，用于提示用户。
class ImportSummary {
  const ImportSummary({
    required this.books,
    required this.plans,
    required this.tasks,
    required this.sessions,
    required this.readings,
    required this.restDays,
  });

  final int books;
  final int plans;
  final int tasks;
  final int sessions;
  final int readings;
  final int restDays;

  @override
  String toString() =>
      '读物 $books 本 · 计划 $plans 个 · 任务 $tasks 条 · '
      '计时 $sessions 次 · 阅读轮次 $readings 条 · 休息日 $restDays 天';
}

/// 阅历数据的完整导出 / 导入。
///
/// 备份格式是带版本号的 JSON：
/// `{ "app": "reader-management", "format": 1, "exportedAt": ..., "data": {...} }`。
/// 导入为「整库恢复」：先清空现有阅读数据，再按备份中的 id 原样写回，
/// 因此计划、任务、计时记录之间的关联不会丢失。
class BackupService {
  BackupService(this.db);

  final AppDatabase db;

  static const appId = 'reader-management';
  static const formatVersion = 1;

  Future<String> exportJson({DateTime? now}) async {
    final books = await db.select(db.books).get();
    final plans = await db.select(db.plans).get();
    final tasks = await db.select(db.tasks).get();
    final sessions = await db.select(db.readingSessions).get();
    final readings = await db.select(db.readings).get();
    final restDays = await db.select(db.restDays).get();
    final settings = await db.loadSettings();

    return const JsonEncoder.withIndent('  ').convert({
      'app': appId,
      'format': formatVersion,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'data': {
        'books': books.map(_bookToJson).toList(),
        'plans': plans.map(_planToJson).toList(),
        'tasks': tasks.map(_taskToJson).toList(),
        'readingSessions': sessions.map(_sessionToJson).toList(),
        'readings': readings.map(_readingToJson).toList(),
        'restDays': restDays.map(_restDayToJson).toList(),
        'settings': {
          'pagesPerHour': settings.pagesPerHour,
          'defaultDailyMinutes': settings.defaultDailyMinutes,
          'defaultWeekdays': settings.defaultWeekdays,
          'autoOpenApp': settings.autoOpenApp,
          'autoOpenPackage': settings.autoOpenPackage,
          'autoOpenAppName': settings.autoOpenAppName,
        },
      },
    });
  }

  Future<ImportSummary> importJson(String raw) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw BackupFormatException('不是有效的 JSON：${e.message}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw BackupFormatException('备份文件内容格式不正确');
    }
    if (decoded['app'] != appId) {
      throw BackupFormatException('这不是阅历导出的备份文件');
    }
    final format = _asInt(decoded['format'], 0);
    if (format <= 0 || format > formatVersion) {
      throw BackupFormatException('备份格式版本不支持（$format）');
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw BackupFormatException('备份文件缺少数据内容');
    }

    final books = _asList(data['books']);
    final plans = _asList(data['plans']);
    final tasks = _asList(data['tasks']);
    final sessions = _asList(data['readingSessions']);
    final readings = _asList(data['readings']);
    final restDays = _asList(data['restDays']);
    final settings = data['settings'];

    await db.transaction(() async {
      // 先删子表，再删主表；保留 appSettings 行本身。
      await db.delete(db.readingSessions).go();
      await db.delete(db.tasks).go();
      await db.delete(db.restDays).go();
      await db.delete(db.readings).go();
      await db.delete(db.plans).go();
      await db.delete(db.books).go();

      for (final row in books) {
        await db.into(db.books).insert(_bookFromJson(row));
      }
      for (final row in readings) {
        await db.into(db.readings).insert(_readingFromJson(row));
      }
      for (final row in plans) {
        await db.into(db.plans).insert(_planFromJson(row));
      }
      for (final row in tasks) {
        await db.into(db.tasks).insert(_taskFromJson(row));
      }
      for (final row in restDays) {
        await db.into(db.restDays).insert(_restDayFromJson(row));
      }
      for (final row in sessions) {
        await db.into(db.readingSessions).insert(_sessionFromJson(row));
      }

      final current = await db.loadSettings();
      final imported = settings is Map<String, dynamic>
          ? _settingsFromJson(settings, current)
          : const AppSettingsCompanion(
              activeBookId: Value(null),
              activeTaskId: Value(null),
              activeStartedAt: Value(null),
              activeRunningSince: Value(null),
              activeAccumulatedSeconds: Value(0),
            );
      await (db.update(
        db.appSettings,
      )..where((t) => t.id.equals(1))).write(imported);
    });

    return ImportSummary(
      books: books.length,
      plans: plans.length,
      tasks: tasks.length,
      sessions: sessions.length,
      readings: readings.length,
      restDays: restDays.length,
    );
  }

  // ---------- 导出 ----------

  Map<String, Object?> _bookToJson(Book b) => {
    'id': b.id,
    'title': b.title,
    'author': b.author,
    'totalPages': b.totalPages,
    'currentPage': b.currentPage,
    'priority': b.priority,
    'tags': b.tags,
    'round': b.round,
    'manualPagesPerHour': b.manualPagesPerHour,
    'measuredPagesPerHour': b.measuredPagesPerHour,
    'createdAt': b.createdAt.toIso8601String(),
  };

  Map<String, Object?> _planToJson(Plan p) => {
    'id': p.id,
    'bookId': p.bookId,
    'startDate': p.startDate.toIso8601String(),
    'deadline': p.deadline?.toIso8601String(),
    'dailyMinutes': p.dailyMinutes,
    'dailyPages': p.dailyPages,
    'weekdays': p.weekdays,
    'status': p.status,
    'createdAt': p.createdAt.toIso8601String(),
  };

  Map<String, Object?> _taskToJson(Task t) => {
    'id': t.id,
    'planId': t.planId,
    'bookId': t.bookId,
    'date': t.date.toIso8601String(),
    'startPage': t.startPage,
    'endPage': t.endPage,
    'plannedMinutes': t.plannedMinutes,
    'actualMinutes': t.actualMinutes,
    'reachedPage': t.reachedPage,
    'status': t.status,
    'createdAt': t.createdAt.toIso8601String(),
  };

  Map<String, Object?> _sessionToJson(ReadingSession s) => {
    'id': s.id,
    'bookId': s.bookId,
    'taskId': s.taskId,
    'startedAt': s.startedAt.toIso8601String(),
    'endedAt': s.endedAt.toIso8601String(),
    'durationSeconds': s.durationSeconds,
    'pagesRead': s.pagesRead,
    'round': s.round,
    'createdAt': s.createdAt.toIso8601String(),
  };

  Map<String, Object?> _readingToJson(Reading r) => {
    'id': r.id,
    'bookId': r.bookId,
    'round': r.round,
    'startedAt': r.startedAt.toIso8601String(),
    'finishedAt': r.finishedAt?.toIso8601String(),
    'completed': r.completed,
    'createdAt': r.createdAt.toIso8601String(),
  };

  Map<String, Object?> _restDayToJson(RestDay r) => {
    'id': r.id,
    'planId': r.planId,
    'date': r.date.toIso8601String(),
    'createdAt': r.createdAt.toIso8601String(),
  };

  // ---------- 导入 ----------

  BooksCompanion _bookFromJson(Map<String, dynamic> m) => BooksCompanion(
    id: Value(_asInt(m['id'], 0)),
    title: Value(_asString(m['title'], '未命名读物')),
    author: Value(_asNullableString(m['author'])),
    totalPages: Value(_asInt(m['totalPages'], 0)),
    currentPage: Value(_asInt(m['currentPage'], 0)),
    priority: Value(_asInt(m['priority'], 2)),
    tags: Value(_asNullableString(m['tags'])),
    round: Value(_asInt(m['round'], 1)),
    manualPagesPerHour: Value(_asNullableInt(m['manualPagesPerHour'])),
    measuredPagesPerHour: Value(_asNullableDouble(m['measuredPagesPerHour'])),
    createdAt: Value(_asDate(m['createdAt'])),
  );

  PlansCompanion _planFromJson(Map<String, dynamic> m) => PlansCompanion(
    id: Value(_asInt(m['id'], 0)),
    bookId: Value(_asInt(m['bookId'], 0)),
    startDate: Value(_asDate(m['startDate'])),
    deadline: Value(_asNullableDate(m['deadline'])),
    dailyMinutes: Value(_asInt(m['dailyMinutes'], 30)),
    dailyPages: Value(_asNullableInt(m['dailyPages'])),
    weekdays: Value(_asString(m['weekdays'], '1,2,3,4,5,6,7')),
    status: Value(_asString(m['status'], 'active')),
    createdAt: Value(_asDate(m['createdAt'])),
  );

  TasksCompanion _taskFromJson(Map<String, dynamic> m) => TasksCompanion(
    id: Value(_asInt(m['id'], 0)),
    planId: Value(_asInt(m['planId'], 0)),
    bookId: Value(_asInt(m['bookId'], 0)),
    date: Value(_asDate(m['date'])),
    startPage: Value(_asInt(m['startPage'], 1)),
    endPage: Value(_asInt(m['endPage'], 1)),
    plannedMinutes: Value(_asInt(m['plannedMinutes'], 0)),
    actualMinutes: Value(_asNullableInt(m['actualMinutes'])),
    reachedPage: Value(_asNullableInt(m['reachedPage'])),
    status: Value(_asString(m['status'], 'pending')),
    createdAt: Value(_asDate(m['createdAt'])),
  );

  ReadingSessionsCompanion _sessionFromJson(Map<String, dynamic> m) =>
      ReadingSessionsCompanion(
        id: Value(_asInt(m['id'], 0)),
        bookId: Value(_asInt(m['bookId'], 0)),
        taskId: Value(_asNullableInt(m['taskId'])),
        startedAt: Value(_asDate(m['startedAt'])),
        endedAt: Value(_asDate(m['endedAt'])),
        durationSeconds: Value(_asInt(m['durationSeconds'], 0)),
        pagesRead: Value(_asNullableInt(m['pagesRead'])),
        round: Value(_asInt(m['round'], 1)),
        createdAt: Value(_asDate(m['createdAt'])),
      );

  ReadingsCompanion _readingFromJson(Map<String, dynamic> m) =>
      ReadingsCompanion(
        id: Value(_asInt(m['id'], 0)),
        bookId: Value(_asInt(m['bookId'], 0)),
        round: Value(_asInt(m['round'], 1)),
        startedAt: Value(_asDate(m['startedAt'])),
        finishedAt: Value(_asNullableDate(m['finishedAt'])),
        completed: Value(_asBool(m['completed'])),
        createdAt: Value(_asDate(m['createdAt'])),
      );

  RestDaysCompanion _restDayFromJson(Map<String, dynamic> m) =>
      RestDaysCompanion(
        id: Value(_asInt(m['id'], 0)),
        planId: Value(_asInt(m['planId'], 0)),
        date: Value(_asDate(m['date'])),
        createdAt: Value(_asDate(m['createdAt'])),
      );

  AppSettingsCompanion _settingsFromJson(
    Map<String, dynamic> m,
    AppSetting current,
  ) {
    return AppSettingsCompanion(
      pagesPerHour: Value(_asInt(m['pagesPerHour'], current.pagesPerHour)),
      defaultDailyMinutes: Value(
        _asInt(m['defaultDailyMinutes'], current.defaultDailyMinutes),
      ),
      defaultWeekdays: Value(
        _asString(m['defaultWeekdays'], current.defaultWeekdays),
      ),
      autoOpenApp: Value(_asBool(m['autoOpenApp'])),
      autoOpenPackage: Value(_asNullableString(m['autoOpenPackage'])),
      autoOpenAppName: Value(_asNullableString(m['autoOpenAppName'])),
      // 计时状态不进入备份，导入后一律回到未计时。
      activeBookId: const Value(null),
      activeTaskId: const Value(null),
      activeStartedAt: const Value(null),
      activeRunningSince: const Value(null),
      activeAccumulatedSeconds: const Value(0),
    );
  }

  // ---------- 安全取值 ----------

  List<Map<String, dynamic>> _asList(Object? value) {
    if (value == null) return const [];
    if (value is! List) throw BackupFormatException('备份文件数据结构不正确');
    final result = <Map<String, dynamic>>[];
    for (final item in value) {
      if (item is! Map<String, dynamic>) {
        throw BackupFormatException('备份文件数据结构不正确');
      }
      result.add(item);
    }
    return result;
  }

  String _asString(Object? value, String fallback) =>
      value is String && value.isNotEmpty ? value : fallback;

  String? _asNullableString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  int _asInt(Object? value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  int? _asNullableInt(Object? value) {
    if (value == null) return null;
    return _asInt(value, 0);
  }

  double? _asNullableDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  DateTime _asDate(Object? value) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    throw BackupFormatException('备份文件中的日期格式不正确');
  }

  DateTime? _asNullableDate(Object? value) =>
      value == null ? null : _asDate(value);
}
