import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets/timer_banner.dart';

/// 全屏专注计时器：大字号时长 + 进度环 + 暂停/继续/结束。
class FocusTimerPage extends ConsumerStatefulWidget {
  const FocusTimerPage({super.key});

  @override
  ConsumerState<FocusTimerPage> createState() => _FocusTimerPageState();
}

class _FocusTimerPageState extends ConsumerState<FocusTimerPage> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(activeTimerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('专注计时')),
      body: timer == null
          ? _Finished(onBack: () => Navigator.of(context).maybePop())
          : _TimerBody(
              timer: timer,
              now: _now,
              scheme: scheme,
              onFinish: () async {
                final navigator = Navigator.of(context);
                await showStopTimerDialog(context, ref);
                if (ref.read(activeTimerProvider) == null) {
                  navigator.pop();
                }
              },
              onAbandon: () async {
                final navigator = Navigator.of(context);
                await ref.read(repositoryProvider).cancelTimer();
                navigator.pop();
              },
            ),
    );
  }
}

class _TimerBody extends ConsumerWidget {
  const _TimerBody({
    required this.timer,
    required this.now,
    required this.scheme,
    required this.onFinish,
    required this.onAbandon,
  });

  final ActiveTimer timer;
  final DateTime now;
  final ColorScheme scheme;
  final Future<void> Function() onFinish;
  final Future<void> Function() onAbandon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(bookProvider(timer.bookId)).valueOrNull;
    final plan = ref.watch(planForBookProvider(timer.bookId)).valueOrNull;
    final targetSeconds = (plan?.dailyMinutes ?? 30) * 60;
    final elapsed = timer.elapsedSecondsAt(now);
    final progress = (elapsed / targetSeconds).clamp(0.0, 1.0);
    final overTarget = elapsed >= targetSeconds;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            book?.title ?? '阅读中',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            timer.isRunning ? '计时中' : '已暂停',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 260,
                  height: 260,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 12,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: overTarget ? scheme.tertiary : scheme.primary,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatDuration(elapsed),
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '目标 ${formatDuration(targetSeconds)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            overTarget ? '已达成今天的阅读目标，好样的！' : '保持专注，放下手机',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: overTarget ? scheme.tertiary : scheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final repo = ref.read(repositoryProvider);
                    timer.isRunning
                        ? repo.pauseTimer()
                        : repo.resumeTimer();
                  },
                  icon: Icon(timer.isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(timer.isRunning ? '暂停' : '继续'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(Icons.stop),
                  label: const Text('结束'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: onAbandon,
            child: const Text('放弃这次计时'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('计时已结束'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onBack, child: const Text('返回')),
        ],
      ),
    );
  }
}
