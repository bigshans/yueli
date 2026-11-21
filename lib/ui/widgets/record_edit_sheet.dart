import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/repository.dart';
import '../../state/providers.dart';

/// 打开「编辑阅读记录」底部弹窗（手动补记或计时记录）。
Future<void> showSessionEditSheet(
  BuildContext context,
  ReadingSession session,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SessionEditSheet(session: session),
  );
}

/// 打开「编辑任务结果」底部弹窗（仅对已完成的任务可用）。
Future<void> showTaskEditSheet(BuildContext context, TaskWithBook item) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TaskEditSheet(item: item),
  );
}

class _SessionEditSheet extends ConsumerStatefulWidget {
  const _SessionEditSheet({required this.session});
  final ReadingSession session;

  @override
  ConsumerState<_SessionEditSheet> createState() => _SessionEditSheetState();
}

class _SessionEditSheetState extends ConsumerState<_SessionEditSheet> {
  late final TextEditingController _page;
  late final TextEditingController _minutes;
  ReplayPreview? _preview;
  int? _nextPage;
  int _before = 0;
  late DateTime _date;
  int _generation = 0;
  bool _saving = false;

  ReadingSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _date = _session.startedAt;
    _page = TextEditingController();
    _minutes = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final preview = await ref
        .read(repositoryProvider)
        .previewSessionEdit(_session.id);
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _before = preview.reachedBefore;
      _nextPage = preview.nextPage;
      _page.text = '${preview.reachedAfter}';
      _minutes.text = '${_session.durationSeconds ~/ 60}';
    });
  }

  Future<void> _refreshPreview(int page) async {
    final generation = ++_generation;
    final preview = await ref
        .read(repositoryProvider)
        .previewSessionEdit(_session.id, reachedPage: page, startedAt: _date);
    if (!mounted || generation != _generation) return;
    setState(() {
      _nextPage = preview.nextPage;
      _before = preview.reachedBefore;
    });
  }

  int? get _pageValue {
    final value = int.tryParse(_page.text.trim());
    if (value == null) return null;
    return value;
  }

  int get _minutesValue => int.tryParse(_minutes.text.trim()) ?? 0;

  bool get _pageTooLow => _pageValue != null && _pageValue! < _before;

  bool get _canSave {
    final page = _pageValue;
    return !_saving && page != null && page >= _before;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = ref.watch(bookProvider(_session.bookId)).valueOrNull;
    final totalPages = book?.totalPages ?? 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '编辑阅读记录',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (book != null) ...[
                const SizedBox(height: 2),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (_preview == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                TextField(
                  controller: _page,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) {
                    final page = int.tryParse(value.trim());
                    if (page != null) _refreshPreview(page);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: '读到第几页',
                    hintText: totalPages > 0 ? '共 $totalPages 页' : null,
                    suffixText: '页',
                    border: const OutlineInputBorder(),
                    errorText: _pageTooLow ? '不能早于第 $_before 页' : null,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _pageValue == null
                      ? ' '
                      : '本次 ${(_pageValue! - _before).clamp(0, 1 << 30)} 页',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minutes,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(
                          labelText: '用时',
                          helperText: '填 0 表示手动补记',
                          suffixText: '分钟',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '阅读日期',
                          border: OutlineInputBorder(),
                        ),
                        child: InkWell(
                          onTap: _pickDate,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(
                              '${_date.year}/${_date.month}/${_date.day}',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ConsequenceLine(
                  previous: _preview!.previousPage,
                  next: _nextPage,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _saving ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      label: const Text('删除记录'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      );
    });
    final page = _pageValue;
    if (page != null) await _refreshPreview(page);
  }

  Future<void> _save() async {
    final page = _pageValue;
    if (page == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(repositoryProvider)
        .updateSession(
          _session.id,
          reachedPage: page,
          durationSeconds: _minutesValue * 60,
          startedAt: _date,
        );
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(_resultText(result))));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('删除后会重新计算书本进度，并重新安排后续任务。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(repositoryProvider)
        .deleteSession(_session.id);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(_resultText(result))));
  }
}

class _TaskEditSheet extends ConsumerStatefulWidget {
  const _TaskEditSheet({required this.item});
  final TaskWithBook item;

  @override
  ConsumerState<_TaskEditSheet> createState() => _TaskEditSheetState();
}

class _TaskEditSheetState extends ConsumerState<_TaskEditSheet> {
  late final TextEditingController _page;
  late final TextEditingController _minutes;
  ReplayPreview? _preview;
  int? _nextPage;
  int _generation = 0;
  bool _saving = false;

  Task get _task => widget.item.task;
  Book get _book => widget.item.book;

  @override
  void initState() {
    super.initState();
    _page = TextEditingController(
      text: '${_task.reachedPage ?? _task.endPage}',
    );
    _minutes = TextEditingController(
      text: '${_task.actualMinutes ?? _task.plannedMinutes}',
    );
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final preview = await ref
        .read(repositoryProvider)
        .previewTaskEdit(_task.id);
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _nextPage = preview.nextPage;
    });
  }

  Future<void> _refreshPreview(int page) async {
    final generation = ++_generation;
    final preview = await ref
        .read(repositoryProvider)
        .previewTaskEdit(_task.id, reachedPage: page);
    if (!mounted || generation != _generation) return;
    setState(() => _nextPage = preview.nextPage);
  }

  int? get _pageValue => int.tryParse(_page.text.trim());

  bool get _canSave => !_saving && _pageValue != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '编辑任务结果',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_book.title} · 计划第 ${_task.startPage}–${_task.endPage} 页',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              if (_preview == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                TextField(
                  controller: _page,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (value) {
                    final page = int.tryParse(value.trim());
                    if (page != null) _refreshPreview(page);
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: '读到第几页',
                    hintText: _book.totalPages > 0
                        ? '共 ${_book.totalPages} 页'
                        : null,
                    suffixText: '页',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '用时（可选）',
                    suffixText: '分钟',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                _ConsequenceLine(
                  previous: _preview!.previousPage,
                  next: _nextPage,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _saving ? null : _reopen,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('撤销完成'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final page = _pageValue;
    if (page == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(repositoryProvider)
        .updateCompletedTask(
          _task.id,
          reachedPage: page,
          actualMinutes: int.tryParse(_minutes.text.trim()),
        );
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(_resultText(result))));
  }

  Future<void> _reopen() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(repositoryProvider).reopenTask(_task.id);
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('已撤销完成，任务回到待读')));
  }
}

class _ConsequenceLine extends StatelessWidget {
  const _ConsequenceLine({required this.previous, required this.next});
  final int previous;
  final int? next;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = next == null
        ? '保存后会重算进度，并重新安排后续任务。'
        : next == previous
        ? '保存后进度仍是第 $next 页，后续任务会重新安排。'
        : '保存后：进度第 $previous 页 → 第 $next 页，后续任务会重新安排。';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _resultText(ReplayResult result) {
  if (result.changed) {
    return '已更新，进度第 ${result.previousPage} 页 → 第 ${result.currentPage} 页';
  }
  return '已更新';
}
