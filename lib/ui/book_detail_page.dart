import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../domain/scheduling/scheduler.dart';
import '../state/providers.dart';
import 'book_form_page.dart';
import 'plan_editor_page.dart';
import 'stats_page.dart';
import 'widgets/task_card.dart';
import 'widgets/timer_banner.dart';

class BookDetailPage extends ConsumerWidget {
  const BookDetailPage({super.key, required this.bookId});
  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(bookProvider(bookId));
    final planAsync = ref.watch(planForBookProvider(bookId));

    return bookAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('出错了：$e'))),
      data: (book) {
        if (book == null) {
          return const Scaffold(body: Center(child: Text('读物不存在')));
        }
        final plan = planAsync.valueOrNull;
        final stats = ref.watch(bookStatsProvider(bookId)).valueOrNull;
        final settings = ref.watch(settingsProvider).valueOrNull;
        final activeTimer = ref.watch(activeTimerProvider);
        final timingThis = activeTimer != null && activeTimer.bookId == bookId;
        final rangeStart = today();
        final rangeEnd = addDays(rangeStart, 120);
        final tasksAsync = ref.watch(
          tasksInRangeProvider((rangeStart, rangeEnd)),
        );
        final tasks = (tasksAsync.valueOrNull ?? [])
            .where((t) => t.book.id == bookId)
            .toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('读物详情'),
            actions: [
              IconButton(
                tooltip: '编辑',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BookFormPage(book: book)),
                ),
              ),
              IconButton(
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmDelete(context, ref, book),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(book: book),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: timingThis
                    ? () => showStopTimerDialog(context, ref)
                    : () => startTimerFor(context, ref, bookId: book.id),
                icon: Icon(timingThis ? Icons.stop : Icons.play_arrow),
                label: Text(timingThis ? '结束计时' : '开始计时阅读'),
              ),
              const SizedBox(height: 16),
              if (settings != null) ...[
                _SectionCard(
                  title: '阅读统计',
                  child: _Stats(book: book, stats: stats, settings: settings),
                ),
                const SizedBox(height: 16),
              ],
              _SectionCard(
                title: '阅读历史',
                child: _RecentHistory(bookId: bookId),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: '阅读排期',
                child: plan == null
                    ? _NoPlan(book: book)
                    : _PlanSummary(book: book, plan: plan, settings: settings),
              ),
              const SizedBox(height: 16),
              if (tasks.isNotEmpty) ...[
                Text(
                  '即将到来的阅读任务',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                for (final t in tasks) TaskCard(item: t, showDate: true),
              ],
            ],
          ),
          bottomNavigationBar: const TimerBanner(),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Book book,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除《${book.title}》？'),
        content: const Text('相关的计划与任务记录会一并删除，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(repositoryProvider).deleteBook(book.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress =
        book.totalPages == 0 ? 0.0 : book.currentPage / book.totalPages;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (book.author != null && book.author!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            book.author!,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '已读 ${book.currentPage} / ${book.totalPages} 页 '
          '(${(progress * 100).toStringAsFixed(0)}%)',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '还没有排期。设置截止日和每天可用的时间，'
          '系统会把剩余页数自动摊到每一天。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PlanEditorPage(bookId: book.id),
            ),
          ),
          icon: const Icon(Icons.event_available),
          label: const Text('创建排期'),
        ),
      ],
    );
  }
}

class _PlanSummary extends ConsumerWidget {
  const _PlanSummary({required this.book, required this.plan, this.settings});
  final Book book;
  final Plan plan;
  final AppSetting? settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final restDates =
        ref.watch(restDatesProvider(plan.id)).valueOrNull ?? const <DateTime>{};
    final oversub = plan.status == 'oversubscribed';
    final statusText = switch (plan.status) {
      'completed' => '已完成',
      'oversubscribed' => '排不下：期限内读不完',
      'archived' => '已归档',
      _ => '进行中',
    };
    final weekdays = parseWeekdays(plan.weekdays);
    const names = {1: '一', 2: '二', 3: '三', 4: '四', 5: '五', 6: '六', 7: '日'};

