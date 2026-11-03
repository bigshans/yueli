import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../services/target_app_service.dart';
import '../../services/weread/weread_launcher.dart';
import '../../services/weread/weread_sync_service.dart';
import '../../state/providers.dart';
import '../focus_timer_page.dart';

String formatDuration(int seconds) {
  final d = Duration(seconds: seconds);
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 开始为一个 / 一次任务计时，并进入专注计时页。
Future<void> startTimerFor(
  BuildContext context,
  WidgetRef ref, {
  required int bookId,
  int? taskId,
}) async {
  if (ref.read(activeTimerProvider) != null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已有正在进行的计时，请先结束')));
    return;
  }
  await ref.read(repositoryProvider).startTimer(bookId: bookId, taskId: taskId);
  await _maybeOpenReadingTarget(ref, bookId: bookId);
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const FocusTimerPage()));
}

/// 安卓端：按设置自动打开阅读应用。
///
/// 如果这本书绑定了微信读书，优先打开对应书籍页面；
/// 否则回退到设置里选择的普通应用。
Future<void> _maybeOpenReadingTarget(WidgetRef ref, {int? bookId}) async {
  final s = ref.read(settingsProvider).valueOrNull;
  if (s == null || !s.autoOpenApp) return;

  if (bookId != null) {
    final link = await ref.read(repositoryProvider).getWereadLink(bookId);
    if (link != null) {
      try {
        await openWereadBookLink(
          readerLink: link.readerLink,
          deepLink: link.deepLink,
          bookId: link.wereadBookId,
        );
        return;
      } catch (_) {
        // 链接不可用时继续尝试设置里的兜底应用。
      }
    }
  }

  final pkg = s.autoOpenPackage;
  if (pkg == null || pkg.isEmpty) return;
  await TargetAppService.open(pkg);
}

/// 先开计时，书本之后再选。
Future<void> startFreeTimer(BuildContext context, WidgetRef ref) async {
  if (ref.read(activeTimerProvider) != null) {
    await openFocusTimer(context);
    return;
  }
  await ref.read(repositoryProvider).startTimer();
  await _maybeOpenReadingTarget(ref);
  if (!context.mounted) return;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const FocusTimerPage()));
}

/// 为当前计时选择书本。返回选中的书（取消则 null）。
Future<Book?> pickBookForTimer(BuildContext context, WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final books = await repo.allBooks();
  if (!context.mounted) return null;
  if (books.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('还没有读物，请先在书架添加')));
    return null;
  }
  final selected = await showModalBottomSheet<Book>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('选择正在读的书'),
          ),
          for (final b in books)
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(b.title),
              subtitle: b.author == null ? null : Text(b.author!),
              onTap: () => Navigator.pop(context, b),
            ),
        ],
      ),
    ),
  );
  if (selected == null) return null;
  await repo.setTimerBook(selected.id);
  return selected;
}

/// 打开专注计时页。
Future<void> openFocusTimer(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const FocusTimerPage()));
}

