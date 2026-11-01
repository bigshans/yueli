import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../core/format_x.dart';
import '../data/book_status.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../domain/scheduling/scheduler.dart';
import '../services/weread/weread_launcher.dart';
import '../state/providers.dart';
import 'book_form_page.dart';
import 'plan_editor_page.dart';
import 'stats_page.dart';
import 'weread_bind_page.dart';
import 'widgets/book_cover.dart';
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
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
        final rangeStart = ref.watch(logicalTodayProvider);
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
              PopupMenuButton<String>(
                tooltip: '阅读状态',
                initialValue: book.status,
                icon: const Icon(Icons.bookmark_outline),
                onSelected: (status) => _setStatus(context, ref, book, status),
                itemBuilder: (context) => [
                  for (final status in BookStatus.all)
                    CheckedPopupMenuItem(
                      value: status,
                      checked: book.status == status,
                      child: Text(BookStatus.label(status)),
                    ),
                ],
              ),
              _WereadActionsButton(book: book),
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
              _WereadCard(book: book),
              const SizedBox(height: 16),
              if (_BookInfoCard.hasContent(book)) ...[
                _BookInfoCard(book: book),
                const SizedBox(height: 16),
              ],
              if (book.description != null &&
                  book.description!.trim().isNotEmpty) ...[
                _DescriptionCard(text: book.description!.trim()),
                const SizedBox(height: 16),
              ],
              if (settings != null) ...[
                _SectionCard(
                  title: '阅读统计',
                  child: _Stats(book: book, stats: stats, settings: settings),
                ),
                const SizedBox(height: 16),
              ],
              _SectionCard(
                title: '阅读轮次',
                child: _ReadingRounds(book: book),
              ),
              const SizedBox(height: 16),
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    Book book,
    String status,
  ) async {
    await ref.read(repositoryProvider).setBookStatus(book.id, status);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已标记为「${BookStatus.label(status)}」')),
      );
    }
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
    final progress = book.totalPages == 0
        ? 0.0
        : book.currentPage / book.totalPages;
    final tags = parseTags(book.tags);
    final author = (book.author == null || book.author!.trim().isEmpty)
        ? '未知作者'
        : book.author!.trim();
    final translator = book.translator?.trim();
    final rating = formatRating(book.rating, book.ratingCount);
    final wordCount = formatWordCount(book.wordCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(book: book, width: 88, height: 124, borderRadius: 10),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    translator == null || translator.isEmpty
                        ? author
                        : '$author · 译者 $translator',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (rating.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 17,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 3),
                        Text(rating, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                  if (wordCount.isNotEmpty || book.totalPages > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (wordCount.isNotEmpty) wordCount,
                        if (book.totalPages > 0) '${book.totalPages} 页',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final t in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '#$t',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (book.status != BookStatus.reading) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        BookStatus.label(book.status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
          '(${(progress * 100).toStringAsFixed(0)}%) · '
          '剩余 ${book.totalPages - book.currentPage} 页',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _BookInfoCard extends StatelessWidget {
  const _BookInfoCard({required this.book});
  final Book book;

  static bool hasContent(Book book) =>
      _nonEmpty(book.publisher) ||
      _nonEmpty(book.publishDate) ||
      _nonEmpty(book.isbn) ||
      book.wordCount != null ||
      book.metadataSource != 'manual';

  static bool _nonEmpty(String? value) =>
      value != null && value.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (_nonEmpty(book.publisher)) ('出版社', book.publisher!.trim()),
      if (_nonEmpty(book.publishDate)) ('出版时间', book.publishDate!.trim()),
      if (_nonEmpty(book.isbn)) ('ISBN', book.isbn!.trim()),
      if (book.wordCount != null) ('字数', formatWordCount(book.wordCount)),
      if (book.metadataSource != 'manual')
        (
          '数据来源',
          switch (book.metadataSource) {
            'weread' => '微信读书',
            'import' => '导入',
            _ => book.metadataSource,
          },
        ),
    ];
    return _SectionCard(
      title: '书籍信息',
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Text(
                    rows[i].$1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatefulWidget {
  const _DescriptionCard({required this.text});
  final String text;

  @override
  State<_DescriptionCard> createState() => _DescriptionCardState();
}

class _DescriptionCardState extends State<_DescriptionCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canExpand = widget.text.length > 120 || widget.text.contains('\n');
    return _SectionCard(
      title: '简介',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
          if (canExpand) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起' : '展开'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WereadCard extends ConsumerWidget {
  const _WereadCard({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkAsync = ref.watch(wereadLinkProvider(book.id));
    return linkAsync.maybeWhen(
      data: (link) => link == null
          ? _WereadBindCard(book: book)
          : _WereadLinkedCard(book: book, link: link),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _WereadBindCard extends ConsumerWidget {
  const _WereadBindCard({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: '微信读书',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '还没有绑定微信读书。绑定后可以打开阅读链接，并同步微信读书的阅读进度。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final linked = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      WereadBindPage(bookId: book.id, bookTitle: book.title),
                ),
              );
              if (linked == true && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已绑定微信读书')));
              }
            },
            icon: const Icon(Icons.link),
            label: const Text('绑定微信读书'),
          ),
        ],
      ),
    );
  }
}

enum _WereadAction { open, sync, unbind }

class _WereadActionsButton extends ConsumerStatefulWidget {
  const _WereadActionsButton({required this.book});
  final Book book;

  @override
  ConsumerState<_WereadActionsButton> createState() =>
      _WereadActionsButtonState();
}

class _WereadActionsButtonState extends ConsumerState<_WereadActionsButton> {
  bool _busy = false;

  Future<void> _open(WereadLink link) async {
    try {
      await openWereadBookLink(
        readerLink: link.readerLink,
        deepLink: link.deepLink,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('打开失败：$e')));
    }
  }

  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(wereadSyncServiceProvider);
      final result = await service.syncBook(widget.book.id);
      if (!mounted) return;

      if (!result.finished &&
          result.remoteProgress < 100 &&
          result.estimatedPage > result.localPage) {
        final apply = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('按比例更新本地页码？'),
            content: Text(
              '微信读书进度为 ${result.remoteProgress}%。\n'
              '按本地总页数换算，约为第 ${result.estimatedPage} 页。\n\n'
              '微信读书的进度百分比和本地页码并不等同，这只是估算。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('仅记录进度'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('更新本地页码'),
              ),
            ],
          ),
        );
        if (apply == true) {
          await service.applyEstimatedPage(
            widget.book.id,
            result.estimatedPage,
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '已按估算更新到第 ${result.estimatedPage} 页。'
                '如需精确页码，可以手动修改。',
              ),
            ),
          );
          return;
        }
        if (!mounted) return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('同步失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbind() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解除微信读书绑定？'),
        content: const Text('只会解除关联，不会删除本地书籍和阅读记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('解除绑定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(repositoryProvider).unlinkWereadBook(widget.book.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已解除微信读书绑定')));
  }

  Future<void> _handle(_WereadAction action, WereadLink link) async {
    switch (action) {
      case _WereadAction.open:
        await _open(link);
      case _WereadAction.sync:
        await _sync();
      case _WereadAction.unbind:
        await _unbind();
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(wereadLinkProvider(widget.book.id)).valueOrNull;
    if (link == null) return const SizedBox.shrink();
    return PopupMenuButton<_WereadAction>(
      tooltip: '微信读书',
      enabled: !_busy,
      icon: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_outlined),
      onSelected: (action) => _handle(action, link),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _WereadAction.open,
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 18),
              SizedBox(width: 10),
              Text('打开阅读'),
            ],
          ),
        ),
        PopupMenuItem(
          value: _WereadAction.sync,
          child: Row(
            children: [
              Icon(Icons.sync, size: 18),
              SizedBox(width: 10),
              Text('同步进度'),
            ],
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: _WereadAction.unbind,
          child: Row(
            children: [
              Icon(Icons.link_off, size: 18),
              SizedBox(width: 10),
              Text('解除绑定'),
            ],
          ),
        ),
      ],
    );
  }
}

