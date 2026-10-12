import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reader_management/app.dart';
import 'package:reader_management/core/date_x.dart';
import 'package:reader_management/data/database.dart';
import 'package:reader_management/data/repository.dart';
import 'package:reader_management/state/providers.dart';
import 'package:reader_management/ui/calendar_page.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('zh_CN');
  });

  Widget appWith(AppDatabase db) => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const ReaderApp(),
      );

  // 有界等待：给数据库流和首帧足够时间，但不会被无限动画卡死。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // 卸载组件树，让 drift 在 dispose 时调度的 0 秒 Timer 有机会执行。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('没有排期时今日页显示空状态', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(appWith(db));
    await settle(tester);

    expect(find.text('今天没有排期'), findsOneWidget);
    expect(find.text('书架'), findsWidgets);
    expect(find.text('日历'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('排期后今日页出现该读物的任务', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ReadingRepository(db);
    final id = await repo.createBook(title: '示例书', totalPages: 30);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 2),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    await tester.pumpWidget(appWith(db));
    await settle(tester);

    expect(find.text('示例书'), findsWidgets);
    expect(find.text('今天没有排期'), findsNothing);
    await unmount(tester);
  });

  testWidgets('无截止日也能排出任务', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ReadingRepository(db);
    final id = await repo.createBook(title: '无期书', totalPages: 30);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: null,
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    final tasks = await repo.tasksBetween(today(), addDays(today(), 5));
    expect(tasks, isNotEmpty);

    await tester.pumpWidget(appWith(db));
    await settle(tester);
    expect(find.text('无期书'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('日历格子直接显示书名', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ReadingRepository(db);
    final id = await repo.createBook(title: '示例书', totalPages: 30);
    await repo.savePlan(
      bookId: id,
      startDate: today(),
      deadline: addDays(today(), 2),
      dailyMinutes: 60,
      weekdays: {1, 2, 3, 4, 5, 6, 7},
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: CalendarPage()),
    ));
    await settle(tester);

    expect(find.text('示例书'), findsWidgets);
    await unmount(tester);
  });
}
