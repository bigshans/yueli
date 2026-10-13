import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets/timer_banner.dart';

enum _RangeOption { d7, d30, d90, all }

/// 一本书的阅读统计：今日、近 7 天趋势、可筛选的历史（按天 / 明细）。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key, required this.bookId});
  final int bookId;

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  _RangeOption _range = _RangeOption.all;
  bool _detail = false;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider(widget.bookId));
    final book = ref.watch(bookProvider(widget.bookId)).valueOrNull;
    final plan = ref.watch(planForBookProvider(widget.bookId)).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final todayTask =
        ref.watch(taskOnDateProvider((widget.bookId, today()))).valueOrNull;

    final targetPages = todayTask != null
        ? todayTask.endPage - todayTask.startPage + 1
        : plan?.dailyPages;
    final targetMinutes = _targetMinutes(book, plan, settings);

    return Scaffold(
      appBar: AppBar(
        title: Text(book == null ? '阅读统计' : '《${book.title}》统计'),
      ),
      bottomNavigationBar: const TimerBanner(),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (all) {
          final now = today();
          // 今日数据不受筛选影响。
          final todaySessions =
              all.where((s) => dateOnly(s.startedAt) == now).toList();
          final todayStat = _aggregate(now, todaySessions);

          final filtered = _applyRange(all, now, _range);
          final byDay = <DateTime, List<ReadingSession>>{};
          for (final s in filtered) {
            byDay.putIfAbsent(dateOnly(s.startedAt), () => []).add(s);
          }
          final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

          final entries = <Object>[
            _TodayData(todayStat, targetPages, targetMinutes),
            const _ChartMarker(),
            const _FilterMarker(),
            _SectionTitleData(_detail ? '全部明细' : '历史'),
          ];
          if (filtered.isEmpty) {
            entries.add(const _EmptyData());
          } else if (_detail) {
            entries.addAll(filtered);
          } else {
            String? monthKey;
            for (final d in days) {
              final k = '${d.year}-${d.month}';
              if (k != monthKey) {
                entries.add(_MonthData(DateTime(d.year, d.month)));
                monthKey = k;
              }
              entries.add(_DayData(d, byDay[d]!));
            }
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              switch (e) {
                case _TodayData():
                  return _TodayCard(
                    stat: e.stat,
                    targetPages: e.targetPages,
                    targetMinutes: e.targetMinutes,
                  );
                case _ChartMarker():
                  return _WeekChart(all: all, today: now);
                case _FilterMarker():
                  return _FilterBar(
                    range: _range,
                    detail: _detail,
                    onRange: (r) => setState(() => _range = r),
                    onDetail: (d) => setState(() => _detail = d),
                  );
                case _SectionTitleData():
                  return _SectionTitle(e.text);
                case _MonthData():
                  return _MonthHeader(month: e.month);
                case _DayData():
                  return _DayTile(date: e.date, sessions: e.sessions);
                case ReadingSession():
                  return _SessionRow(session: e, showDate: true);
                case _EmptyData():
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        all.isEmpty ? '还没有阅读记录' : '这个时间范围内没有记录',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  );
                default:
                  return const SizedBox.shrink();
              }
            },
          );
        },
      ),
    );
  }

  List<ReadingSession> _applyRange(
    List<ReadingSession> sessions,
    DateTime now,
    _RangeOption range,
  ) {
    if (range == _RangeOption.all) return sessions;
    final n = switch (range) {
      _RangeOption.d7 => 7,
      _RangeOption.d30 => 30,
      _RangeOption.d90 => 90,
      _RangeOption.all => 0,
    };
    final cutoff = addDays(now, -(n - 1));
    return sessions
        .where((s) => !dateOnly(s.startedAt).isBefore(cutoff))
        .toList();
  }

  DailyStat _aggregate(DateTime date, List<ReadingSession> sessions) {
    var seconds = 0;
    var pages = 0;
    for (final s in sessions) {
      seconds += s.durationSeconds;
      pages += s.pagesRead ?? 0;
    }
    return DailyStat(
      date: date,
      seconds: seconds,
      pages: pages,
      sessions: sessions.length,
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
}

// ---- 条目类型标记 ----

class _TodayData {
  const _TodayData(this.stat, this.targetPages, this.targetMinutes);
  final DailyStat stat;
  final int? targetPages;
  final int? targetMinutes;
}

class _ChartMarker {
  const _ChartMarker();
}

class _FilterMarker {
  const _FilterMarker();
}

class _SectionTitleData {
  const _SectionTitleData(this.text);
  final String text;
}

class _MonthData {
  const _MonthData(this.month);
  final DateTime month;
}

class _DayData {
  const _DayData(this.date, this.sessions);
  final DateTime date;
  final List<ReadingSession> sessions;
}

class _EmptyData {
  const _EmptyData();
}

// ---- 组件 ----

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.range,
    required this.detail,
    required this.onRange,
    required this.onDetail,
  });

  final _RangeOption range;
  final bool detail;
  final ValueChanged<_RangeOption> onRange;
  final ValueChanged<bool> onDetail;

  static const _labels = {
    _RangeOption.d7: '近 7 天',
    _RangeOption.d30: '近 30 天',
    _RangeOption.d90: '近 90 天',
    _RangeOption.all: '全部',
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final r in _RangeOption.values)
              ChoiceChip(
                label: Text(_labels[r]!),
                selected: range == r,
                onSelected: (_) => onRange(r),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.calendar_view_day_outlined, size: 18),
              label: Text('按天'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.list_alt, size: 18),
              label: Text('明细'),
            ),
          ],
          selected: {detail},
          onSelectionChanged: (s) => onDetail(s.first),
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.stat,
    this.targetPages,
    this.targetMinutes,
  });
  final DailyStat stat;
  final int? targetPages;
  final int? targetMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pages = stat.pages;
    final target = targetPages;
    final progress = (target != null && target > 0)
        ? (pages / target).clamp(0.0, 1.0)
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
                  '$pages 页',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (target != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 6),
                    child: Text(
                      '/ $target 页',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '用时 ${formatMinutes(stat.minutes)} · ${stat.sessions} 次',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
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
                    ? (pages > target!
                        ? '已达成今日目标（$target 页，超额 ${pages - target} 页）'
                        : '已达成今日目标（$target 页）')
                    : '今日目标 $target 页'
                        '${targetMinutes != null ? '（约 ${formatMinutes(targetMinutes!)}）' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ] else if (stat.sessions == 0)
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
  const _WeekChart({required this.all, required this.today});
  final List<ReadingSession> all;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = [for (var i = 6; i >= 0; i--) addDays(today, -i)];
    final minutesByDay = <DateTime, int>{};
    for (final s in all) {
      final d = dateOnly(s.startedAt);
      minutesByDay[d] = (minutesByDay[d] ?? 0) + s.durationSeconds;
    }
    final values = [
      for (final d in days) ((minutesByDay[d] ?? 0) / 60).round(),
    ];
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
                                    fontSize: 10,
                                    color: scheme.onSurfaceVariant),
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

