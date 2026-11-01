// 展示格式化工具。页面里不要再各写一套。

String formatWordCount(int? words) {
  if (words == null || words <= 0) return '';
  if (words >= 10000) {
    final value = words / 10000;
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} 万字';
  }
  return '$words 字';
}

String formatRating(double? rating, [int? count]) {
  if (rating == null || rating <= 0) return '';
  final score = rating.toStringAsFixed(1);
  if (count == null || count <= 0) return score;
  if (count >= 10000) {
    return '$score · ${(count / 10000).toStringAsFixed(1)} 万人评分';
  }
  return '$score · $count 人评分';
}

String formatPublishDate(String? value) {
  if (value == null || value.trim().isEmpty) return '';
  return value.trim();
}

String formatReadSeconds(int seconds) {
  if (seconds <= 0) return '0 分钟';
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分';
}

String formatRelativeDate(DateTime? date, {DateTime? now}) {
  if (date == null) return '尚未阅读';
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final target = DateTime(date.year, date.month, date.day);
  final days = today.difference(target).inDays;
  if (days <= 0) return '今天';
  if (days == 1) return '昨天';
  if (days < 7) return '$days 天前';
  if (days < 30) return '${days ~/ 7} 周前';
  if (days < 365) return '${days ~/ 30} 个月前';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
