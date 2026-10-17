import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_x.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'widgets/slider_field.dart';
import 'widgets/timer_banner.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _pace = TextEditingController(text: '30');
  final _minutes = TextEditingController(text: '30');
  int _dailyMinutes = 30;
  Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(settingsProvider, (_, next) {
      final s = next.valueOrNull;
      if (s == null || _seeded || !mounted) return;
      _seeded = true;
      setState(() {
        _pace.text = s.pagesPerHour.toString();
        _dailyMinutes = s.defaultDailyMinutes;
        _minutes.text = '$_dailyMinutes';
        _weekdays = parseWeekdays(s.defaultWeekdays);
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _pace.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pace = int.tryParse(_pace.text.trim());
    if (pace == null || pace <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('阅读速度需要是正整数')),
      );
      return;
    }
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('每天时长需要是正整数')),
      );
      return;
    }
    await ref.read(repositoryProvider).updateSettings(
          pagesPerHour: pace,
          defaultDailyMinutes: minutes,
          defaultWeekdays: encodeWeekdays(_weekdays),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存，所有进行中的排期已重算')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      bottomNavigationBar: const TimerBanner(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '阅读速度',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '用于把页数换算成时间。读了几次后可以回来微调，排期会立即重算。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pace,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '每小时的阅读页数',
              suffixText: '页/小时',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '默认每天时长',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          SliderField(
            value: _dailyMinutes,
            min: 5,
            max: 240,
            unit: '分钟',
            controller: _minutes,
            onValue: (n) => setState(() => _dailyMinutes = n),
            format: formatMinutes,
          ),
          const SizedBox(height: 24),
          Text(
            '默认阅读日',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(const ['一', '二', '三', '四', '五', '六', '日'][d - 1]),
                  selected: _weekdays.contains(d),
                  onSelected: (on) {
                    setState(() {
                      on ? _weekdays.add(d) : _weekdays.remove(d);
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存设置'),
          ),
        ],
      ),
    );
  }
}
