import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/data/database.dart';
import 'package:reader_management/data/repository.dart';
import 'package:reader_management/state/providers.dart';
import 'package:reader_management/ui/widgets/record_edit_sheet.dart';

void main() {
  late AppDatabase db;
  late ReadingRepository repo;
  late int bookId;
  late ReadingSession session;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReadingRepository(db);
    bookId = await repo.createBook(title: '纠错书', totalPages: 320);
    await repo.logPagesRead(
      bookId: bookId,
      reachedPage: 268,
      at: DateTime(2024, 5, 1, 12),
    );
    session = (await (db.select(db.readingSessions)).get()).single;
  });

  tearDown(() => db.close());

  // 有界等待：给数据库流和首帧足够时间，但不会被无限动画卡死。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  }

  Widget app() {
    return ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSessionEditSheet(context, session),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('编辑弹窗预填页码并提示保存后的进度变化', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('打开'));
    await settle(tester);

    expect(find.text('编辑阅读记录'), findsOneWidget);
    expect(find.text('共 320 页'), findsOneWidget);
    expect(find.text('保存后进度仍是第 268 页，后续任务会重新安排。'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '168');
    await settle(tester);

    expect(find.text('保存后：进度第 268 页 → 第 168 页，后续任务会重新安排。'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await settle(tester);

    expect(find.text('编辑阅读记录'), findsNothing);
    expect((await repo.getBook(bookId))!.currentPage, 168);
    expect((await repo.getSession(session.id))!.pagesRead, 168);
    // 让保存后的 SnackBar 计时器走完，再卸载组件树。
    await tester.pump(const Duration(seconds: 6));
    await unmount(tester);
  });

  testWidgets('页码低于上一条时禁止保存并给出提示', (tester) async {
    await repo.logPagesRead(
      bookId: bookId,
      reachedPage: 300,
      at: DateTime(2024, 5, 2, 12),
    );
    final last = (await (db.select(db.readingSessions)).get()).last;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSessionEditSheet(context, last),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, '100');
    await settle(tester);

    expect(find.text('不能早于第 268 页'), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '保存'),
    );
    expect(save.onPressed, isNull);
    await unmount(tester);
  });
}
