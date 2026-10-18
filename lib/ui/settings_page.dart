import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installed_apps/installed_apps.dart';

import '../core/date_x.dart';
import '../data/backup.dart';
import '../data/repository.dart';
import '../services/target_app_service.dart';
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

  Future<void> _pickTargetApp() async {
    final selected = await showModalBottomSheet<AppInfo>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const _AppPickerSheet(),
    );
    if (selected == null) return;
    await ref
        .read(repositoryProvider)
        .updateAutoOpenApp(
          enabled: true,
          packageName: selected.packageName,
          appName: selected.name,
        );
  }

  Future<void> _exportData() async {
    try {
      final json = await BackupService(ref.read(databaseProvider)).exportJson();
      final fileName = 'reader-backup-${formatDate(DateTime.now())}.json';
      final path = await FilePicker.saveFile(
        dialogTitle: '导出阅历数据',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(json)),
      );
      if (!mounted) return;
      if (!kIsWeb && path == null) return; // 用户取消了保存。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kIsWeb || path == null ? '已开始下载备份文件' : '数据已导出到 $path'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _importData() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择阅历备份文件',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据？'),
        content: Text(
          '将用备份文件覆盖当前全部阅读数据（读物、计划、任务、计时记录和设置），'
          '且无法撤销。\n\n文件：${picked.files.single.name}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('覆盖并导入'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final file = picked.files.single;
      final bytes = file.bytes ?? await file.xFile.readAsBytes();
      final summary = await BackupService(
        ref.read(databaseProvider),
      ).importJson(utf8.decode(bytes));
      if (!mounted) return;
      // 导入的设置要立刻反映到本页表单，避免随后保存时又把旧值写回去。
      final restored = await ref.read(databaseProvider).loadSettings();
      if (!mounted) return;
      setState(() {
        _seeded = true;
        _pace.text = restored.pagesPerHour.toString();
        _dailyMinutes = restored.defaultDailyMinutes;
        _minutes.text = '$_dailyMinutes';
        _weekdays = parseWeekdays(restored.defaultWeekdays);
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入完成'),
          content: Text('已恢复：$summary'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入失败'),
          content: Text(e is BackupFormatException ? e.message : '$e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _save() async {
    final pace = int.tryParse(_pace.text.trim());
    if (pace == null || pace <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('阅读速度需要是正整数')));
      return;
    }
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('每天时长需要是正整数')));
      return;
    }
    await ref
        .read(repositoryProvider)
        .updateSettings(
          pagesPerHour: pace,
          defaultDailyMinutes: minutes,
          defaultWeekdays: encodeWeekdays(_weekdays),
        );
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已保存，所有进行中的排期已重算')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSettings = ref.watch(settingsProvider).valueOrNull;
    final autoOpen = currentSettings?.autoOpenApp ?? false;
    final selectedName = currentSettings?.autoOpenAppName;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      bottomNavigationBar: const TimerBanner(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '阅读速度',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
          const SizedBox(height: 24),
          Text(
            '计时时自动打开应用',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '仅安卓：开始计时时自动打开指定的阅读应用。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: autoOpen,
            onChanged: TargetAppService.isAndroid
                ? (v) =>
                      ref.read(repositoryProvider).updateAutoOpenApp(enabled: v)
                : null,
            title: const Text('自动打开'),
            subtitle: Text(
              selectedName == null || selectedName.isEmpty
                  ? '未选择应用'
                  : selectedName,
            ),
          ),
          if (autoOpen)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: TargetAppService.isAndroid ? _pickTargetApp : null,
                icon: const Icon(Icons.apps),
                label: const Text('选择应用'),
              ),
            ),
          const SizedBox(height: 32),
          Text(
            '数据备份',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '导出会生成一个 JSON 备份文件，包含所有读物、计划、任务、计时记录与设置。'
            '导入会用备份覆盖当前数据。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _exportData,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('导出数据'),
              ),
              OutlinedButton.icon(
                onPressed: _importData,
                icon: const Icon(Icons.download_outlined),
                label: const Text('导入数据'),
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

/// 已安装应用选择器（带搜索与加载动画）。
class _AppPickerSheet extends StatefulWidget {
  const _AppPickerSheet();

  @override
  State<_AppPickerSheet> createState() => _AppPickerSheetState();
}

class _AppPickerSheetState extends State<_AppPickerSheet> {
  final _search = TextEditingController();
  String _query = '';
  List<AppInfo>? _apps;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await TargetAppService.installedApps();
    if (!mounted) return;
    setState(() => _apps = apps);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apps = _apps;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: apps == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在读取已安装应用…'),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: '搜索应用',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) =>
                        setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final filtered = _query.isEmpty
                          ? apps
                          : apps
                                .where(
                                  (a) => a.name.toLowerCase().contains(_query),
                                )
                                .toList();
                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(apps.isEmpty ? '没有找到可启动的应用' : '没有匹配的应用'),
                        );
                      }
                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final app = filtered[i];
                          return ListTile(
                            leading: SizedBox(
                              width: 36,
                              height: 36,
                              child: app.icon == null
                                  ? const Icon(Icons.android)
                                  : Image.memory(
                                      app.icon!,
                                      fit: BoxFit.contain,
                                    ),
                            ),
                            title: Text(app.name),
                            subtitle: Text(
                              app.packageName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => Navigator.pop(context, app),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
