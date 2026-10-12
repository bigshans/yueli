import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets/task_card.dart';

/// 为每本书分配一个稳定颜色，让日历里的书名更好区分。
const List<Color> _bookPalette = [
  Color(0xFF3F6BFF),
  Color(0xFF00A884),
  Color(0xFFE8873A),
  Color(0xFFB44BE0),
  Color(0xFFE05299),
  Color(0xFF00A5C4),
  Color(0xFF8A8F3D),
];

Color bookColor(int bookId) => _bookPalette[bookId % _bookPalette.length];

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final tasksAsync = ref.watch(tasksInRangeProvider((first, last)));

    return Scaffold(
      appBar: AppBar(title: const Text('日历')),
      body: Column(
        children: [
          _MonthHeader(month: _month, onShift: _shift),
          _WeekdayHeader(),
          Expanded(
            child: tasksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('出错了：$e')),
              data: (tasks) {
                final byDay = <String, List<TaskWithBook>>{};
                for (final t in tasks) {
                  byDay.putIfAbsent(formatDate(t.task.date), () => []).add(t);
                }
                return _MonthGrid(
                  month: _month,
                  byDay: byDay,
                  onTapDay: (day) =>
                      _showDay(day, byDay[formatDate(day)] ?? []),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDay(DateTime day, List<TaskWithBook> tasks) {
    // 按书分组
    final grouped = <int, List<TaskWithBook>>{};
    final books = <int, Book>{};
    for (final t in tasks) {
      grouped.putIfAbsent(t.book.id, () => []).add(t);
      books[t.book.id] = t.book;
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formatDateCn(day),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('这天没有排期'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in grouped.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: bookColor(entry.key),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              books[entry.key]?.title ?? '',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      for (final t in entry.value) TaskCard(item: t),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.onShift});
  final DateTime month;
  final void Function(int) onShift;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onShift(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${month.year} 年 ${month.month} 月',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          IconButton(
            onPressed: () => onShift(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final n in names)
            Expanded(child: Center(child: Text(n, style: style))),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.byDay,
    required this.onTapDay,
  });

  final DateTime month;
  final Map<String, List<TaskWithBook>> byDay;
  final void Function(DateTime) onTapDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday - 1; // 周一为首列
    final today0 = today();

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      cells.add(_DayCell(
        day: day,
        tasks: byDay[formatDate(day)] ?? const [],
        isToday: day == today0,
        onTap: () => onTapDay(day),
      ));
    }

    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      crossAxisCount: 7,
      childAspectRatio: 0.62,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.tasks,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final List<TaskWithBook> tasks;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allDone =
        tasks.isNotEmpty && tasks.every((t) => t.task.status == 'done');
    final hasSkipped =
        tasks.any((t) => t.task.status == 'skipped') && !allDone;

    // 当天的书（去重、保序）。
    final books = <int, Book>{};
    for (final t in tasks) {
      books[t.book.id] = t.book;
    }
    final bookList = books.values.toList();
    final shown = bookList.take(2).toList();
    final extra = bookList.length - shown.length;

    Color? tint;
    if (tasks.isNotEmpty) {
      tint = allDone
          ? scheme.primary
          : (hasSkipped ? scheme.tertiary : scheme.secondary);
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
          color: tint?.withValues(alpha: 0.10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                    color: isToday ? scheme.primary : scheme.onSurface,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                if (allDone)
                  Icon(Icons.check_circle, size: 11, color: scheme.primary),
              ],
            ),
            const SizedBox(height: 2),
            for (final b in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  b.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: bookColor(b.id),
                    decoration:
                        allDone ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
            if (extra > 0)
              Text(
                '+$extra',
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}
