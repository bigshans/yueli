import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../domain/scheduling/scheduler.dart';
import '../state/providers.dart';
import 'widgets/slider_field.dart';
import 'widgets/timer_banner.dart';

class PlanEditorPage extends ConsumerStatefulWidget {
  const PlanEditorPage({super.key, required this.bookId, this.plan});
  final int bookId;
  final Plan? plan;

  @override
  ConsumerState<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends ConsumerState<PlanEditorPage> {
  late DateTime _deadline;
  late int _dailyMinutes;
  late int _dailyPages;
  late bool _noDeadline;
  late bool _byPages;
  late Set<int> _weekdays;
  late final TextEditingController _minutesCtrl;
  late final TextEditingController _pagesCtrl;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    final p = widget.plan;
    _deadline = p?.deadline ?? addDays(today(), 14);
    _noDeadline = p != null && p.deadline == null;
    _byPages = p?.dailyPages != null;
    _dailyMinutes = p?.dailyMinutes ?? 30;
    _dailyPages = p?.dailyPages ?? 20;
    _weekdays =
        p != null ? parseWeekdays(p.weekdays) : {1, 2, 3, 4, 5, 6, 7};
    _minutesCtrl = TextEditingController(text: _dailyMinutes.toString());
    _pagesCtrl = TextEditingController(text: _dailyPages.toString());

    if (p == null) {
      // 新建排期：拿到全局默认设置后填充一次表单。
      ref.listenManual(settingsProvider, (_, next) {
        final s = next.valueOrNull;
        if (s == null || _seeded || !mounted) return;
        _seeded = true;
        setState(() {
          _dailyMinutes = s.defaultDailyMinutes;
          _dailyPages = max(1, (s.pagesPerHour * s.defaultDailyMinutes / 60).floor());
          _weekdays = parseWeekdays(s.defaultWeekdays);
          _minutesCtrl.text = '$_dailyMinutes';
          _pagesCtrl.text = '$_dailyPages';
        });
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _minutesCtrl.dispose();
    _pagesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bookAsync = ref.watch(bookProvider(widget.bookId));
    final settings = ref.watch(settingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(widget.plan == null ? '创建排期' : '调整排期')),
      bottomNavigationBar: const TimerBanner(),
      body: bookAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('出错了：$e')),
        data: (book) {
          if (book == null || settings == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _body(book, settings);
        },
      ),
    );
  }

  Widget _body(Book book, AppSetting settings) {
    final pace = effectivePace(book, settings);
    final result = buildSchedule(
      ScheduleInput(
        currentPage: book.currentPage,
        totalPages: book.totalPages,
        startDate: today(),
        deadline: _noDeadline ? null : _deadline,
        dailyMinutes: _dailyMinutes,
        dailyPages: _byPages ? _dailyPages : null,
        weekdays: _weekdays,
        pagesPerHour: pace,
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          book.title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          '剩余 ${book.totalPages - book.currentPage} 页 · '
          '阅读速度 $pace 页/小时（${_paceSource(book)}）',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 20),
        _label('排期方式'),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.schedule),
              label: Text('按时间'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.menu_book_outlined),
              label: Text('按页数'),
            ),
          ],
          selected: {_byPages},
          onSelectionChanged: (s) => setState(() => _byPages = s.first),
        ),
        const SizedBox(height: 20),
        if (_byPages) ...[
          _label('每天读多少页'),
          const SizedBox(height: 4),
          SliderField(
            value: _dailyPages,
            min: 1,
            max: 200,
            unit: '页',
            controller: _pagesCtrl,
            onValue: (n) => setState(() => _dailyPages = n),
          ),
          Text(
            '约 ${formatMinutes((_dailyPages / pace * 60).ceil())} / 天（按时长估算，仅供参考）',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ] else ...[
          _label('每天可投入时间'),
          const SizedBox(height: 4),
          SliderField(
            value: _dailyMinutes,
            min: 5,
            max: 240,
            unit: '分钟',
            controller: _minutesCtrl,
            onValue: (n) => setState(() => _dailyMinutes = n),
            format: formatMinutes,
          ),
        ],
        const SizedBox(height: 20),
        Card(
          child: SwitchListTile(
            value: _noDeadline,
            onChanged: (v) => setState(() => _noDeadline = v),
            title: const Text('不设截止日期'),
            subtitle: Text(_byPages
                ? '按每天的页数一直排，直到读完'
                : '按每天可投入的时间一直排，直到读完'),
          ),
        ),
        if (!_noDeadline) ...[
          const SizedBox(height: 12),
          _label('截止日期'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text(formatDate(_deadline)),
            trailing: TextButton(
              onPressed: _pickDeadline,
              child: const Text('选择'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _label('安排在这些天阅读'),
        const SizedBox(height: 8),
        _WeekdayPicker(
          selected: _weekdays,
          onChanged: (s) => setState(() => _weekdays = s),
        ),
        const SizedBox(height: 20),
        _PreviewCard(result: result),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _weekdays.isEmpty ? null : _save,
          icon: const Icon(Icons.check),
          label: const Text('保存排期'),
        ),
      ],
    );
  }

  String _paceSource(Book book) {
    if (book.manualPagesPerHour != null) return '手动设置';
    if (book.measuredPagesPerHour != null) return '自动学习';
    return '全局默认';
  }

  Widget _label(String text) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      );

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline.isBefore(today()) ? today() : _deadline,
      firstDate: today(),
      lastDate: DateTime(today().year + 3),
    );
    if (picked != null) setState(() => _deadline = dateOnly(picked));
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutesCtrl.text.trim());
    final pages = int.tryParse(_pagesCtrl.text.trim());
    if (_byPages && (pages == null || pages <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的每天页数')),
      );
      return;
    }
    if (!_byPages && (minutes == null || minutes <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的每天时长')),
      );
      return;
    }

    final repo = ref.read(repositoryProvider);
    final result = await repo.savePlan(
      bookId: widget.bookId,
      startDate: today(),
      deadline: _noDeadline ? null : _deadline,
      dailyMinutes: minutes ?? _dailyMinutes,
      dailyPages: _byPages ? pages : null,
      weekdays: _weekdays,
    );
    if (!mounted) return;
    if (result.oversubscribed) {
      final keep = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('排期偏紧'),
          content: Text(
            '按当前设置，到 ${formatDate(_deadline)} 仍剩约 '
            '${result.unassignedPages} 页读不完。\n\n'
            '可以先保存，之后再调整；或返回修改。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('仍然保存'),
            ),
          ],
        ),
      );
      if (keep != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  static const _names = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (var d = 1; d <= 7; d++)
          FilterChip(
            label: Text(_names[d - 1]),
            selected: selected.contains(d),
            onSelected: (on) {
              final next = {...selected};
              on ? next.add(d) : next.remove(d);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.result});
  final ScheduleResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = !result.oversubscribed;

    return Card(
      color: ok
          ? theme.colorScheme.surfaceContainerLow
          : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.check_circle_outline : Icons.error_outline,
                  color:
                      ok ? theme.colorScheme.primary : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(
                  ok ? '可以排下' : '期限内读不完',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ok ? null : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (result.remainingPages <= 0)
              const Text('这本书已经读完了。')
            else ...[
              _stat(context, '剩余页数', '${result.remainingPages} 页'),
              _stat(context, '每天读', '${result.pagesPerReadingDay} 页'),
              if (result.estimatedFinish != null)
                _stat(context, '预计读完',
                    '${formatDate(result.estimatedFinish!)}（${result.totalReadingDaysNeeded} 个阅读日）'),
              if (!ok && result.unassignedPages > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '还差约 ${result.unassignedPages} 页。建议延长截止日、提高每天页数，或调高阅读速度。',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