    PlanProgress? progress;
    if (settings != null) {
      progress = computeProgress(
        currentPage: book.currentPage,
        totalPages: book.totalPages,
        startDate: plan.startDate,
        deadline: plan.deadline,
        dailyMinutes: plan.dailyMinutes,
        dailyPages: plan.dailyPages,
        weekdays: weekdays,
        pagesPerHour: effectivePace(book, settings!),
        restDates: restDates,
      );
    }
    final ahead = progress?.aheadPages;
    final finish = progress?.estimatedFinish;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('状态', statusText,
            color: oversub ? theme.colorScheme.error : null),
        _row('截止',
            plan.deadline == null ? '不设期限' : formatDate(plan.deadline!)),
        if (plan.dailyPages != null)
          _row('每天页数', '${plan.dailyPages} 页')
        else
          _row('每天时长', formatMinutes(plan.dailyMinutes)),
        _row('阅读日', weekdays.map((d) => names[d]).join(' ')),
        if (ahead != null)
          _row(
            '进度',
            ahead >= 0 ? '领先计划 $ahead 页' : '落后计划 ${-ahead} 页',
            color: ahead >= 0
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
        if (finish != null) _row('预计读完', formatDate(finish)),
        _row('休息日', '${restDates.length} 天'),
        if (oversub) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '按当前速度和每天时长，截止日前读不完。'
              '可以延长截止日、增加每天时长，或在设置里调高阅读速度。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlanEditorPage(bookId: book.id, plan: plan),
                ),
              ),
              icon: const Icon(Icons.edit_calendar),
              label: const Text('调整排期'),
            ),
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _RestDaysDialog(plan: plan),
              ),
              icon: const Icon(Icons.beach_access_outlined),
              label: Text('休息日（${restDates.length}）'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestDaysDialog extends ConsumerWidget {
  const _RestDaysDialog({required this.plan});
  final Plan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restDates =
        ref.watch(restDatesProvider(plan.id)).valueOrNull ?? const <DateTime>{};
    final sorted = restDates.toList()..sort();
    final lastDate = plan.deadline ?? DateTime(today().year + 3);

    return AlertDialog(
      title: const Text('休息日'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '休息日不安排阅读；多读的页数会优先抵消它们，'
              '抵消满一天，那天就轻松了。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            if (sorted.isEmpty)
              const Text('暂无休息日')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in sorted)
                    Chip(
                      label: Text(formatDate(d)),
                      onDeleted: () =>
                          ref.read(repositoryProvider).removeRestDay(plan.id, d),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: today(),
              firstDate: today(),
              lastDate: lastDate.isBefore(today()) ? today() : lastDate,
            );
            if (picked != null) {
              await ref.read(repositoryProvider).addRestDay(plan.id, picked);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('添加休息日'),
        ),
      ],
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats({
    required this.book,
    required this.stats,
    required this.settings,
  });

  final Book book;
  final BookStats? stats;
  final AppSetting settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stats;
    final avg = s?.averagePagesPerHour;
    final source = book.manualPagesPerHour != null
        ? '手动设置'
        : (book.measuredPagesPerHour != null ? '自动学习' : '全局默认');

    final daily = ref.watch(dailyStatsProvider(book.id)).valueOrNull;
    DailyStat? todayStat;
    if (daily != null) {
      final t = today();
      for (final d in daily) {
        if (d.date == t) {
          todayStat = d;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row(
            '今日',
            todayStat == null
                ? '暂无记录'
                : '${formatMinutes(todayStat.minutes)} · ${todayStat.pages} 页 · ${todayStat.sessions} 次'),
        _row('计时次数', '${s?.sessionCount ?? 0} 次'),
        _row('累计时长', formatMinutes(((s?.totalSeconds ?? 0) / 60).round())),
        _row('累计页数', '${s?.totalPages ?? 0} 页'),
        _row('平均速度',
            avg == null ? '数据不足' : '${avg.toStringAsFixed(1)} 页/小时'),
        _row(
            '平均单次',
            s?.averageSessionMinutes == null
                ? '数据不足'
                : '${s!.averageSessionMinutes!.toStringAsFixed(0)} 分钟/次'),
        _row('排期采用',
            '${effectivePace(book, settings)} 页/小时（$source）'),
        const SizedBox(height: 8),
        Text(
          '设置手动速度会覆盖自动学习值；否则用计时数据的平均值，'
          '估算会随着记录越来越准。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentHistory extends ConsumerWidget {
  const _RecentHistory({required this.bookId});
  final int bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sessionsProvider(bookId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text('出错了：$e'),
      data: (sessions) {
        if (sessions.isEmpty) {
          return Text(
            '还没有阅读记录。点上面的「开始计时阅读」，系统会据此学习你的阅读速度。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
        }
        final shown = sessions.take(5).toList();
        return Column(
          children: [
            for (final s in shown) _row(context, s),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StatsPage(bookId: bookId),
                  ),
                ),
                icon: const Icon(Icons.insights_outlined, size: 18),
                label: Text(
                  sessions.length > shown.length
                      ? '查看全部（共 ${sessions.length} 次记录）'
                      : '查看全部统计',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, ReadingSession s) {
    final scheme = Theme.of(context).colorScheme;
    final pages = s.pagesRead;
    final pace = (pages != null && pages > 0 && s.durationSeconds > 0)
        ? pages / (s.durationSeconds / 3600)
        : null;
    final start = s.startedAt;
    final hm =
        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.timer_outlined, size: 16, color: scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${start.month}/${start.day} $hm',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${formatDuration(s.durationSeconds)}'
                  '${pages != null ? ' · $pages 页' : ''}'
                  '${pace != null ? ' · ${pace.toStringAsFixed(0)} 页/小时' : ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
