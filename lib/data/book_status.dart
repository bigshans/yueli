/// 读物的阅读状态。
///
/// 只有「在读」的书会出现在今日任务和日历排期中。
abstract final class BookStatus {
  static const want = 'want';
  static const reading = 'reading';
  static const finished = 'finished';
  static const shelved = 'shelved';

  static const all = [want, reading, finished, shelved];

  static String label(String status) => switch (status) {
    want => '想读',
    finished => '已读',
    shelved => '搁置',
    _ => '在读',
  };

  static String normalize(String? status) =>
      status != null && all.contains(status) ? status : reading;

  /// 兼容旧备份：旧版本只有 shelved 布尔值，没有 status 字段。
  static String fromLegacy({
    String? status,
    bool shelved = false,
    int currentPage = 0,
    int totalPages = 0,
  }) {
    // 「已读」由进度自动判定，优先于任何手动状态。
    if (totalPages > 0 && currentPage >= totalPages) return finished;
    if (status != null && all.contains(status)) {
      return status == finished ? reading : status;
    }
    if (shelved) return BookStatus.shelved;
    return reading;
  }
}
