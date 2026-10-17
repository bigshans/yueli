import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../state/providers.dart';
import 'settings_page.dart';
import 'widgets/task_card.dart';
import 'widgets/timer_banner.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(todayTasksProvider);
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
            tooltip: '设置',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
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
          final pending = tasks.where((t) => t.task.status == 'pending').toList();
          final done = tasks.where((t) => t.task.status == 'done').toList();
          final skipped =
              tasks.where((t) => t.task.status == 'skipped').toList();
          final planned = pending.fold<int>(
            0,
            (sum, t) => sum + t.task.plannedMinutes,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                formatDateCn(today()),
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