/// 按天一行，可展开查看当天的单次记录。
class _DayTile extends StatelessWidget {
  const _DayTile({required this.date, required this.sessions});
  final DateTime date;
  final List<ReadingSession> sessions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var seconds = 0;
    var pages = 0;
    for (final s in sessions) {
      seconds += s.durationSeconds;
      pages += s.pagesRead ?? 0;
    }
    final pace =
        (pages > 0 && seconds > 0) ? pages / (seconds / 3600) : null;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.only(left: 28, right: 4, bottom: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          '${date.month}/${date.day} '
          '${const ['一', '二', '三', '四', '五', '六', '日'][date.weekday - 1]}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          '${formatMinutes((seconds / 60).round())} · $pages 页 · '
          '${sessions.length} 次'
          '${pace != null ? ' · ${pace.toStringAsFixed(0)} 页/小时' : ''}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final s in sessions)
            _SessionRow(session: s, showDate: false),
        ],
      ),
    );
  }
}

/// 单次记录：起止时间、时长、页数、速度。
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.showDate});
  final ReadingSession session;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = session;
    final pages = s.pagesRead;
    final pace = (pages != null && pages > 0 && s.durationSeconds > 0)
        ? pages / (s.durationSeconds / 3600)
        : null;
    final start = s.startedAt;
    final end = s.endedAt;
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 15, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${showDate ? '${start.month}/${start.day} ' : ''}'
                  '${hm(start)}–${hm(end)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${formatDuration(s.durationSeconds)}'
                  '${pages != null ? ' · $pages 页' : ''}'
                  '${pace != null ? ' · ${pace.toStringAsFixed(0)} 页/小时' : ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
