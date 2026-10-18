import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/core/date_x.dart';
import 'package:reader_management/data/backup.dart';
import 'package:reader_management/data/database.dart';
import 'package:reader_management/data/repository.dart';

void main() {
  late AppDatabase db;
  late ReadingRepository repo;
  late BackupService backup;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReadingRepository(db);
    backup = BackupService(db);
  });

  tearDown(() => db.close());

  Future<int> seed() async {
    final id = await repo.createBook(
      title: '备份测试书',
      author: '作者',
      totalPages: 120,
      tags: '小说,测试',
      manualPagesPerHour: 45,
    );
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 5),
      dailyMinutes: 45,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );
    final plan = await repo.getPlanForBook(id);
    await repo.addRestDay(plan!.id, addDays(today(), 2));

    final t0 = today().add(const Duration(hours: 9));
    await repo.startTimer(bookId: id, now: t0);
    await repo.stopTimer(
      reachedPage: 18,
      now: t0.add(const Duration(minutes: 40)),
    );
    return id;
  }

  test('导出的备份可以完整恢复，并覆盖现有数据', () async {
    final id = await seed();
    final plan = await repo.getPlanForBook(id);
    final json = await backup.exportJson();

    // 导出后继续改数据，再导入备份，应当回到导出时的状态。
    await repo.createBook(title: '临时书', totalPages: 10);
    await repo.updateSettings(pagesPerHour: 99);

    final summary = await backup.importJson(json);

    expect(summary.books, 1);
    expect(summary.plans, 1);
    expect(summary.sessions, 1);
    expect(summary.readings, 1);

    final books = await repo.allBooks();
    expect(books.length, 1);
    expect(books.single.id, id);
    expect(books.single.title, '备份测试书');
    expect(books.single.author, '作者');
    expect(books.single.tags, '小说,测试');
    expect(books.single.manualPagesPerHour, 45);
    expect(books.single.currentPage, 18);

    final restoredPlan = await repo.getPlanForBook(id);
    expect(restoredPlan!.id, plan!.id);
    expect(restoredPlan.dailyMinutes, 45);
    expect(
      (await repo.restDates(restoredPlan.id)).contains(addDays(today(), 2)),
      isTrue,
    );

    final stats = await repo.bookStats(id);
    expect(stats.sessionCount, 1);
    expect(stats.totalPages, 18);
    expect(stats.totalSeconds, 40 * 60);

    final settings = await db.loadSettings();
    expect(settings.pagesPerHour, 30); // 恢复导出时的设置，而不是导出后的 99
    expect(settings.activeStartedAt, isNull); // 计时状态不进入备份
  });

  test('非法备份不会清空现有数据', () async {
    final id = await repo.createBook(title: '原书', totalPages: 20);

    await expectLater(
      backup.importJson('{"app":"other","format":1,"data":{}}'),
      throwsA(isA<BackupFormatException>()),
    );
    await expectLater(
      backup.importJson('不是 JSON'),
      throwsA(isA<BackupFormatException>()),
    );

    final books = await repo.allBooks();
    expect(books.length, 1);
    expect(books.single.id, id);
  });

  test('CSV 历史包含每次计时记录', () async {
    await seed();
    final csv = await backup.exportSessionsCsv();

    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('日期,开始时间,结束时间,书名,轮次'));
    expect(csv, contains('备份测试书'));
    expect(csv, contains('18')); // 本次读到的页数
    expect(csv.trim().split('\n').length, 2); // 表头 + 一条记录
  });

  test('ZIP 一次性导出可完整导入，并包含历史 CSV', () async {
    final id = await seed();
    final bytes = await backup.exportArchiveBytes();

    expect(bytes.length, greaterThan(0));
    expect(bytes[0], 0x50); // ZIP 魔数
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    expect(archive.find('backup.json'), isNotNull);
    final csv = archive.find('history.csv');
    expect(csv, isNotNull);
    expect(utf8.decode(csv!.content), contains('备份测试书'));

    await repo.createBook(title: '临时书', totalPages: 10);
    final summary = await backup.importBytes(bytes, fileName: 'yueli.zip');

    expect(summary.books, 1);
    expect(summary.sessions, 1);
    final books = await repo.allBooks();
    expect(books.length, 1);
    expect(books.single.id, id);
    expect(books.single.title, '备份测试书');
  });
}
