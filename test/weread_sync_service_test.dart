import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_management/data/book_status.dart';
import 'package:reader_management/data/database.dart';
import 'package:reader_management/data/repository.dart';
import 'package:reader_management/services/weread/weread_client.dart';
import 'package:reader_management/services/weread/weread_sync_service.dart';

void main() {
  late AppDatabase db;
  late ReadingRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReadingRepository(db);
  });

  tearDown(() => db.close());

  WereadSyncService buildService(
    Map<String, Map<String, Object?>> progressByBook,
  ) {
    final client = WereadClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final bookId = body['bookId'] as String? ?? '';
        return http.Response(
          jsonEncode({'book': progressByBook[bookId] ?? {}}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return WereadSyncService(
      client: client,
      repository: repo,
      apiKeyLoader: () async => 'wrk-test',
    );
  }

  Future<int> linkedBook({
    required int totalPages,
    required int currentPage,
    required String wereadBookId,
    String status = BookStatus.reading,
  }) async {
    final id = await repo.createBook(
      title: '同步测试书',
      totalPages: totalPages,
      currentPage: currentPage,
      status: status,
    );
    await repo.linkWereadBook(bookId: id, wereadBookId: wereadBookId);
    return id;
  }

  test('远端进度领先时更新本地页码和关联状态', () async {
    final id = await linkedBook(
      totalPages: 100,
      currentPage: 10,
      wereadBookId: 'b1',
    );
    final service = buildService({
      'b1': {'progress': 45, 'recordReadingTime': 3600},
    });

    final result = await service.syncBook(id, updatePages: true);
    expect(result.changed, isTrue);
    expect(result.message, contains('估算'));
    expect(result.localPage, 45);

    final book = await repo.getBook(id);
    expect(book!.currentPage, 45);
    final link = await repo.getWereadLink(id);
    expect(link!.remoteProgress, 45);
    expect(link.remoteReadSeconds, 3600);
    expect(link.lastSyncedAt, isNotNull);
  });

  test('远端进度落后时保留本地进度', () async {
    final id = await linkedBook(
      totalPages: 100,
      currentPage: 80,
      wereadBookId: 'b1',
    );
    final service = buildService({
      'b1': {'progress': 45},
    });

    final result = await service.syncBook(id, updatePages: true);
    expect(result.changed, isFalse);
    expect(result.message, contains('保留本地'));
    expect((await repo.getBook(id))!.currentPage, 80);
    expect((await repo.getWereadLink(id))!.remoteProgress, 45);
  });

  test('远端 100% 且有 finishTime 时同步为已读', () async {
    final id = await linkedBook(
      totalPages: 100,
      currentPage: 60,
      wereadBookId: 'b1',
    );
    final service = buildService({
      'b1': {
        'progress': 100,
        'finishTime': 1760000000,
        'recordReadingTime': 7200,
      },
    });

    final result = await service.syncBook(id);
    expect(result.changed, isTrue);
    expect(result.finished, isTrue);
    final book = await repo.getBook(id);
    expect(book!.status, BookStatus.finished);
    expect(book.currentPage, 100);
  });

  test('100% 但缺少 finishTime 时不改动本地进度', () async {
    final id = await linkedBook(
      totalPages: 100,
      currentPage: 60,
      wereadBookId: 'b1',
    );
    final service = buildService({
      'b1': {'progress': 100},
    });

    final result = await service.syncBook(id);
    expect(result.changed, isFalse);
    expect(result.message, contains('缺少读完时间'));
    expect((await repo.getBook(id))!.currentPage, 60);
    expect((await repo.getBook(id))!.status, BookStatus.reading);
  });

  test('同步全部会统计更新、保留和失败', () async {
    final a = await linkedBook(
      totalPages: 100,
      currentPage: 10,
      wereadBookId: 'b1',
    );
    final b = await linkedBook(
      totalPages: 100,
      currentPage: 80,
      wereadBookId: 'b2',
    );
    final service = buildService({
      'b1': {'progress': 30},
      'b2': {'progress': 40},
    });

    final result = await service.syncAll(updatePages: true);
    expect(result.changed, 1);
    expect(result.kept, 1);
    expect(result.failed, 0);
    expect((await repo.getBook(a))!.currentPage, 30);
    expect((await repo.getBook(b))!.currentPage, 80);
  });
  test('默认只记录微信读书百分比，不把百分比直接写成本地页码', () async {
    final id = await linkedBook(
      totalPages: 100,
      currentPage: 10,
      wereadBookId: 'b1',
    );
    final service = buildService({
      'b1': {'progress': 45},
    });

    final result = await service.syncBook(id);
    expect(result.changed, isFalse);
    expect(result.estimatedPage, 45);
    expect(result.localPage, 10);
    expect(result.message, contains('本地页码未改动'));
    expect((await repo.getBook(id))!.currentPage, 10);
    expect((await repo.getWereadLink(id))!.remoteProgress, 45);
  });
  test('预览远端进度只返回估算页，不修改本地页码', () async {
    final id = await linkedBook(
      totalPages: 100,
      currentPage: 10,
      wereadBookId: 'b1',
    );
    final service = buildService({
      'b1': {'progress': 45},
    });

    final preview = await service.previewBook(id);
    expect(preview.remoteProgress, 45);
    expect(preview.estimatedPage, 45);
    expect(preview.finished, isFalse);
    expect((await repo.getBook(id))!.currentPage, 10);
  });
}
