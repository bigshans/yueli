import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/core/format_x.dart';

void main() {
  test('字数格式化', () {
    expect(formatWordCount(null), '');
    expect(formatWordCount(0), '');
    expect(formatWordCount(999), '999 字');
    expect(formatWordCount(10000), '1.0 万字');
    expect(formatWordCount(123456), '12.3 万字');
  });

  test('评分格式化', () {
    expect(formatRating(null), '');
    expect(formatRating(8.7), '8.7');
    expect(formatRating(8.7, 0), '8.7');
    expect(formatRating(8.7, 1234), '8.7 · 1234 人评分');
    expect(formatRating(8.7, 12345), '8.7 · 1.2 万人评分');
  });

  test('阅读时长格式化', () {
    expect(formatReadSeconds(0), '0 分钟');
    expect(formatReadSeconds(45), '45 秒');
    expect(formatReadSeconds(3 * 60), '3 分钟');
    expect(formatReadSeconds(2 * 3600 + 40 * 60), '2 小时 40 分');
  });

  test('相对日期格式化', () {
    final now = DateTime(2026, 5, 20);
    expect(formatRelativeDate(null, now: now), '尚未阅读');
    expect(formatRelativeDate(DateTime(2026, 5, 20), now: now), '今天');
    expect(formatRelativeDate(DateTime(2026, 5, 19), now: now), '昨天');
    expect(formatRelativeDate(DateTime(2026, 5, 17), now: now), '3 天前');
    expect(formatRelativeDate(DateTime(2026, 5, 1), now: now), '2 周前');
    expect(formatRelativeDate(DateTime(2025, 5, 1), now: now), '2025-05-01');
  });
}
