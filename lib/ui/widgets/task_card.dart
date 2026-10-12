import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_x.dart';
import '../../data/repository.dart';
import '../../state/providers.dart';
import 'timer_banner.dart';

/// 单条阅读任务卡片：勾选完成后可记录读到的页码、也可计时或跳过。
class TaskCard extends ConsumerWidget {
  const TaskCard({super.key, required this.item, this.showDate = false});

  final TaskWithBook item;
  final bool showDate;

  bool get _done => item.task.status == 'done';
  bool get _skipped => item.task.status == 'skipped';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final task = item.task;
    final muted = _done || _skipped;

    final parts = <String>[
      '第 ${task.startPage}–${task.endPage} 页',
      '预计 ${formatMinutes(task.plannedMinutes)}',
      if (task.actualMinutes != null) '实际 ${formatMinutes(task.actualMinutes!)}',
      if (_done && task.reachedPage != null) '读到第 ${task.reachedPage} 页',
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
        child: Row(
          children: [
            Checkbox(
              value: _done,
              onChanged: (_) => _toggle(context, ref),
              shape: const CircleBorder(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration:
                                muted ? TextDecoration.lineThrough : null,
                            color: muted
                                ? theme.colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                      ),
                      if (showDate) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatDateCn(task.date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    parts.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_skipped)
              _chip(context, '已跳过', theme.colorScheme.outline)
            else if (_done)
              _chip(context, '已完成', theme.colorScheme.primary)
            else
              _menu(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _menu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        final repo = ref.read(repositoryProvider);
        switch (value) {
          case 'timer':
            await startTimerFor(
              context,
              ref,
              bookId: item.book.id,
              taskId: item.task.id,
            );
          case 'skip':
            await repo.completeTask(item.task.id, skipped: true);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'timer',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.timer_outlined),
            title: Text('开始计时'),
          ),
        ),
        PopupMenuItem(
          value: 'skip',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.redo_outlined),
            title: Text('跳过这次'),
          ),
        ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(repositoryProvider);
    if (_done) {
      await repo.reopenTask(item.task.id);
    } else {
      await _showCompleteDialog(context, ref);
    }
  }

  Future<void> _showCompleteDialog(BuildContext context, WidgetRef ref) async {
    final task = item.task;
    final pageController =
        TextEditingController(text: task.endPage.toString());
    final minutesController =
        TextEditingController(text: task.plannedMinutes.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('完成《${item.book.title}》'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '计划第 ${task.startPage}–${task.endPage} 页',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pageController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '读到第几页',
                hintText: '共 ${item.book.totalPages} 页',
                suffixText: '页',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minutesController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '用时（可选）',
                suffixText: '分钟',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('完成'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final page = int.tryParse(pageController.text.trim());
    final minutes = int.tryParse(minutesController.text.trim());
    await ref.read(repositoryProvider).completeTask(
          item.task.id,
          reachedPage: page,
          actualMinutes: minutes,
        );
  }
}
