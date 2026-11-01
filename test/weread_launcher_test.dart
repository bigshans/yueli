import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/services/weread/weread_launcher.dart';

void main() {
  test('移动端优先使用 readerLink', () {
    expect(
      pickWereadOpenLink(
        readerLink: 'weread://reading?bId=1',
        deepLink: 'https://weread.qq.com/web/bookDetail/1',
        mobile: true,
      ),
      'weread://reading?bId=1',
    );
  });

  test('PC/Web 优先使用 http 链接', () {
    expect(
      pickWereadOpenLink(
        readerLink: 'weread://reading?bId=1',
        deepLink: 'https://weread.qq.com/web/bookDetail/1',
        mobile: false,
      ),
      'https://weread.qq.com/web/bookDetail/1',
    );
  });

  test('PC/Web 只有 App 链接时不构造网页地址', () {
    expect(
      pickWereadOpenLink(
        readerLink: 'weread://reading?bId=1',
        deepLink: null,
        mobile: false,
      ),
      isNull,
    );
  });
}
