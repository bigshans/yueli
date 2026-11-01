import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_management/services/weread/weread_client.dart';

void main() {
  test('请求体平铺参数并携带 Bearer 与 skill_version', () async {
    late http.Request captured;
    final client = WereadClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'errcode': 0, 'books': [], 'albums': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);

    await client.call(
      '/book/getprogress',
      apiKey: 'wrk-test',
      params: {'bookId': '43208843', 'mode': 'overall'},
    );

    expect(
      captured.url.toString(),
      'https://i.weread.qq.com/api/agent/gateway',
    );
    expect(captured.headers['Authorization'], 'Bearer wrk-test');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['api_name'], '/book/getprogress');
    expect(body['skill_version'], WereadClient.skillVersion);
    expect(body['bookId'], '43208843');
    expect(body['mode'], 'overall');
    expect(body.containsKey('params'), isFalse);
    expect(WereadClient.skillVersion, '1.0.5');
  });

  test('validateApiKey 通过 /shelf/sync 返回书架数量', () async {
    late Map<String, dynamic> body;
    final client = WereadClient(
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'books': [
              {'bookId': 'a'},
              {'bookId': 'b'},
            ],
            'albums': [
              {'albumInfo': {}},
            ],
            'mp': {'title': '文章收藏'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);

    final summary = await client.validateApiKey('wrk-test');

    expect(body['api_name'], '/shelf/sync');
    expect(summary.bookCount, 2);
    expect(summary.albumCount, 1);
    expect(summary.hasMp, isTrue);
    expect(summary.totalCount, 4);
  });

  test('业务 errcode 转为 WereadApiException', () async {
    final client = WereadClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'errcode': 1001, 'errmsg': '书不存在'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.close);

    expect(
      () => client.call('/book/info', apiKey: 'wrk-test'),
      throwsA(
        isA<WereadApiException>()
            .having((e) => e.code, 'code', 1001)
            .having((e) => e.message, 'message', '书不存在'),
      ),
    );
  });

  test('升级提示转为 WereadUpgradeException', () async {
    final client = WereadClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'upgrade_info': {'message': '请升级到 1.1.0'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.close);

    expect(
      () => client.call('/shelf/sync', apiKey: 'wrk-test'),
      throwsA(
        isA<WereadUpgradeException>().having(
          (e) => e.message,
          'message',
          '请升级到 1.1.0',
        ),
      ),
    );
  });

  test('HTTP 401 转为 WereadAuthException', () async {
    final client = WereadClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'errcode': 401, 'errmsg': '登录超时'}),
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(client.close);

    expect(
      () => client.call('/shelf/sync', apiKey: 'wrk-test'),
      throwsA(isA<WereadAuthException>()),
    );
  });

  test('无效 JSON 转为 WereadHttpException', () async {
    final client = WereadClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '<html>bad gateway</html>',
          502,
          headers: {'content-type': 'text/html'},
        ),
      ),
    );
    addTearDown(client.close);

    expect(
      () => client.call('/shelf/sync', apiKey: 'wrk-test'),
      throwsA(isA<WereadHttpException>()),
    );
  });

  test('中文或升级提示不会被当作 API Key 发送', () async {
    var requestCount = 0;
    final client = WereadClient(
      httpClient: MockClient((_) async {
        requestCount++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);

    await expectLater(
      () => client.call(
        '/shelf/sync',
        apiKey: '微信读书 Skill 有新版本，请立即从 upgrade_url 下载最新版 SKILL.md',
      ),
      throwsA(
        isA<WereadAuthException>().having(
          (e) => e.message,
          'message',
          contains('升级提示'),
        ),
      ),
    );
    expect(requestCount, 0);

    await expectLater(
      () => client.call('/shelf/sync', apiKey: 'wrk-测试'),
      throwsA(
        isA<WereadAuthException>().having(
          (e) => e.message,
          'message',
          contains('格式不正确'),
        ),
      ),
    );
    expect(requestCount, 0);
  });

  test('book/info 与 getprogress 解析为模型', () async {
    final client = WereadClient(
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['api_name'] == '/book/info') {
          return http.Response(
            jsonEncode({
              'bookId': '1',
              'title': '书',
              'author': '作者',
              'wordCount': 12345,
              'newRating': 87,
              'newRatingCount': 100,
              'publishTime': 1714521600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'book': {
              'progress': 45,
              'recordReadingTime': 3600,
              'updateTime': 1760000000,
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);

    final info = await client.fetchBookInfo('wrk-test', bookId: '1');
    expect(info.title, '书');
    expect(info.wordCount, 12345);
    expect(info.rating, 87);
    expect(info.publishDate, '2024-05-01');

    final progress = await client.fetchProgress('wrk-test', bookId: '1');
    expect(progress.progress, 45);
    expect(progress.recordReadingTime, 3600);
  });
}
