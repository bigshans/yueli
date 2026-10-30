import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/book_status.dart';
import '../data/database.dart';
import '../state/providers.dart';
import 'settings_page.dart';
import 'widgets/task_card.dart';
import 'widgets/timer_banner.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(todayTasksProvider);
    final today0 = ref.watch(logicalTodayProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日'),
        actions: [
          IconButton(
            tooltip: '开始计时',
            icon: const Icon(Icons.timer_outlined),
            onPressed: () => startFreeTimer(context, ref),
          ),
          IconButton(
            tooltip: '手动补记页数',
            icon: const Icon(Icons.edit_note),
            onPressed: () => showManualRecordDialog(context, ref),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const _EmptyState();
          }
          final pending = tasks
              .where((t) => t.task.status == 'pending')
              .toList();
          final done = tasks.where((t) => t.task.status == 'done').toList();
          final skipped = tasks
              .where((t) => t.task.status == 'skipped')
              .toList();
          final planned = pending.fold<int>(
            0,
            (sum, t) => sum + t.task.plannedMinutes,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                formatDateCn(today0),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _Summary(
                total: tasks.length,
                done: done.length,
                remainingMinutes: planned,
              ),
              const SizedBox(height: 8),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionTitle('待读'),
                for (final t in pending) TaskCard(item: t),
              ],
              if (done.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionTitle('已完成'),
                for (final t in done) TaskCard(item: t),
              ],
              if (skipped.isNotEmpty) ...[
                const SizedBox(height: 20),
                _SectionTitle('已跳过'),
                for (final t in skipped) TaskCard(item: t),
              ],
            ],
          );
        },
      ),
    );
  }
}

Future<void> showManualRecordDialog(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final books = await repo.allBooks();
  if (!context.mounted) return;
  final candidates = books
      .where((b) => b.totalPages > 0 && b.status != BookStatus.finished)
      .toList();
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('没有可补记的书')));
    return;
  }

  final result = await showDialog<_ManualRecordResult>(
    context: context,
    builder: (_) => _ManualRecordDialog(
      books: candidates,
      today: ref.read(logicalTodayProvider),
    ),
  );
  if (result == null) return;

  final pages = await repo.logPagesRead(
    bookId: result.bookId,
    reachedPage: result.reachedPage,
    at: result.at,
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(pages > 0 ? '已补记 $pages 页' : '页数没有增加')),
  );
}

class _ManualRecordResult {
  const _ManualRecordResult({
    required this.bookId,
    required this.reachedPage,
    required this.at,
  });

  final int bookId;
  final int reachedPage;
  final DateTime at;
}

class _ManualRecordDialog extends StatefulWidget {
  const _ManualRecordDialog({required this.books, required this.today});

  final List<Book> books;
  final DateTime today;

  @override
  State<_ManualRecordDialog> createState() => _ManualRecordDialogState();
}

class _ManualRecordDialogState extends State<_ManualRecordDialog> {
  late int _bookId;
  late DateTime _date;
  final _page = TextEditingController();

  Book get _book => widget.books.firstWhere((b) => b.id == _bookId);

  @override
  void initState() {
    super.initState();
    _bookId = widget.books.first.id;
    _date = widget.today;
    _page.text = _book.currentPage.toString();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2000),
      lastDate: now,
      helpText: '选择阅读日期',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _submit(int reached) {
    final now = DateTime.now();
    final at = dateOnly(_date) == dateOnly(now)
        ? now
        : DateTime(_date.year, _date.month, _date.day, 12);
    Navigator.pop(
      context,
      _ManualRecordResult(bookId: _bookId, reachedPage: reached, at: at),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final reached = int.tryParse(_page.text.trim());
    final added = (reached ?? book.currentPage) - book.currentPage;

    return AlertDialog(
      title: const Text('手动补记页数'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<int>(
            value: _bookId,
            decoration: const InputDecoration(
              labelText: '读物',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final b in widget.books)
                DropdownMenuItem(value: b.id, child: Text(b.title)),
            ],
            onChanged: (id) {
              if (id == null) return;
              setState(() {
                _bookId = id;
                _page.text = _book.currentPage.toString();
              });
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(formatDate(_date)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _page,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '读到第几页',
              helperText: '当前 ${book.currentPage} / ${book.totalPages} 页',
              suffixText: '页',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            added > 0 ? '本次补记 $added 页' : '页数没有增加',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: added > 0
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: added > 0 ? () => _submit(reached!) : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.done,
    required this.remainingMinutes,
  });

  final int total;
  final int done;
  final int remainingMinutes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _stat(context, '$done/$total', '完成'),
            _divider(scheme),
            _stat(context, formatMinutes(remainingMinutes), '预计剩余'),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

  Widget _divider(ColorScheme scheme) =>
      Container(width: 1, height: 32, color: scheme.outlineVariant);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 56, color: scheme.outline),
            const SizedBox(height: 16),
            Text('今天没有排期', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '去「书架」添加一本书并创建阅读计划，\n系统会自动把页数摊到每一天。',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
