import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets/timer_banner.dart';

/// 一本书的阅读统计：今日、近 7 天趋势、全部历史（按月分组，懒加载）。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key, required this.bookId});
  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dailyStatsProvider(bookId));
    final book = ref.watch(bookProvider(bookId)).valueOrNull;
    final plan = ref.watch(planForBookProvider(bookId)).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(book == null ? '阅读统计' : '《${book.title}》统计'),
      ),
      bottomNavigationBar: const TimerBanner(),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (stats) {
          final now = dateOnly(DateTime.now());
          final todayStat = _find(stats, now);
          final targetMinutes = _targetMinutes(book, plan, settings);

          // 扁平化成条目，交给 ListView.builder 懒加载。
          final entries = <Object>[
            _TodayData(todayStat, targetMinutes),
            const _ChartMarker(),
            const _SectionTitleData('全部历史'),
          ];
          String? monthKey;
          for (final s in stats) {
            final k = '${s.date.year}-${s.date.month}';
            if (k != monthKey) {
              entries.add(_MonthData(DateTime(s.date.year, s.date.month)));
              monthKey = k;
            }
            entries.add(s);
          }
          if (stats.isEmpty) entries.add(const _EmptyData());

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              switch (e) {
                case _TodayData():
                  return _TodayCard(stat: e.stat, target: e.target);
                case _ChartMarker():
                  return _WeekChart(stats: stats, today: now);
                case _SectionTitleData():
                  return _SectionTitle(e.text);
                case _MonthData():
                  return _MonthHeader(month: e.month);
                case _EmptyData():
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('还没有阅读记录')),
                  );
                case DailyStat():
                  return _DayRow(stat: e);
                default:
                  return const SizedBox.shrink();
              }
            },
          );
        },
      ),
    );
  }

  int? _targetMinutes(Book? book, Plan? plan, AppSetting? settings) {
    if (plan == null) return null;
    if (plan.dailyPages != null && book != null && settings != null) {
      final pace = effectivePace(book, settings);
      return (plan.dailyPages! / pace * 60).round();
    }
    return plan.dailyMinutes;
  }

  static DailyStat? _find(List<DailyStat> stats, DateTime date) {
    for (final s in stats) {
      if (s.date == date) return s;
    }
    return null;
  }
}

// ---- 条目类型标记 ----

class _TodayData {
  const _TodayData(this.stat, this.target);
  final DailyStat? stat;
  final int? target;
}

class _ChartMarker {
  const _ChartMarker();
}

class _SectionTitleData {
  const _SectionTitleData(this.text);
  final String text;
}

class _MonthData {
  const _MonthData(this.month);
  final DateTime month;
}

class _EmptyData {
  const _EmptyData();
}

// ---- 组件 ----

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.stat, required this.target});
  final DailyStat? stat;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mins = stat?.minutes ?? 0;
    final progress = (target != null && target! > 0)
        ? (mins / target!).clamp(0.0, 1.0)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('今日',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMinutes(mins),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 12),
                if (stat != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${stat!.pages} 页 · ${stat!.sessions} 次',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: progress >= 1 ? scheme.tertiary : scheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                progress >= 1
                    ? '已达成今日目标（$target 分钟）'
                    : '今日目标 $target 分钟',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ] else if (stat == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '今天还没有阅读记录',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.stats, required this.today});
  final List<DailyStat> stats;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 最近 7 天，最旧在左。
    final days = [
      for (var i = 6; i >= 0; i--) addDays(today, -i),
    ];
    final byDate = {for (final s in stats) s.date: s};
    final values = [for (final d in days) byDate[d]?.minutes ?? 0];
    final maxV = max(1, values.fold<int>(0, max));
    const names = ['一', '二', '三', '四', '五', '六', '日'];

    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近 7 天（分钟）',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < days.length; i++)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (values[i] > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '${values[i]}',
                                style: TextStyle(
                                    fontSize: 10, color: scheme.onSurfaceVariant),
                              ),
                            ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 6 + 56 * (values[i] / maxV),
                            decoration: BoxDecoration(
                              color: days[i] == today
                                  ? scheme.primary
                                  : scheme.primary.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            names[days[i].weekday - 1],
                            style: TextStyle(
                              fontSize: 10,
                              color: days[i] == today
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: days[i] == today
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Row(
        children: [
          Text(
            '${month.year} 年 ${month.month} 月',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: scheme.outlineVariant)),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.stat});
  final DailyStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pace = stat.pace;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stat.date.month}/${stat.date.day} '
                  '${const ['一', '二', '三', '四', '五', '六', '日'][stat.date.weekday - 1]}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${formatMinutes(stat.minutes)} · ${stat.pages} 页'
                  '${pace != null ? ' · ${pace.toStringAsFixed(0)} 页/小时' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(
            '${stat.sessions} 次',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
