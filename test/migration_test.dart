import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/data/database.dart';

void main() {
  test('半迁移状态可自愈：tags 已存在但 user_version 落后时不再重复 ADD COLUMN', () async {
    final file = File(
      '${Directory.systemTemp.path}/yueli_migration_'
      '${DateTime.now().microsecondsSinceEpoch}.db',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    // 1) 用当前 schema 建库，得到包含 tags 的 books 表。
    var db = AppDatabase(NativeDatabase(file));
    final id = await db.into(db.books).insert(
          BooksCompanion.insert(title: '测试书', totalPages: 100),
        );
    // 2) 把版本号退回 6，模拟「列已加上但版本没更新」的半迁移状态。
    await db.customStatement('PRAGMA user_version = 6');
    await db.close();

    // 3) 重新打开会触发 6 -> 10 迁移。旧实现会在这里抛
    //    duplicate column name: tags。
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    final book =
        await (db.select(db.books)..where((t) => t.id.equals(id))).getSingle();
    expect(book.title, '测试书');

    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle()
        .then((r) => r.read<int>('user_version'));
    expect(version, 11);

    // 回填的轮次记录应存在。
    final rounds = await (db.select(db.readings)
          ..where((t) => t.bookId.equals(id)))
        .get();
    expect(rounds, isNotEmpty);
  });
}