class _WereadLinkedCard extends StatelessWidget {
  const _WereadLinkedCard({required this.book, required this.link});
  final Book book;
  final WereadLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readTime = link.remoteReadSeconds == null
        ? ''
        : formatReadSeconds(link.remoteReadSeconds!);
    return _SectionCard(
      title: '微信读书',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_done_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '已绑定',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (link.lastSyncedAt != null)
                Text(
                  '同步于 ${formatRelativeDate(link.lastSyncedAt)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (link.remoteProgress / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '微信读书进度 ${link.remoteProgress}%',
                style: theme.textTheme.bodySmall,
              ),
              if (readTime.isNotEmpty) ...[
                const SizedBox(width: 10),
                Text(
                  '累计 $readTime',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '微信读书进度是百分比，本地是页码；按比例换算只能作为估算。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '打开阅读、同步进度、解除绑定在右上角微信读书菜单。',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
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
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
            MaterialPageRoute(builder: (_) => PlanEditorPage(bookId: book.id)),
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
    final statusText = book.status != BookStatus.reading
        ? BookStatus.label(book.status)
        : switch (plan.status) {
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
        _row('状态', statusText, color: oversub ? theme.colorScheme.error : null),
        _row('截止', plan.deadline == null ? '不设期限' : formatDate(plan.deadline!)),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
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
    final today0 = ref.watch(logicalTodayProvider);
    final lastDate = plan.deadline ?? DateTime(today0.year + 3);

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
                      onDeleted: () => ref
                          .read(repositoryProvider)
                          .removeRestDay(plan.id, d),
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
              initialDate: today0,
              firstDate: today0,
              lastDate: lastDate.isBefore(today0) ? today0 : lastDate,
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
      final t = ref.watch(logicalTodayProvider);
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
              : '${formatMinutes(todayStat.minutes)} · ${todayStat.pages} 页 · ${todayStat.sessions} 次',
        ),
        _row('计时次数', '${s?.sessionCount ?? 0} 次'),
        _row('累计时长', formatMinutes(((s?.totalSeconds ?? 0) / 60).round())),
        _row('累计页数', '${s?.totalPages ?? 0} 页'),
        _row('平均速度', avg == null ? '数据不足' : '${avg.toStringAsFixed(1)} 页/小时'),
        _row(
          '平均单次',
          s?.averageSessionMinutes == null
              ? '数据不足'
              : '${s!.averageSessionMinutes!.toStringAsFixed(0)} 分钟/次',
        ),
        _row('排期采用', '${effectivePace(book, settings)} 页/小时（$source）'),
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
                  MaterialPageRoute(builder: (_) => StatsPage(bookId: bookId)),
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
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
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

/// 各遍阅读记录，并在读完时提供「开始重读」。
class _ReadingRounds extends ConsumerWidget {
  const _ReadingRounds({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingsAsync = ref.watch(readingsProvider(book.id));
    final sessions =
        ref.watch(sessionsProvider(book.id)).valueOrNull ?? const [];
    final finished = book.totalPages > 0 && book.currentPage >= book.totalPages;

    // 每遍的累计时长/页数。
    final totals = <int, (int, int)>{};
    for (final s in sessions) {
      final cur = totals[s.round] ?? (0, 0);
      totals[s.round] = (
        cur.$1 + s.durationSeconds,
        cur.$2 + (s.pagesRead ?? 0),
      );
    }

    return readingsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Text('出错了：$e'),
      data: (readings) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in readings) _row(context, r, totals[r.round]),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => _confirmReread(context, ref, finished: finished),
              icon: const Icon(Icons.replay),
              label: Text('开始重读（第 ${book.round + 1} 遍）'),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, Reading r, (int, int)? total) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isCurrent = r.round == book.round;
    final active = isCurrent && r.finishedAt == null;
    final status = active ? '（进行中）' : (r.completed ? '（已完成）' : '（未读完）');
    final range = r.finishedAt == null
        ? '${formatDate(r.startedAt)} 起'
        : '${formatDate(r.startedAt)} ~ ${formatDate(r.finishedAt!)}';
    final totals = total == null
        ? ''
        : ' · ${formatMinutes((total.$1 / 60).round())} · ${total.$2} 页';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isCurrent ? scheme.primary : scheme.outline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 ${r.round} 遍$status',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$range$totals',
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

  Future<void> _confirmReread(
    BuildContext context,
    WidgetRef ref, {
    required bool finished,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('开始重读《${book.title}》？'),
        content: Text(
          finished
              ? '会开始新的一遍，进度重置为第 1 页；之前的阅读记录会保留。'
              : '这一遍还没读完。开始重读会把这一遍记为「未读完」，进度重置为第 1 页；之前的记录会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始重读'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(repositoryProvider).startReread(book.id);
    }
  }
}
