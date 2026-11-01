import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/book_status.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../services/cover_storage.dart';
import '../state/providers.dart';
import 'book_detail_page.dart';
import 'widgets/book_cover.dart';
import 'widgets/tag_picker_sheet.dart';
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
  late final TextEditingController _coverUrl;
  late final TextEditingController _description;
  late final TextEditingController _translator;
  late final TextEditingController _publisher;
  late final TextEditingController _publishDate;
  late final TextEditingController _isbn;
  late final TextEditingController _wordCount;
  late final TextEditingController _rating;
  late final TextEditingController _ratingCount;
  final _selectedTags = <String>{};
  int _priority = 2;
  String _status = BookStatus.reading;
  String? _coverPath;
  late final String? _originalCoverPath;

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
    _coverUrl = TextEditingController(text: b?.coverUrl ?? '');
    _coverPath = b?.coverPath;
    _originalCoverPath = b?.coverPath;
    _description = TextEditingController(text: b?.description ?? '');
    _translator = TextEditingController(text: b?.translator ?? '');
    _publisher = TextEditingController(text: b?.publisher ?? '');
    _publishDate = TextEditingController(text: b?.publishDate ?? '');
    _isbn = TextEditingController(text: b?.isbn ?? '');
    _wordCount = TextEditingController(text: b?.wordCount?.toString() ?? '');
    _rating = TextEditingController(text: b?.rating?.toString() ?? '');
    _ratingCount = TextEditingController(
      text: b?.ratingCount?.toString() ?? '',
    );
    _selectedTags.addAll(parseTags(b?.tags));
    _priority = b?.priority ?? 2;
    _status = b?.status ?? BookStatus.reading;
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _total.dispose();
    _current.dispose();
    _pace.dispose();
    _coverUrl.dispose();
    _description.dispose();
    _translator.dispose();
    _publisher.dispose();
    _publishDate.dispose();
    _isbn.dispose();
    _wordCount.dispose();
    _rating.dispose();
    _ratingCount.dispose();
    super.dispose();
  }

  String? _textOrNull(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  int? _intOrNull(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  double? _doubleOrNull(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  bool get _hasMetadataInput =>
      _textOrNull(_coverUrl) != null ||
      (_coverPath != null && _coverPath!.isNotEmpty) ||
      _textOrNull(_description) != null ||
      _textOrNull(_translator) != null ||
      _textOrNull(_publisher) != null ||
      _textOrNull(_publishDate) != null ||
      _textOrNull(_isbn) != null ||
      _intOrNull(_wordCount) != null ||
      _doubleOrNull(_rating) != null ||
      _intOrNull(_ratingCount) != null;

  Future<void> _pickCover() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes ?? await file.xFile.readAsBytes();
    final path = await saveCoverFile(bytes, file.name);
    if (!mounted || path == null) return;
    final previous = _coverPath;
    if (previous != null &&
        previous.isNotEmpty &&
        previous != _originalCoverPath) {
      await deleteCoverFile(previous);
    }
    setState(() => _coverPath = path);
  }

  Future<void> _clearCover() async {
    final previous = _coverPath;
    if (previous != null &&
        previous.isNotEmpty &&
        previous != _originalCoverPath) {
      await deleteCoverFile(previous);
    }
    if (mounted) setState(() => _coverPath = null);
  }

  String? _ratingValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final rating = double.tryParse(text);
    if (rating == null || rating < 0 || rating > 10) {
      return '评分需要在 0–10 之间';
    }
    return null;
  }

  String? _nonNegativeIntValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final number = int.tryParse(text);
    if (number == null || number < 0) return '请输入非负整数';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(repositoryProvider);
    final title = _title.text.trim();
    final author = _author.text.trim();
    final total = int.parse(_total.text.trim());
    final current = int.tryParse(_current.text.trim()) ?? 0;
    final pace = int.tryParse(_pace.text.trim());
    final tagsText = encodeTags(_selectedTags);
    final tags = tagsText.isEmpty ? null : tagsText;
    final effectiveCurrent = _status == BookStatus.finished
        ? total
        : current.clamp(0, total);
    final coverUrl = _textOrNull(_coverUrl);
    final coverPath = (_coverPath == null || _coverPath!.trim().isEmpty)
        ? null
        : _coverPath;
    final description = _textOrNull(_description);
    final translator = _textOrNull(_translator);
    final publisher = _textOrNull(_publisher);
    final publishDate = _textOrNull(_publishDate);
    final isbn = _textOrNull(_isbn);
    final wordCount = _intOrNull(_wordCount);
    final rating = _doubleOrNull(_rating);
    final ratingCount = _intOrNull(_ratingCount);

    if (_isEdit) {
      await repo.updateBook(
        widget.book!.id,
        BooksCompanion(
          title: Value(title),
          author: Value(author.isEmpty ? null : author),
          totalPages: Value(total),
          currentPage: Value(effectiveCurrent),
          priority: Value(_priority),
          manualPagesPerHour: Value(pace),
          tags: Value(tags),
          status: Value(_status),
          coverUrl: Value(coverUrl),
          coverPath: Value(coverPath),
          description: Value(description),
          translator: Value(translator),
          publisher: Value(publisher),
          publishDate: Value(publishDate),
          isbn: Value(isbn),
          wordCount: Value(wordCount),
          rating: Value(rating),
          ratingCount: Value(ratingCount),
          metadataSource: Value(widget.book!.metadataSource),
          metadataUpdatedAt: Value(
            _hasMetadataInput ? DateTime.now() : widget.book!.metadataUpdatedAt,
          ),
        ),
      );
      if (coverPath != _originalCoverPath) {
        await deleteCoverFile(_originalCoverPath);
      }
      final plan = await repo.getPlanForBook(widget.book!.id);
      if (plan != null) await repo.reschedulePlan(plan.id);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final id = await repo.createBook(
      title: title,
      author: author.isEmpty ? null : author,
      totalPages: total,
      currentPage: effectiveCurrent,
      priority: _priority,
      manualPagesPerHour: pace,
      tags: tags,
      status: _status,
      coverUrl: coverUrl,
      coverPath: coverPath,
      description: description,
      translator: translator,
      publisher: publisher,
      publishDate: publishDate,
      isbn: isbn,
      wordCount: wordCount,
      rating: rating,
      ratingCount: ratingCount,
      metadataSource: 'manual',
      metadataUpdatedAt: _hasMetadataInput ? DateTime.now() : null,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => BookDetailPage(bookId: id)),
    );
  }

  Future<void> _pickTags(List<String> allTags) async {
    final picked = await showTagPickerSheet(
      context,
      allTags: allTags,
      selected: _selectedTags,
      title: '选择标签',
      allowCreate: true,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTags
          ..clear()
          ..addAll(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allTags = <String>{
      for (final b in ref.watch(booksProvider).valueOrNull ?? const <Book>[])
        ...parseTags(b.tags),
      ..._selectedTags,
    }.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑读物' : '添加读物'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
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
            Text('标签', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            if (_selectedTags.isEmpty)
              Text(
                '未选择标签',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final tag in _selectedTags)
                    InputChip(
                      label: Text('#$tag'),
                      onDeleted: () =>
                          setState(() => _selectedTags.remove(tag)),
                    ),
                ],
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _pickTags(allTags),
              icon: const Icon(Icons.local_offer_outlined, size: 18),
              label: const Text('选择标签'),
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
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                title: const Text('更多信息'),
                subtitle: const Text('封面、简介、出版信息等，均可留空'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CoverImage(
                        coverPath: _coverPath,
                        coverUrl: _coverUrl.text,
                        title: _title.text,
                        width: 64,
                        height: 90,
                        borderRadius: 8,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _coverUrl,
                              keyboardType: TextInputType.url,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: '封面链接（可选）',
                                hintText: 'https://...',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickCover,
                                  icon: const Icon(
                                    Icons.upload_file_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('上传封面'),
                                ),
                                if (_coverPath != null &&
                                    _coverPath!.isNotEmpty)
                                  TextButton(
                                    onPressed: _clearCover,
                                    child: const Text('清除上传封面'),
                                  ),
                              ],
                            ),
                            Text(
                              '上传优先于链接；都不填时显示首字占位图。',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: '简介（可选）',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _translator,
                          decoration: const InputDecoration(
                            labelText: '译者（可选）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _wordCount,
                          keyboardType: TextInputType.number,
                          validator: _nonNegativeIntValidator,
                          decoration: const InputDecoration(
                            labelText: '字数（可选）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _publisher,
                    decoration: const InputDecoration(
                      labelText: '出版社（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _publishDate,
                          decoration: const InputDecoration(
                            labelText: '出版时间（可选）',
                            hintText: '2024-05',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _isbn,
                          decoration: const InputDecoration(
                            labelText: 'ISBN（可选）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _rating,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: _ratingValidator,
                          decoration: const InputDecoration(
                            labelText: '评分（可选）',
                            hintText: '0–10',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _ratingCount,
                          keyboardType: TextInputType.number,
                          validator: _nonNegativeIntValidator,
                          decoration: const InputDecoration(
                            labelText: '评分人数（可选）',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('阅读状态', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final status in BookStatus.all)
                  ChoiceChip(
                    label: Text(BookStatus.label(status)),
                    selected: _status == status,
                    onSelected: (_) => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '读满总页数后会自动标记为「已读」；如果调低进度或撤销任务，会自动回到「在读」。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