/// 结束计时对话框：确认用时、页数与是否完成任务。
Future<void> showStopTimerDialog(BuildContext context, WidgetRef ref) async {
  final initial = ref.read(activeTimerProvider);
  if (initial == null) return;
  final repo = ref.read(repositoryProvider);

  // 点「结束」立即暂停，冻结本次用时（选书/确认期间不再计时）。
  final now = DateTime.now();
  final wasRunning = initial.isRunning;
  if (wasRunning) await repo.pauseTimer(now: now);
  final elapsed = initial.elapsedSecondsAt(now);

  // 先计时后选书：结束前必须指定书本。
  var bookId = initial.bookId;
  if (bookId == null) {
    if (!context.mounted) return;
    final selected = await pickBookForTimer(context, ref);
    if (selected == null) {
      // 取消选书：恢复计时。
      if (wasRunning) await repo.resumeTimer();
      return;
    }
    bookId = selected.id;
  }

  final boundTask = initial.taskId == null
      ? null
      : await repo.getTask(initial.taskId!);
  // 自由计时时，归到今天这本书的任务，这样时长也能计进去。
  final task = boundTask ?? await repo.taskForBookOnDate(bookId, now);
  final attributed = boundTask == null && task != null;
  final book = await repo.getBook(bookId);
  if (!context.mounted) {
    if (wasRunning) await repo.resumeTimer();
    return;
  }

  // 已绑定微信读书时，结束计时前读取一次远端进度，用来预填「读到第几页」。
  WereadProgressPreview? wereadPreview;
  final wereadLink = await repo.getWereadLink(bookId);
  if (wereadLink != null && context.mounted) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('正在读取微信读书进度…'),
          ],
        ),
      ),
    );
    try {
      wereadPreview = await ref
          .read(wereadSyncServiceProvider)
          .previewBook(bookId);
    } catch (_) {
      // 读取失败时保留原有预填逻辑，不阻断结束计时。
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  if (!context.mounted) {
    if (wasRunning) await repo.resumeTimer();
    return;
  }

  final initialPage =
      wereadPreview?.estimatedPage ?? task?.endPage ?? book?.currentPage;
  final pageController = TextEditingController(
    text: initialPage?.toString() ?? '',
  );
  final minutesController = TextEditingController(text: '${elapsed ~/ 60}');
  final secondsController = TextEditingController(text: '${elapsed % 60}');
  var completeTask = boundTask != null;

  final result = await showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        scrollable: true,
        title: const Text('结束计时'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Text('本次用时', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minutesController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '分钟',
                      suffixText: '分',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: secondsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '秒',
                      suffixText: '秒',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '短时段可以手动修改用时；自动记录为 ${formatDuration(elapsed)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (attributed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '会计入今天《${book?.title ?? ''}》的阅读任务',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            if (wereadPreview != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '微信读书进度 ${wereadPreview.remoteProgress}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      wereadPreview.finished
                          ? '微信读书已读完，预填为最后一页。'
                          : '按本地总页数估算约为第 ${wereadPreview.estimatedPage} 页，可手动修改。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (task != null) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: completeTask,
                onChanged: (v) => setState(() => completeTask = v),
                title: const Text('标记该任务已完成'),
                subtitle: Text('计划第 ${task.startPage}–${task.endPage} 页'),
              ),
              const SizedBox(height: 4),
            ],
            TextField(
              controller: pageController,
              keyboardType: TextInputType.number,
              autofocus: task == null,
              decoration: _pageField(book),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'abandon'),
            child: const Text('放弃计时'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );

  final parsedMinutes = int.tryParse(minutesController.text.trim());
  final parsedSeconds = int.tryParse(secondsController.text.trim());
  var manualSeconds = (parsedMinutes ?? 0) * 60 + (parsedSeconds ?? 0);
  if (manualSeconds <= 0) manualSeconds = 1;
  minutesController.dispose();
  secondsController.dispose();

  if (result == 'abandon') {
    await repo.cancelTimer();
    return;
  }
  if (result != 'save') {
    // 取消对话框：恢复计时。
    if (wasRunning) await repo.resumeTimer();
    return;
  }
  final reached = int.tryParse(pageController.text.trim());
  await repo.stopTimer(
    reachedPage: reached,
    completeTask: completeTask,
    fallbackBookId: bookId,
    durationSeconds: manualSeconds,
  );
}

InputDecoration _pageField(Book? book) => InputDecoration(
  labelText: '读到第几页',
  hintText: book != null ? '共 ${book.totalPages} 页' : null,
  suffixText: '页',
  border: const OutlineInputBorder(),
);

/// 底部常驻计时条，只在计时中存在，每秒刷新已用时长（暂停时不刷新）。
class TimerBanner extends ConsumerStatefulWidget {
  const TimerBanner({super.key});

  @override
  ConsumerState<TimerBanner> createState() => _TimerBannerState();
}

class _TimerBannerState extends ConsumerState<TimerBanner> {
  Timer? _ticker;

  void _syncTicker(bool running) {
    if (running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(activeTimerProvider);
    _syncTicker(timer?.isRunning ?? false);
    ref.listen(
      activeTimerProvider,
      (_, next) => _syncTicker(next?.isRunning ?? false),
    );
    if (timer == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final book = timer.bookId == null
        ? null
        : ref.watch(bookProvider(timer.bookId!)).valueOrNull;
    final elapsed = timer.elapsedSecondsAt(DateTime.now());

    return Material(
      color: scheme.primaryContainer,
      child: InkWell(
        onTap: () => openFocusTimer(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book?.title ?? (timer.bookId == null ? '未选择书本' : '阅读中'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${timer.isRunning ? '计时中' : '已暂停'} · ${formatDuration(elapsed)}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: timer.isRunning ? '暂停' : '继续',
                icon: Icon(
                  timer.isRunning ? Icons.pause : Icons.play_arrow,
                  color: scheme.onPrimaryContainer,
                ),
                onPressed: () {
                  final repo = ref.read(repositoryProvider);
                  timer.isRunning ? repo.pauseTimer() : repo.resumeTimer();
                },
              ),
              FilledButton.tonal(
                onPressed: () => showStopTimerDialog(context, ref),
                child: const Text('结束'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
