import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/date_x.dart';
import '../../data/database.dart';

enum ReadingHeatmapMetric { time, pages }

/// GitHub 风格阅读热力图：最近 [weeks] 周，每格一天，颜色深浅表示阅读量。
class ReadingHeatmap extends StatelessWidget {
  const ReadingHeatmap({
    super.key,
    required this.sessions,
    required this.metric,
    this.weeks = 26,
    this.today,
  });

  final List<ReadingSession> sessions;
  final ReadingHeatmapMetric metric;
  final int weeks;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = dateOnly(today ?? DateTime.now());
    // 从 weeks 周前的周一开始，保证每列都是完整的周一至周日。
    final start = addDays(now, -((weeks - 1) * 7 + (now.weekday - 1)));

    final dayStats = <DateTime, _DayValue>{};
    for (final s in sessions) {
      final d = dateOnly(s.startedAt);
      if (d.isBefore(start) || d.isAfter(now)) continue;
      final value = dayStats.putIfAbsent(d, _DayValue.new);
      value.seconds += s.durationSeconds;
      value.pages += s.pagesRead ?? 0;
    }
    final maxValue = dayStats.values.fold<int>(
      0,
      (m, v) =>
          max(m, metric == ReadingHeatmapMetric.time ? v.seconds : v.pages),
    );

    const cell = 11.0;
    const gap = 3.0;
    final weekWidth = cell + gap;
    const names = ['一', '二', '三', '四', '五', '六', '日'];

    final monthLabels = <int, String>{};
    DateTime? lastMonth;
    for (var w = 0; w < weeks; w++) {
      final weekStart = addDays(start, w * 7);
      if (lastMonth == null ||
          weekStart.year != lastMonth.year ||
          weekStart.month != lastMonth.month) {
        monthLabels[w] = weekStart.month == 1
            ? '${weekStart.year}'
            : '${weekStart.month}月';
        lastMonth = DateTime(weekStart.year, weekStart.month);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                for (var weekday = 0; weekday < 7; weekday++)
                  SizedBox(
                    width: 18,
                    height: weekWidth,
                    child: Text(
                      weekday.isEven ? names[weekday] : '',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 16,
                      child: Row(
                        children: [
                          for (var w = 0; w < weeks; w++)
                            SizedBox(
                              width: weekWidth,
                              child: monthLabels[w] == null
                                  ? null
                                  : Text(
                                      monthLabels[w]!,
                                      maxLines: 1,
                                      softWrap: false,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontSize: 9,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var w = 0; w < weeks; w++)
                          Column(
                            children: [
                              for (var weekday = 0; weekday < 7; weekday++)
                                _cell(
                                  context,
                                  addDays(start, w * 7 + weekday),
                                  now,
                                  dayStats,
                                  maxValue,
                                  cell,
                                  gap,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 18),
            const Spacer(),
            Text(
              '少',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            for (var level = 0; level <= 4; level++) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _levelColor(context, level),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 2),
            ],
            Text(
              '多',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime date,
    DateTime now,
    Map<DateTime, _DayValue> dayStats,
    int maxValue,
    double cell,
    double gap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (date.isAfter(now)) {
      return SizedBox(width: cell + gap, height: cell + gap);
    }
    final stat = dayStats[date];
    final value = stat == null
        ? 0
        : (metric == ReadingHeatmapMetric.time ? stat.seconds : stat.pages);
    final level = value <= 0
        ? 0
        : max(1, min(4, (value / max(1, maxValue) * 4).ceil()));
    final minutes = stat == null ? 0 : (stat.seconds / 60).round();
    final pages = stat?.pages ?? 0;

    return Padding(
      padding: EdgeInsets.only(right: gap, bottom: gap),
      child: Tooltip(
        message: date.isAfter(now)
            ? ''
            : '${formatDate(date)}\n$minutes 分钟 · $pages 页',
        child: Container(
          width: cell,
          height: cell,
          decoration: BoxDecoration(
            color: _levelColor(context, level),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Color _levelColor(BuildContext context, int level) {
    final scheme = Theme.of(context).colorScheme;
    if (level <= 0) return scheme.surfaceContainerHighest;
    const alpha = [0.0, 0.25, 0.45, 0.68, 1.0];
    return scheme.primary.withValues(alpha: alpha[level]);
  }
}

class _DayValue {
  int seconds = 0;
  int pages = 0;
}

/// 热力图卡片，统一统计页的标题、说明和留白。
class ReadingHeatmapCard extends StatelessWidget {
  const ReadingHeatmapCard({
    super.key,
    required this.sessions,
    required this.metric,
    this.weeks = 26,
    this.today,
  });

  final List<ReadingSession> sessions;
  final ReadingHeatmapMetric metric;
  final int weeks;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '阅读热力图',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  metric == ReadingHeatmapMetric.time ? '按时长' : '按页数',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ReadingHeatmap(
              sessions: sessions,
              metric: metric,
              weeks: weeks,
              today: today,
            ),
          ],
        ),
      ),
    );
  }
}
