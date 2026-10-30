import 'package:flutter/material.dart';

/// 打开标签选择弹窗。返回 null 表示取消，否则返回选中的标签集合。
Future<Set<String>?> showTagPickerSheet(
  BuildContext context, {
  required Iterable<String> allTags,
  required Set<String> selected,
  String title = '选择标签',
  bool allowCreate = false,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (_) => TagPickerSheet(
      allTags: allTags.toList()..sort(),
      initialSelected: selected,
      title: title,
      allowCreate: allowCreate,
    ),
  );
}

class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.allTags,
    required this.initialSelected,
    this.title = '选择标签',
    this.allowCreate = false,
  });

  final List<String> allTags;
  final Set<String> initialSelected;
  final String title;
  final bool allowCreate;

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  final _search = TextEditingController();
  late final Set<String> _tags;
  late final Set<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tags = {...widget.allTags, ...widget.initialSelected};
    _selected = {...widget.initialSelected};
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _createTag() {
    final tag = _query.trim().replaceAll(',', ' ');
    if (tag.isEmpty) return;
    setState(() {
      _tags.add(tag);
      _selected.add(tag);
      _query = '';
      _search.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final q = _query.trim().toLowerCase();
    final filtered =
        _tags.where((t) => q.isEmpty || t.toLowerCase().contains(q)).toList()
          ..sort();
    final canCreate =
        widget.allowCreate &&
        q.isNotEmpty &&
        !_tags.any((t) => t.toLowerCase() == q);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.66,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '已选 ${_selected.length} 个',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _search,
              autofocus: false,
              decoration: InputDecoration(
                hintText: widget.allowCreate ? '搜索或新建标签' : '搜索标签',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in filtered)
                      FilterChip(
                        label: Text('#$tag'),
                        selected: _selected.contains(tag),
                        onSelected: (on) => setState(() {
                          on ? _selected.add(tag) : _selected.remove(tag);
                        }),
                      ),
                    if (canCreate)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: Text('新建「${_query.trim()}」'),
                        onPressed: _createTag,
                      ),
                    if (filtered.isEmpty && !canCreate)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          q.isEmpty ? '还没有标签' : '没有匹配的标签',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => setState(_selected.clear),
                  child: const Text('清除'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('完成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
