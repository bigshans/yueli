import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/services/weread/weread_launcher.dart';

void main() {
  test('移动端使用 App 深链，即使接口返回的是网页链接', () {
    expect(
      pickWereadOpenLink(
        readerLink: 'https://weread.qq.com/web/reader/abc',
        deepLink: 'https://weread.qq.com/web/bookDetail/1',
        bookId: '1',
        mobile: true,
      ),
      'weread://reading?bId=1',
    );
  });

  test('移动端没有 bookId 时才回退到接口链接', () {
    expect(
      pickWereadOpenLink(readerLink: 'weread://reading?bId=1', mobile: true),
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

  test('PC/Web 只有 App 链接时按 bookId 生成网页地址', () {
    expect(
      pickWereadOpenLink(
        readerLink: 'weread://reading?bId=43208843',
        deepLink: null,
        bookId: '43208843',
        mobile: false,
      ),
      'https://weread.qq.com/web/reader/c9c321c07293508bc9c79df',
    );
  });

  test('接口没有链接时，移动端生成 App 深链', () {
    expect(
      pickWereadOpenLink(bookId: '43208843', mobile: true),
      'weread://reading?bId=43208843',
    );
  });

  test('接口没有链接时，PC 端生成网页阅读地址', () {
    expect(
      pickWereadOpenLink(bookId: '43208843', mobile: false),
      'https://weread.qq.com/web/reader/c9c321c07293508bc9c79df',
    );
  });

  test('微信读书 bookHash 与官方规则一致', () {
    expect(wereadBookHash('43208843'), 'c9c321c07293508bc9c79df');
    expect(wereadBookHash('2'), 'c81322c012c81e728d9d180');
    expect(wereadBookHash('119'), '07e323f027707e1cd7dc674');
  });
}
