import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:installed_apps/installed_apps.dart';

import '../core/date_x.dart';
import '../data/backup.dart';
import '../data/repository.dart';
import '../services/target_app_service.dart';
import '../services/weread/weread_client.dart';
import '../state/providers.dart';
import 'weread_import_page.dart';
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
  int _settlementMinutes = 0;
  bool _seeded = false;
  final _wereadKey = TextEditingController();
  bool _wereadKeyVisible = false;
  bool _wereadBusy = false;
  bool _wereadAutoBindBusy = false;
  bool _wereadSyncBusy = false;
  bool _hasWereadKey = false;
  String? _wereadStatus;
  bool _wereadStatusOk = false;

  @override
  void initState() {
    super.initState();
    _loadWereadKey();
    ref.listenManual(settingsProvider, (_, next) {
      final s = next.valueOrNull;
      if (s == null || _seeded || !mounted) return;
      _seeded = true;
      setState(() {
        _pace.text = s.pagesPerHour.toString();
        _dailyMinutes = s.defaultDailyMinutes;
        _minutes.text = '$_dailyMinutes';
        _weekdays = parseWeekdays(s.defaultWeekdays);
        _settlementMinutes = s.settlementMinutes;
      });
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _pace.dispose();
    _minutes.dispose();
    _wereadKey.dispose();
    super.dispose();
  }

  Future<void> _loadWereadKey() async {
    try {
      final key = await ref.read(wereadCredentialsProvider).readApiKey();
      if (!mounted) return;
      setState(() {
        _wereadKey.text = key ?? '';
        _hasWereadKey = key != null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = '读取安全存储失败：$e';
        _wereadStatusOk = false;
      });
    }
  }

  Future<void> _saveWereadKey() async {
    final key = _wereadKey.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写微信读书 API Key')));
      return;
    }
    setState(() {
      _wereadBusy = true;
      _wereadStatus = null;
    });
    try {
      final summary = await ref.read(wereadClientProvider).validateApiKey(key);
      await ref.read(wereadCredentialsProvider).saveApiKey(key);
      if (!mounted) return;
      setState(() {
        _hasWereadKey = true;
        _wereadStatus =
            '已连接 · 书架 ${summary.totalCount} 个条目'
            '（电子书 ${summary.bookCount}，有声书 ${summary.albumCount}'
            '${summary.hasMp ? '，文章收藏 1' : ''}）';
        _wereadStatusOk = true;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('微信读书连接成功')));
    } on WereadException catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = e.message;
        _wereadStatusOk = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = '验证失败：$e';
        _wereadStatusOk = false;
      });
    } finally {
      if (mounted) setState(() => _wereadBusy = false);
    }
  }

  Future<void> _autoBindWeread() async {
    setState(() {
      _wereadAutoBindBusy = true;
      _wereadStatus = '正在扫描同名书籍…';
      _wereadStatusOk = true;
    });
    try {
      final result = await ref
          .read(wereadImportServiceProvider)
          .autoBindExistingBooks(
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                _wereadStatus = total == 0
                    ? '正在扫描同名书籍…'
                    : '正在自动绑定 $done / $total…';
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _wereadStatus = result.bound > 0
            ? '已自动绑定 ${result.bound} 本'
            : '没有找到可自动绑定的同名书籍';
        _wereadStatusOk = result.bound > 0;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('自动绑定完成'),
          content: Text(
            [
              if (result.bound > 0) '已绑定 ${result.bound} 本。',
              if (result.ambiguous > 0) '${result.ambiguous} 本同名但无法唯一确定，已跳过。',
              if (result.failed > 0) '${result.failed} 本绑定失败：',
              if (result.failed > 0) ...result.errors.take(5),
              if (result.bound == 0 &&
                  result.ambiguous == 0 &&
                  result.failed == 0)
                '没有找到书名和作者都匹配的微信读书书籍。',
            ].join('\n'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } on WereadException catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = e.message;
        _wereadStatusOk = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = '自动绑定失败：$e';
        _wereadStatusOk = false;
      });
    } finally {
      if (mounted) setState(() => _wereadAutoBindBusy = false);
    }
  }

  Future<void> _syncWereadAll() async {
    setState(() {
      _wereadSyncBusy = true;
      _wereadStatus = '正在同步微信读书进度…';
      _wereadStatusOk = true;
    });
    try {
      final result = await ref
          .read(wereadSyncServiceProvider)
          .syncAll(
            onProgress: (done, total) {
              if (!mounted) return;
              setState(() {
                _wereadStatus = total == 0
                    ? '没有已绑定的微信读书书籍'
                    : '正在同步 $done / $total…';
              });
            },
          );
      if (!mounted) return;
      setState(() {
        _wereadStatus = result.changed > 0
            ? '已同步 ${result.changed} 本'
            : '已检查 ${result.kept} 本，进度无需更新';
        _wereadStatusOk = result.failed == 0;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('同步完成'),
          content: Text(
            [
              if (result.changed > 0) '更新 ${result.changed} 本。',
              if (result.finished > 0) '其中 ${result.finished} 本同步为读完。',
              if (result.kept > 0) '${result.kept} 本无需更新。',
              if (result.failed > 0) '${result.failed} 本同步失败：',
              if (result.failed > 0) ...result.errors.take(5),
              if (result.changed == 0 && result.kept == 0 && result.failed == 0)
                '还没有绑定任何微信读书书籍。',
              if (result.kept > 0 || result.changed > 0)
                '\n同步只记录微信读书百分比和读完状态，不会自动按比例修改本地页码。',
            ].join('\n'),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('好'),
            ),
          ],
        ),
      );
    } on WereadException catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = e.message;
        _wereadStatusOk = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = '同步失败：$e';
        _wereadStatusOk = false;
      });
    } finally {
      if (mounted) setState(() => _wereadSyncBusy = false);
    }
  }

  Future<void> _clearWereadKey() async {
    setState(() => _wereadBusy = true);
    try {
      await ref.read(wereadCredentialsProvider).clearApiKey();
      if (!mounted) return;
      setState(() {
        _wereadKey.clear();
        _hasWereadKey = false;
        _wereadStatus = '已清除微信读书授权';
        _wereadStatusOk = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _wereadStatus = '清除失败：$e';
        _wereadStatusOk = false;
      });
    } finally {
      if (mounted) setState(() => _wereadBusy = false);
    }
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
      String? savedKey;
      try {
        savedKey = await ref.read(wereadCredentialsProvider).readApiKey();
      } catch (_) {
        // 安全存储不可用时仍然可以导出其他数据。
      }
      if (!mounted) return;

      var includeWereadKey = false;
      if (savedKey != null && savedKey.isNotEmpty) {
        final choice = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导出完整备份'),
            content: const Text(
              '备份会包含书籍、计划、任务、计时记录、阅读轮次、休息日、'
              '设置、微信读书关联和本地封面。\n\n'
              '是否同时包含微信读书 API Key？'
              '包含后恢复备份即可继续使用微信读书，但 Key 会以明文形式保存在 ZIP 中。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('不包含 Key'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('包含 Key'),
              ),
            ],
          ),
        );
        if (choice == null) return;
        includeWereadKey = choice;
      }

      final bytes = await BackupService(
        ref.read(databaseProvider),
      ).exportArchiveBytes(wereadApiKey: includeWereadKey ? savedKey : null);
      final fileName = 'yueli-backup-${formatDate(DateTime.now())}.zip';
      final path = await FilePicker.saveFile(
        dialogTitle: '导出阅历数据',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (!kIsWeb && path == null) return; // 用户取消了保存。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb || path == null
                ? includeWereadKey
                      ? '已开始下载完整备份（含历史 CSV 和微信读书 Key）'
                      : '已开始下载完整备份（含历史 CSV）'
                : includeWereadKey
                ? '数据已导出到 $path（含微信读书 Key）'
                : '数据已导出到 $path',
          ),
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
      allowedExtensions: const ['zip', 'json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入数据？'),
        content: Text(
          '将用备份文件覆盖当前全部阅读数据（读物、计划、任务、计时记录、设置和微信读书关联），'
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
      ).importBytes(bytes, fileName: file.name);
      if (!mounted) return;

      String? keyWarning;
      if (summary.wereadApiKey != null && summary.wereadApiKey!.isNotEmpty) {
        try {
          await ref
              .read(wereadCredentialsProvider)
              .saveApiKey(summary.wereadApiKey!);
          if (!mounted) return;
          setState(() {
            _wereadKey.text = summary.wereadApiKey!;
            _hasWereadKey = true;
            _wereadStatus = '已从备份恢复微信读书授权';
            _wereadStatusOk = true;
          });
        } catch (e) {
          keyWarning = '微信读书 API Key 恢复失败：$e';
        }
      }

      // 导入的设置要立刻反映到本页表单，避免随后保存时又把旧值写回去。
      final restored = await ref.read(databaseProvider).loadSettings();
      if (!mounted) return;
      setState(() {
        _seeded = true;
        _pace.text = restored.pagesPerHour.toString();
        _dailyMinutes = restored.defaultDailyMinutes;
        _minutes.text = '$_dailyMinutes';
        _weekdays = parseWeekdays(restored.defaultWeekdays);
        _settlementMinutes = restored.settlementMinutes;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导入完成'),
          content: Text(
            keyWarning == null ? '已恢复：$summary' : '已恢复：$summary\n\n$keyWarning',
          ),
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

  Future<void> _pickSettlementTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settlementMinutes ~/ 60,
        minute: _settlementMinutes % 60,
      ),
      helpText: '选择每日结算时间',
    );
    if (picked != null && mounted) {
      setState(() {
        _settlementMinutes = picked.hour * 60 + picked.minute;
      });
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
          settlementMinutes: _settlementMinutes,
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
            '每日结算时间',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '每天到这个时间才开始新的一天。例如设为 04:00，'
            '凌晨 04:00 前的阅读和任务仍算前一天。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(formatSettlementTime(_settlementMinutes)),
            subtitle: const Text('点击修改'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickSettlementTime,
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
            '仅安卓：开始计时时自动打开阅读应用。'
            '已绑定微信读书的书会优先打开对应书籍页面；'
            '未绑定时打开下面选择的兜底应用。',
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
            '微信读书',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '通过微信读书官方 Agent API Gateway 连接账号，用于导入书架和同步阅读进度。'
            'API Key 只保存在本机安全存储中，不写入备份。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wereadKey,
            obscureText: !_wereadKeyVisible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'wrk-...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _wereadKeyVisible ? '隐藏' : '显示',
                onPressed: () =>
                    setState(() => _wereadKeyVisible = !_wereadKeyVisible),
                icon: Icon(
                  _wereadKeyVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _wereadBusy ? null : _saveWereadKey,
                icon: _wereadBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_wereadBusy ? '验证中…' : '保存并验证'),
              ),
              if (_hasWereadKey)
                OutlinedButton.icon(
                  onPressed: _wereadBusy ? null : _clearWereadKey,
                  icon: const Icon(Icons.link_off),
                  label: const Text('清除授权'),
                ),
            ],
          ),
          if (_wereadStatus != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _wereadStatusOk
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  size: 18,
                  color: _wereadStatusOk
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _wereadStatus!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _wereadStatusOk
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SelectableText(
            '获取 API Key：weread.qq.com/r/weread-skills',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_hasWereadKey) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _wereadBusy || _wereadAutoBindBusy || _wereadSyncBusy
                      ? null
                      : _autoBindWeread,
                  icon: _wereadAutoBindBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  label: Text(_wereadAutoBindBusy ? '自动绑定中…' : '自动绑定同名书籍'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _wereadBusy || _wereadAutoBindBusy || _wereadSyncBusy
                      ? null
                      : _syncWereadAll,
                  icon: _wereadSyncBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_wereadSyncBusy ? '同步中…' : '同步全部进度'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _wereadBusy || _wereadAutoBindBusy || _wereadSyncBusy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const WereadImportPage(),
                          ),
                        ),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('从微信读书导入书籍'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          Text(
            '数据备份',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '一次导出会生成 ZIP：包含完整书籍、计划、任务、计时记录、'
            '阅读轮次、休息日、设置、微信读书关联、本地封面和历史 CSV。'
            '可选择是否包含微信读书 API Key；导入时选择 ZIP 或旧版 JSON 即可。',
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
                label: const Text('导出完整备份'),
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
