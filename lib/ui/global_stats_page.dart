import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'stats_page.dart';
import 'widgets/timer_banner.dart';

enum _Range { d7, d30, d90, all }

enum _View { day, book, detail }

/// 全局统计：跨所有书的汇总、今日、趋势、历史（按天 / 按书 / 明细）。
class GlobalStatsPage extends ConsumerStatefulWidget {
  const GlobalStatsPage({super.key});

  @override
  ConsumerState<GlobalStatsPage> createState() => _GlobalStatsPageState();
}

class _GlobalStatsPageState extends ConsumerState<GlobalStatsPage> {
  _Range _range = _Range.all;
  _View _view = _View.day;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(allSessionsProvider);
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      bottomNavigationBar: const TimerBanner(),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (all) {
          final now = today();
          final booksById = {for (final b in books) b.id: b};

          // 汇总（全部时间）。
          var totalSeconds = 0;
          var totalPages = 0;
          for (final s in all) {
            totalSeconds += s.durationSeconds;
            totalPages += s.pagesRead ?? 0;
          }
          final finished =
              books.where((b) => b.totalPages > 0 && b.currentPage >= b.totalPages).length;

          // 今日（跨所有书）。
          final todaySessions =
              all.where((s) => dateOnly(s.startedAt) == now).toList();
          final todayStat = _aggregate(now, todaySessions);

          final filtered = _applyRange(all, now, _range);

          final entries = <Object>[
            _SummaryData(
              totalSeconds: totalSeconds,
              totalPages: totalPages,
              totalSessions: all.length,
              finishedBooks: finished,
              bookCount: books.length,
            ),
            _TodayData(todayStat),
            const _ChartMarker(),
            const _FilterMarker(),
          ];

          if (filtered.isEmpty) {
            entries.add(const _EmptyData());
          } else {
            switch (_view) {
              case _View.day:
                entries.add(const _SectionTitleData('历史（按天）'));
                final byDay = <DateTime, List<ReadingSession>>{};
                for (final s in filtered) {
                  byDay.putIfAbsent(dateOnly(s.startedAt), () => []).add(s);
                }
                final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
                String? monthKey;
                for (final d in days) {
                  final k = '${d.year}-${d.month}';
                  if (k != monthKey) {
                    entries.add(_MonthData(DateTime(d.year, d.month)));
                    monthKey = k;
                  }
                  entries.add(_DayData(d, byDay[d]!));
                }
              case _View.book:
                entries.add(const _SectionTitleData('按书统计'));
                final aggs = <int, _BookAgg>{};
                for (final s in filtered) {
                  final a = aggs.putIfAbsent(s.bookId, () => _BookAgg(s.bookId));
                  a.seconds += s.durationSeconds;
                  a.pages += s.pagesRead ?? 0;
                  a.sessions += 1;
                }
                final list = aggs.values
                    .where((a) => booksById.containsKey(a.bookId))
                    .toList()
                  ..sort((a, b) => b.seconds.compareTo(a.seconds));
                entries.addAll(list);
              case _View.detail:
                entries.add(const _SectionTitleData('全部明细'));
                entries.addAll(filtered);
            }
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              switch (e) {
                case _SummaryData():
                  return _SummaryCard(data: e);
                case _TodayData():
                  return _TodayCard(stat: e.stat);
                case _ChartMarker():
                  return _WeekChart(all: all, today: now);
                case _FilterMarker():
                  return _FilterBar(
                    range: _range,
                    view: _view,
                    onRange: (r) => setState(() => _range = r),
                    onView: (v) => setState(() => _view = v),
                  );
                case _SectionTitleData():
                  return _SectionTitle(e.text);
                case _MonthData():
                  return _MonthHeader(month: e.month);
                case _DayData():
                  return _DayTile(
                    date: e.date,
                    sessions: e.sessions,
                    booksById: booksById,
                  );
                case _BookAgg():
                  final book = booksById[e.bookId];
                  if (book == null) return const SizedBox.shrink();
                  return _BookRow(agg: e, book: book);
                case ReadingSession():
                  return _SessionLine(
                    session: e,
                    bookTitle: booksById[e.bookId]?.title ?? '（已删除）',
                    showDate: true,
                  );
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
    _Range range,
  ) {
    if (range == _Range.all) return sessions;
    final n = switch (range) {
      _Range.d7 => 7,
      _Range.d30 => 30,
      _Range.d90 => 90,
      _Range.all => 0,
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
}

// ---- 条目类型 ----

class _SummaryData {
  const _SummaryData({
    required this.totalSeconds,
    required this.totalPages,
    required this.totalSessions,
    required this.finishedBooks,
    required this.bookCount,
  });
  final int totalSeconds;
  final int totalPages;
  final int totalSessions;
  final int finishedBooks;
  final int bookCount;
}

class _TodayData {
  const _TodayData(this.stat);
  final DailyStat stat;
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

class _BookAgg {
  _BookAgg(this.bookId);
  final int bookId;
  int seconds = 0;
  int pages = 0;
  int sessions = 0;
  int get minutes => (seconds / 60).round();
}

class _EmptyData {
  const _EmptyData();
}

// ---- 组件 ----

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});
  final _SummaryData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('总览',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Row(
              children: [
                _stat(context, formatMinutes((data.totalSeconds / 60).round()),
                    '累计阅读'),
                _stat(context, '${data.totalPages}', '累计页数'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _stat(context, '${data.totalSessions}', '计时次数'),
                _stat(context, '${data.finishedBooks}/${data.bookCount}', '已读完'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.stat});
  final DailyStat stat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.today, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('今日',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(
                    stat.sessions == 0
                        ? '还没有阅读'
                        : '${stat.pages} 页 · ${formatMinutes(stat.minutes)} · ${stat.sessions} 次',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
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

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.range,
    required this.view,
    required this.onRange,
    required this.onView,
  });

  final _Range range;
  final _View view;
  final ValueChanged<_Range> onRange;
  final ValueChanged<_View> onView;

  static const _rangeLabels = {
    _Range.d7: '近 7 天',
    _Range.d30: '近 30 天',
    _Range.d90: '近 90 天',
    _Range.all: '全部',
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
            for (final r in _Range.values)
              ChoiceChip(
                label: Text(_rangeLabels[r]!),
                selected: range == r,
                onSelected: (_) => onRange(r),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<_View>(
          segments: const [
            ButtonSegment(
              value: _View.day,
              icon: Icon(Icons.calendar_view_day_outlined, size: 18),
              label: Text('按天'),
            ),
            ButtonSegment(
              value: _View.book,
              icon: Icon(Icons.menu_book_outlined, size: 18),
              label: Text('按书'),
            ),
            ButtonSegment(
              value: _View.detail,
              icon: Icon(Icons.list_alt, size: 18),
              label: Text('明细'),
            ),
          ],
          selected: {view},
          onSelectionChanged: (s) => onView(s.first),
        ),
      ],
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
    final secondsByDay = <DateTime, int>{};
    for (final s in all) {
      final d = dateOnly(s.startedAt);
      secondsByDay[d] = (secondsByDay[d] ?? 0) + s.durationSeconds;
    }
    final values = [
      for (final d in days) ((secondsByDay[d] ?? 0) / 60).round(),
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

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.date,
    required this.sessions,
    required this.booksById,
  });
  final DateTime date;
  final List<ReadingSession> sessions;
  final Map<int, Book> booksById;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var seconds = 0;
    var pages = 0;
    final bookIds = <int>{};
    for (final s in sessions) {
      seconds += s.durationSeconds;
      pages += s.pagesRead ?? 0;
      bookIds.add(s.bookId);
    }

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
          '${sessions.length} 次 · ${bookIds.length} 本',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final s in sessions)
            _SessionLine(
              session: s,
              bookTitle: booksById[s.bookId]?.title ?? '（已删除）',
              showDate: false,
            ),
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.agg, required this.book});
  final _BookAgg agg;
  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pace =
        (agg.pages > 0 && agg.seconds > 0) ? agg.pages / (agg.seconds / 3600) : null;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StatsPage(bookId: book.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatMinutes(agg.minutes)} · ${agg.pages} 页 · ${agg.sessions} 次'
                      '${pace != null ? ' · ${pace.toStringAsFixed(0)} 页/小时' : ''}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionLine extends StatelessWidget {
  const _SessionLine({
    required this.session,
    required this.bookTitle,
    required this.showDate,
  });
  final ReadingSession session;
  final String bookTitle;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = session;
    final pages = s.pagesRead;
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        bookTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${showDate ? '${start.month}/${start.day} ' : ''}'
                      '${hm(start)}–${hm(end)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Text(
                  '${formatDuration(s.durationSeconds)}'
                  '${pages != null ? ' · $pages 页' : ''}',
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
