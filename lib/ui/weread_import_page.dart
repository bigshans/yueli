import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format_x.dart';
import '../data/database.dart';
import '../services/weread/weread_client.dart';
import '../services/weread/weread_import_service.dart';
import '../state/providers.dart';
import 'widgets/book_cover.dart';

enum _ShelfFilter { all, unfinished, finished }

class WereadImportPage extends ConsumerStatefulWidget {
  const WereadImportPage({super.key});

  @override
  ConsumerState<WereadImportPage> createState() => _WereadImportPageState();
}

class _WereadImportPageState extends ConsumerState<WereadImportPage> {
  final _search = TextEditingController();
  final _selected = <String>{};
  List<WereadShelfBook> _books = const [];
  List<Book> _localBooks = const [];
  Set<String> _linkedIds = const {};
  Set<int> _linkedLocalIds = const {};
  bool _loading = true;
  bool _importing = false;
  bool _addWereadTag = true;
  int _importDone = 0;
  String? _error;
  String _query = '';
  _ShelfFilter _filter = _ShelfFilter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shelf = await ref.read(wereadImportServiceProvider).fetchShelf();
      final links = await ref.read(repositoryProvider).allWereadLinks();
      final localBooks = await ref.read(repositoryProvider).allBooks();
      shelf.sort((a, b) {
        final at = a.readUpdateTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.readUpdateTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      if (!mounted) return;
      setState(() {
        _books = shelf;
        _localBooks = localBooks;
        _linkedIds = links.map((e) => e.wereadBookId).toSet();
        _linkedLocalIds = links.map((e) => e.bookId).toSet();
      });
    } on WereadException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载微信读书书架失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isFinished(WereadShelfBook book) => book.finishReading;

  List<Book> _localCandidates(WereadShelfBook book) {
    final title = normalizeWereadTitle(book.title);
    if (title.isEmpty) return const [];
    final author = normalizeWereadAuthor(book.author);
    return _localBooks.where((local) {
      if (normalizeWereadTitle(local.title) != title) return false;
      final localAuthor = normalizeWereadAuthor(local.author);
      if (author.isEmpty || localAuthor.isEmpty) return true;
      return author == localAuthor;
    }).toList();
  }

  Book? _matchedLocal(WereadShelfBook book) {
    final candidates = _localCandidates(book);
    return candidates.length == 1 ? candidates.single : null;
  }

  Book? _bindableLocal(WereadShelfBook book) {
    final matched = _matchedLocal(book);
    if (matched == null || _linkedLocalIds.contains(matched.id)) return null;
    return matched;
  }

  bool _isDisabled(WereadShelfBook book) {
    if (_linkedIds.contains(book.bookId)) return true;
    if (_localCandidates(book).length > 1) return true;
    final matched = _matchedLocal(book);
    if (matched != null && _linkedLocalIds.contains(matched.id)) return true;
    return false;
  }

  String? _bindingLabel(WereadShelfBook book) {
    if (_linkedIds.contains(book.bookId)) return '已导入';
    if (_bindableLocal(book) != null) return '绑定已有';
    if (_localCandidates(book).length > 1) return '可能重复';
    final matched = _matchedLocal(book);
    if (matched != null && _linkedLocalIds.contains(matched.id)) {
      return '本地已绑定';
    }
    return null;
  }

  List<WereadShelfBook> get _filtered {
    final query = _query.trim().toLowerCase();
    return _books.where((book) {
      if (_filter == _ShelfFilter.finished && !_isFinished(book)) return false;
      if (_filter == _ShelfFilter.unfinished && _isFinished(book)) return false;
      if (query.isNotEmpty) {
        final title = book.title.toLowerCase();
        final author = (book.author ?? '').toLowerCase();
        if (!title.contains(query) && !author.contains(query)) return false;
      }
      return true;
    }).toList();
  }

  void _toggle(WereadShelfBook book) {
    if (_importing || _isDisabled(book)) return;
    setState(() {
      if (!_selected.remove(book.bookId)) _selected.add(book.bookId);
    });
  }

  void _selectAllVisible(bool selected) {
    if (_importing) return;
    setState(() {
      for (final book in _filtered) {
        if (_isDisabled(book)) continue;
        selected ? _selected.add(book.bookId) : _selected.remove(book.bookId);
      }
    });
  }

  Future<void> _importSelected() async {
    final selectedBooks = _books
        .where((book) => _selected.contains(book.bookId))
        .toList();
    if (selectedBooks.isEmpty) return;

    setState(() {
      _importing = true;
      _importDone = 0;
    });
    final errors = <String>[];
    var success = 0;
    final service = ref.read(wereadImportServiceProvider);

    for (final book in selectedBooks) {
      try {
        final existing = _bindableLocal(book);
        if (existing != null) {
          await service.bindExistingBook(bookId: existing.id, shelfBook: book);
        } else {
          final preview = await service.prepare(book);
          await service.importPreview(preview, addWereadTag: _addWereadTag);
        }
        success++;
      } catch (e) {
        errors.add('《${book.title}》：$e');
      }
      if (mounted) setState(() => _importDone++);
    }

    if (!mounted) return;
    setState(() => _importing = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入完成'),
        content: Text(
          [
            '成功导入 $success 本。',
            if (errors.isNotEmpty) ...['', '失败 ${errors.length} 本：', ...errors],
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
    if (success > 0 && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    final selectable = filtered.where((book) => !_isDisabled(book)).toList();
    final allSelected =
        selectable.isNotEmpty &&
        selectable.every((book) => _selected.contains(book.bookId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('从微信读书导入'),
        actions: [
          if (!_loading && _error == null)
            PopupMenuButton<String>(
              tooltip: '批量选择',
              onSelected: (value) => _selectAllVisible(value == 'all'),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'all',
                  enabled: !allSelected && selectable.isNotEmpty,
                  child: const Text('全选当前列表'),
                ),
                PopupMenuItem(
                  value: 'none',
                  enabled: _selected.isNotEmpty,
                  child: const Text('取消选择'),
                ),
              ],
            ),
          IconButton(
            tooltip: '刷新书架',
            onPressed: _loading || _importing ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(theme, filtered),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_importing) ...[
                      LinearProgressIndicator(
                        value: _selected.isEmpty
                            ? null
                            : _importDone / _selected.length,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '正在导入 $_importDone / ${_selected.length}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Checkbox(
                          value: _addWereadTag,
                          onChanged: _importing
                              ? null
                              : (value) => setState(
                                  () => _addWereadTag = value ?? true,
                                ),
                        ),
                        const Expanded(child: Text('添加「微信读书」标签')),
                        FilledButton.icon(
                          onPressed: _importing || _selected.isEmpty
                              ? null
                              : _importSelected,
                          icon: const Icon(Icons.download_outlined),
                          label: Text('导入 ${_selected.length} 本'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBody(ThemeData theme, List<WereadShelfBook> filtered) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在读取微信读书书架…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
              const SizedBox(height: 8),
              Text(
                '如果尚未配置 API Key，请到「设置 → 微信读书」填写并验证。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜索书名 / 作者',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              for (final filter in _ShelfFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(switch (filter) {
                      _ShelfFilter.all => '全部',
                      _ShelfFilter.unfinished => '未读完',
                      _ShelfFilter.finished => '已读完',
                    }),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
              const Spacer(),
              Text(
                '${filtered.length} 本',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _books.isEmpty ? '微信读书书架里没有可导入的书籍' : '没有匹配的书籍',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final book = filtered[index];
                    final disabled = _isDisabled(book);
                    final bindingLabel = _bindingLabel(book);
                    final selected = _selected.contains(book.bookId);
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: disabled ? null : () => _toggle(book),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value: selected,
                                onChanged: disabled || _importing
                                    ? null
                                    : (_) => _toggle(book),
                              ),
                              CoverImage(
                                coverUrl: book.cover,
                                title: book.title,
                                width: 44,
                                height: 62,
                                borderRadius: 6,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      book.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (book.author == null ||
                                              book.author!.trim().isEmpty)
                                          ? '未知作者'
                                          : book.author!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    if (book.category != null &&
                                        book.category!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        book.category!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (book.finishReading)
                                          _MiniBadge(
                                            label: '已读完',
                                            color: theme.colorScheme.tertiary,
                                          )
                                        else if (book.readUpdateTime != null)
                                          Text(
                                            '最近阅读 '
                                            '${formatRelativeDate(book.readUpdateTime)}',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        const Spacer(),
                                        if (bindingLabel != null)
                                          _MiniBadge(
                                            label: bindingLabel,
                                            color: bindingLabel == '绑定已有'
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.outline,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
