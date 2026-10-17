import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
    tables: [Books, Plans, Tasks, ReadingSessions, Readings, RestDays, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: 'reader_management');

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // 迁移必须幂等：历史版本可能出现过「列已添加但版本号未更新」的
          // 半迁移状态，重复执行 ALTER 会报 duplicate column。这里不再依赖
          // from 的分支，而是逐项检查后再执行，能自动修复半迁移数据库。

          // 1) 确保所有表存在（CREATE TABLE IF NOT EXISTS，幂等）。
          await m.createAll();

          // 2) 补齐可能缺失的列（列已存在则跳过）。
          await _addColumnIfMissing(m, books, books.manualPagesPerHour);
          await _addColumnIfMissing(m, books, books.measuredPagesPerHour);
          await _addColumnIfMissing(m, books, books.round);
          await _addColumnIfMissing(m, books, books.tags);

          // plans.deadline 早期为 NOT NULL，需要重建表改为可空。
          if (await _hasTable('plans') &&
              await _columnNotNull('plans', 'deadline')) {
            await m.alterTable(TableMigration(plans));
          }
          await _addColumnIfMissing(m, plans, plans.dailyPages);

          await _addColumnIfMissing(m, tasks, tasks.reachedPage);

          await _addColumnIfMissing(m, appSettings, appSettings.activeBookId);
          await _addColumnIfMissing(m, appSettings, appSettings.activeTaskId);
          await _addColumnIfMissing(m, appSettings, appSettings.activeStartedAt);
          await _addColumnIfMissing(
              m, appSettings, appSettings.activeRunningSince);
          await _addColumnIfMissing(
              m, appSettings, appSettings.activeAccumulatedSeconds);
          await _addColumnIfMissing(m, appSettings, appSettings.autoOpenApp);
          await _addColumnIfMissing(
              m, appSettings, appSettings.autoOpenPackage);
          await _addColumnIfMissing(m, appSettings, appSettings.autoOpenAppName);

          await _addColumnIfMissing(
              m, readingSessions, readingSessions.round);
          await _addColumnIfMissing(m, readings, readings.completed);

          // 3) 数据回填（幂等）。
          await _backfillReadings();
          await (update(readings)..where((t) => t.finishedAt.isNotNull()))
              .write(const ReadingsCompanion(completed: Value(true)));
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<bool> _hasTable(String table) async {
    final rows = await customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _hasColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    return rows.any((r) => r.read<String>('name') == column);
  }

  Future<bool> _columnNotNull(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info("$table")').get();
    for (final r in rows) {
      if (r.read<String>('name') == column) {
        return r.read<int>('notnull') != 0;
      }
    }
    return false;
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn column,
  ) async {
    if (await _hasColumn(table.actualTableName, column.name)) return;
    await m.addColumn(table, column);
  }

  /// 为每本书补建缺失的「当前轮次」记录。
  Future<void> _backfillReadings() async {
    final allBooks = await select(books).get();
    for (final b in allBooks) {
      final existing = await (select(readings)
            ..where((t) => t.bookId.equals(b.id) & t.round.equals(b.round)))
          .getSingleOrNull();
      if (existing == null) {
        await into(readings).insert(ReadingsCompanion.insert(
          bookId: b.id,
          round: b.round,
          startedAt: b.createdAt,
        ));
      }
    }
  }

  /// 确保存在唯一的设置行。
  Future<AppSetting> loadSettings() async {
    final existing = await (select(appSettings)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    if (existing != null) return existing;
    await into(appSettings).insert(const AppSettingsCompanion());
    return (select(appSettings)..where((t) => t.id.equals(1))).getSingle();
  }

  Stream<AppSetting> watchSettings() {
    return (select(appSettings)..where((t) => t.id.equals(1)))
        .watchSingleOrNull()
        .asyncMap((row) async => row ?? await loadSettings());
  }
}
