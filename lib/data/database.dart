import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Books, Plans, Tasks, ReadingSessions, RestDays, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  static QueryExecutor _open() => driftDatabase(name: 'reader_management');

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(books, books.manualPagesPerHour);
            await m.addColumn(books, books.measuredPagesPerHour);
            await m.alterTable(TableMigration(plans));
            await m.createTable(readingSessions);
            await m.addColumn(appSettings, appSettings.activeBookId);
            await m.addColumn(appSettings, appSettings.activeTaskId);
            await m.addColumn(appSettings, appSettings.activeStartedAt);
          }
          if (from < 3) {
            await m.addColumn(appSettings, appSettings.activeRunningSince);
            await m.addColumn(
                appSettings, appSettings.activeAccumulatedSeconds);
          }
          if (from < 4) {
            await m.addColumn(plans, plans.dailyPages);
          }
          if (from < 5) {
            await m.addColumn(tasks, tasks.reachedPage);
          }
          if (from < 6) {
            await m.createTable(restDays);
          }
          if (from < 7) {
            await m.addColumn(books, books.tags);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

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
