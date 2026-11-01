import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_management/data/book_status.dart';
import 'package:reader_management/data/database.dart';
import 'package:reader_management/data/repository.dart';
import 'package:reader_management/services/weread/weread_client.dart';
import 'package:reader_management/services/weread/weread_import_service.dart';

void main() {
  late AppDatabase db;
  late ReadingRepository repo;
  late WereadImportService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReadingRepository(db);
    final client = WereadClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final api = body['api_name'];
        if (api == '/shelf/sync') {
          return _json({
            'books': [
              {
                'bookId': 'wr-book-1',
                'title': '微信读书示例',
                'author': '示例作者',
                'cover': 'https://example.com/cover.jpg',
                'category': '计算机/编程',
                'readUpdateTime': 1760000000,
                'finishReading': 0,
                'readerLink': 'weread://reader/1',
              },
            ],
            'albums': [],
            'mp': null,
          });
        }
        if (api == '/book/info') {
          return _json({
            'bookId': 'wr-book-1',
            'title': '微信读书示例',
            'author': '示例作者',
            'translator': '示例译者',
            'cover': 'https://example.com/cover.jpg',
            'intro': '这是一本示例书。',
            'category': '计算机/编程',
            'publisher': '示例出版社',
            'publishTime': 1714521600,
            'isbn': '9780000000000',
            'wordCount': 12345,
            'newRating': 87,
            'newRatingCount': 1234,
            'readerLink': 'weread://reader/1',
          });
        }
        if (api == '/book/getprogress') {
          return _json({
            'bookId': 'wr-book-1',
            'book': {
              'progress': 45,
              'recordReadingTime': 3600,
              'updateTime': 1760000000,
            },
          });
        }
        return _json({'errcode': 404, 'errmsg': 'unknown api'});
      }),
    );
    service = WereadImportService(
      client: client,
      repository: repo,
      apiKeyLoader: () async => 'wrk-test',
    );
    addTearDown(db.close);
  });

  test('拉取书架并导入一本书，元数据、进度和关联都正确', () async {
    final shelf = await service.fetchShelf();
    expect(shelf, hasLength(1));

    final preview = await service.prepare(shelf.single);
    expect(preview.totalPages, 13);
    expect(preview.currentPage, 6);
    expect(preview.status, BookStatus.reading);
    expect(preview.progress.progress, 45);

    final id = await service.importPreview(preview);
    final book = await repo.getBook(id);
    expect(book, isNotNull);
    expect(book!.title, '微信读书示例');
    expect(book.author, '示例作者');
    expect(book.translator, '示例译者');
    expect(book.publisher, '示例出版社');
    expect(book.publishDate, '2024-05-01');
    expect(book.isbn, '9780000000000');
    expect(book.wordCount, 12345);
    expect(book.rating, 8.7);
    expect(book.ratingCount, 1234);
    expect(book.totalPages, 13);
    expect(book.currentPage, 6);
    expect(book.status, BookStatus.reading);
    expect(book.metadataSource, 'weread');
    expect(parseTags(book.tags), containsAll(['计算机', '编程', '微信读书']));

    final link = await repo.getWereadLink(id);
    expect(link, isNotNull);
    expect(link!.wereadBookId, 'wr-book-1');
    expect(link.remoteProgress, 45);
    expect(link.remoteReadSeconds, 3600);
    expect(link.readerLink, 'weread://reader/1');
  });

  test('进度 100 且有 finishTime 时导入为已读', () async {
    final shelf = await service.fetchShelf();
    final clientPreview = shelf.single;
    // 用新 service 模拟已完成进度。
    final completedService = WereadImportService(
      client: WereadClient(
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final api = body['api_name'];
          if (api == '/book/info') {
            return _json({
              'bookId': 'wr-book-1',
              'title': '已读完示例',
              'wordCount': 5000,
              'newRating': 90,
            });
          }
          if (api == '/book/getprogress') {
            return _json({
              'book': {
                'progress': 100,
                'recordReadingTime': 7200,
                'finishTime': 1760000000,
                'updateTime': 1760000000,
              },
            });
          }
          return _json({'books': []});
        }),
      ),
      repository: repo,
      apiKeyLoader: () async => 'wrk-test',
    );
    final preview = await completedService.prepare(clientPreview);
    expect(preview.finished, isTrue);
    expect(preview.currentPage, 5);
    expect(preview.status, BookStatus.finished);
    final id = await completedService.importPreview(preview);
    final book = await repo.getBook(id);
    expect(book!.status, BookStatus.finished);
    expect(book.currentPage, 5);
  });

  test('分类转标签会拆分路径并去重', () {
    expect(
      buildWereadTags('计算机/编程/程序设计', addWereadTag: true),
      containsAll(['计算机', '编程', '程序设计', '微信读书']),
    );
    expect(buildWereadTags(null, addWereadTag: false), isEmpty);
  });
  test('已有本地书籍绑定微信读书时不会按百分比修改页码', () async {
    final localId = await repo.createBook(
      title: '我手动录入的书',
      totalPages: 100,
      currentPage: 10,
      status: BookStatus.reading,
    );
    final shelf = await service.fetchShelf();
    await service.bindExistingBook(bookId: localId, shelfBook: shelf.single);

    final book = await repo.getBook(localId);
    expect(book, isNotNull);
    expect(book!.title, '我手动录入的书');
    expect(book.author, '示例作者');
    expect(book.translator, '示例译者');
    expect(book.publisher, '示例出版社');
    expect(book.coverUrl, 'https://example.com/cover.jpg');
    expect(book.rating, 8.7);
    expect(book.wordCount, 12345);
    expect(book.currentPage, 10); // 绑定不按百分比改本地页码
    expect(book.status, BookStatus.reading);

    final link = await repo.getWereadLink(localId);
    expect(link?.wereadBookId, 'wr-book-1');
    expect(link?.remoteProgress, 45);
  });

  test('同一本微信读书书不能绑定到两本本地书', () async {
    final first = await repo.createBook(title: '第一本', totalPages: 100);
    final second = await repo.createBook(title: '第二本', totalPages: 100);
    final shelf = await service.fetchShelf();
    await service.bindExistingBook(bookId: first, shelfBook: shelf.single);

    await expectLater(
      () => service.bindExistingBook(bookId: second, shelfBook: shelf.single),
      throwsA(isA<WereadImportException>()),
    );
  });
  test('自动绑定唯一同名同作者的本地书籍', () async {
    final localId = await repo.createBook(
      title: '微信读书示例',
      author: '示例作者',
      totalPages: 100,
    );
    final result = await service.autoBindExistingBooks();
    expect(result.bound, 1);
    expect(result.ambiguous, 0);
    expect(result.failed, 0);
    final link = await repo.getWereadLink(localId);
    expect(link?.wereadBookId, 'wr-book-1');
  });

  test('自动绑定遇到多本同名本地书时只绑定一本并跳过其余', () async {
    await repo.createBook(title: '微信读书示例', author: '示例作者', totalPages: 100);
    await repo.createBook(title: '微信读书示例', author: '示例作者', totalPages: 100);
    final result = await service.autoBindExistingBooks();
    expect(result.bound, 1);
    expect(result.ambiguous, 1);
  });

  test('书名和作者归一化', () {
    expect(normalizeWereadTitle('《微信读书示例》'), '微信读书示例');
    expect(normalizeWereadTitle('微信 读书 示例'), '微信读书示例');
    expect(normalizeWereadAuthor('[美] 示例作者'), '示例作者');
  });
}

http.Response _json(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);
