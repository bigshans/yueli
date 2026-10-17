import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'book_detail_page.dart';
import 'widgets/timer_banner.dart';

class BookFormPage extends ConsumerStatefulWidget {
  const BookFormPage({super.key, this.book});
  final Book? book;

  @override
  ConsumerState<BookFormPage> createState() => _BookFormPageState();
}

class _BookFormPageState extends ConsumerState<BookFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _author;
  late final TextEditingController _total;
  late final TextEditingController _current;
  late final TextEditingController _pace;
  late final TextEditingController _tags;
  int _priority = 2;

  bool get _isEdit => widget.book != null;

  @override
  void initState() {
    super.initState();
    final b = widget.book;
    _title = TextEditingController(text: b?.title ?? '');
    _author = TextEditingController(text: b?.author ?? '');
    _total = TextEditingController(text: b?.totalPages.toString() ?? '');
    _current = TextEditingController(text: b?.currentPage.toString() ?? '0');
    _pace = TextEditingController(
      text: b?.manualPagesPerHour?.toString() ?? '',
    );
    _tags = TextEditingController(text: b?.tags ?? '');
    _priority = b?.priority ?? 2;
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _total.dispose();
    _current.dispose();
    _pace.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(repositoryProvider);
    final title = _title.text.trim();
    final author = _author.text.trim();
    final total = int.parse(_total.text.trim());
    final current = int.tryParse(_current.text.trim()) ?? 0;
    final pace = int.tryParse(_pace.text.trim());
    final tagsText = encodeTags(parseTags(_tags.text));
    final tags = tagsText.isEmpty ? null : tagsText;

    if (_isEdit) {
      await repo.updateBook(
        widget.book!.id,
        BooksCompanion(
          title: Value(title),
          author: Value(author.isEmpty ? null : author),
          totalPages: Value(total),
          currentPage: Value(current.clamp(0, total)),
          priority: Value(_priority),
          manualPagesPerHour: Value(pace),
          tags: Value(tags),
        ),
      );
      final plan = await repo.getPlanForBook(widget.book!.id);
      if (plan != null) await repo.reschedulePlan(plan.id);
      if (mounted) Navigator.of(context).pop();      return;
    }

    final id = await repo.createBook(
      title: title,
      author: author.isEmpty ? null : author,
      totalPages: total,
      currentPage: current.clamp(0, total),
      priority: _priority,
      manualPagesPerHour: pace,
      tags: tags,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => BookDetailPage(bookId: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑读物' : '添加读物'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      bottomNavigationBar: const TimerBanner(),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '书名',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写书名' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _author,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '作者（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tags,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '标签（可选，用逗号分隔）',
                hintText: '如：技术, 心理学',
                prefixIcon: Icon(Icons.local_offer_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _total,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '总页数',
                      suffixText: '页',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final n = int.tryParse(v?.trim() ?? '');
                      if (n == null || n <= 0) return '请输入有效页数';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _current,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '已读',
                      suffixText: '页',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _pace,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '阅读速度（可选）',
                helperText: '页/小时。留空则用计时数据自动学习，或用全局默认',
                suffixText: '页/小时',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('优先级', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('高')),
                ButtonSegment(value: 2, label: Text('中')),
                ButtonSegment(value: 3, label: Text('低')),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(_isEdit ? '保存修改' : '保存并设置排期'),
            ),
          ],
        ),
      ),
    );
  }
}
