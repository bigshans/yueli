import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets/task_card.dart';
import 'widgets/timer_banner.dart';

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
    final sessionsAsync = ref.watch(sessionsInRangeProvider((first, last)));
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final booksById = {for (final b in books) b.id: b};

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
                final sessions =
                    sessionsAsync.valueOrNull ?? const <ReadingSession>[];
                final tasksByDay = <String, List<TaskWithBook>>{};
                for (final t in tasks) {
                  tasksByDay
                      .putIfAbsent(formatDate(t.task.date), () => [])
                      .add(t);
                }
                final sessionsByDay = <String, List<ReadingSession>>{};
                for (final s in sessions) {
                  sessionsByDay
                      .putIfAbsent(formatDate(s.startedAt), () => [])
                      .add(s);
                }
                return _MonthGrid(
                  month: _month,
                  tasksByDay: tasksByDay,
                  sessionsByDay: sessionsByDay,
                  booksById: booksById,
                  onTapDay: (day) => _showDay(
                    day,
                    tasksByDay[formatDate(day)] ?? const [],
                    sessionsByDay[formatDate(day)] ?? const [],
                    booksById,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDay(
    DateTime day,
    List<TaskWithBook> tasks,
    List<ReadingSession> sessions,
    Map<int, Book> booksById,
  ) {
    final taskGroups = <int, List<TaskWithBook>>{};
    final taskBooks = <int, Book>{};
    for (final t in tasks) {
      taskGroups.putIfAbsent(t.book.id, () => []).add(t);
      taskBooks[t.book.id] = t.book;
    }
    final sessionGroups = <int, List<ReadingSession>>{};
    for (final s in sessions) {
      sessionGroups.putIfAbsent(s.bookId, () => []).add(s);
    }
    final allBooks = <int, Book>{...booksById, ...taskBooks};

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) => SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                formatDateCn(day),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${tasks.length} 项排期 · ${sessions.length} 次阅读记录',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (tasks.isEmpty && sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('这天没有排期或阅读记录')),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (tasks.isNotEmpty) ...[
                        const _SheetSectionTitle('排期'),
                        for (final entry in taskGroups.entries) ...[
                          _BookGroupHeader(
                            bookId: entry.key,
                            title: taskBooks[entry.key]?.title ?? '（已删除）',
                          ),
                          for (final t in entry.value) TaskCard(item: t),
                        ],
                      ],
                      if (sessions.isNotEmpty) ...[
                        const _SheetSectionTitle('阅读记录'),
                        for (final entry in sessionGroups.entries) ...[
                          _BookGroupHeader(
                            bookId: entry.key,
                            title: allBooks[entry.key]?.title ?? '（已删除）',
                          ),
                          for (final s in entry.value) _SessionTile(session: s),
                        ],
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetSectionTitle extends StatelessWidget {
  const _SheetSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BookGroupHeader extends StatelessWidget {
  const _BookGroupHeader({required this.bookId, required this.title});
  final int bookId;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: bookColor(bookId),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final ReadingSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pages = session.pagesRead;
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${hm(session.startedAt)}–${hm(session.endedAt)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${formatDuration(session.durationSeconds)}'
                  '${pages != null ? ' · $pages 页' : ''}'
                  '${session.round > 1 ? ' · 第 ${session.round} 遍' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
            Expanded(
              child: Center(child: Text(n, style: style)),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.tasksByDay,
    required this.sessionsByDay,
    required this.booksById,
    required this.onTapDay,
  });

  final DateTime month;
  final Map<String, List<TaskWithBook>> tasksByDay;
  final Map<String, List<ReadingSession>> sessionsByDay;
  final Map<int, Book> booksById;
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
      final key = formatDate(day);
      cells.add(
        _DayCell(
          day: day,
          tasks: tasksByDay[key] ?? const [],
          sessions: sessionsByDay[key] ?? const [],
          booksById: booksById,
          isToday: day == today0,
          onTap: () => onTapDay(day),
        ),
      );
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
    required this.sessions,
    required this.booksById,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final List<TaskWithBook> tasks;
  final List<ReadingSession> sessions;
  final Map<int, Book> booksById;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allDone =
        tasks.isNotEmpty && tasks.every((t) => t.task.status == 'done');
    final hasSkipped = tasks.any((t) => t.task.status == 'skipped') && !allDone;
    final recordOnly = tasks.isEmpty && sessions.isNotEmpty;

    // 当天出现过的书（排期优先，阅读记录补充，去重保序）。
    final books = <int, Book>{};
    for (final t in tasks) {
      books[t.book.id] = t.book;
    }
    for (final s in sessions) {
      final book = booksById[s.bookId];
      if (book != null) books[s.bookId] = book;
    }
    final bookList = books.values.toList();
    final shown = bookList.take(2).toList();
    final extra = bookList.length - shown.length;

    Color? tint;
    if (tasks.isNotEmpty) {
      tint = allDone
          ? scheme.primary
          : (hasSkipped ? scheme.tertiary : scheme.secondary);
    } else if (recordOnly) {
      tint = scheme.secondary;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
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
                  Icon(Icons.check_circle, size: 11, color: scheme.primary)
                else if (recordOnly)
                  Icon(Icons.auto_stories, size: 10, color: scheme.secondary),
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
                    decoration: allDone ? TextDecoration.lineThrough : null,
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
