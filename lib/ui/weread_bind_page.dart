import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format_x.dart';
import '../services/weread/weread_client.dart';
import '../state/providers.dart';
import 'widgets/book_cover.dart';

class WereadBindPage extends ConsumerStatefulWidget {
  const WereadBindPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  final int bookId;
  final String bookTitle;

  @override
  ConsumerState<WereadBindPage> createState() => _WereadBindPageState();
}

class _WereadBindPageState extends ConsumerState<WereadBindPage> {
  final _search = TextEditingController();
  List<WereadShelfBook> _books = const [];
  Map<String, int> _boundBookIds = const {};
  bool _loading = true;
  String? _error;
  String? _busyId;
  String _query = '';

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
      shelf.sort((a, b) {
        final at = a.readUpdateTime?.millisecondsSinceEpoch ?? 0;
        final bt = b.readUpdateTime?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });
      if (!mounted) return;
      setState(() {
        _books = shelf;
        _boundBookIds = {
          for (final link in links) link.wereadBookId: link.bookId,
        };
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

  List<WereadShelfBook> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _books;
    return _books.where((book) {
      final title = book.title.toLowerCase();
      final author = (book.author ?? '').toLowerCase();
      return title.contains(query) || author.contains(query);
    }).toList();
  }

  Future<void> _bind(WereadShelfBook shelfBook) async {
    if (_busyId != null) return;
    setState(() => _busyId = shelfBook.bookId);
    try {
      await ref
          .read(wereadImportServiceProvider)
          .bindExistingBook(bookId: widget.bookId, shelfBook: shelfBook);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('绑定失败：$e')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('绑定微信读书')),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在读取微信读书书架…'),
                ],
              ),
            )
          : _error != null
          ? Center(
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
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '选择微信读书中的《${widget.bookTitle}》，绑定到当前本地书籍。'
                    '只补齐空着的元数据，不会按百分比修改本地页码。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: '搜索微信读书书架',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            _books.isEmpty ? '微信读书书架没有可绑定的书籍' : '没有匹配的书籍',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final book = filtered[index];
                            final boundTo = _boundBookIds[book.bookId];
                            final bound = boundTo != null;
                            final busy = _busyId == book.bookId;
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: ListTile(
                                enabled: !bound && _busyId == null,
                                onTap: bound ? null : () => _bind(book),
                                leading: CoverImage(
                                  coverUrl: book.cover,
                                  title: book.title,
                                  width: 44,
                                  height: 62,
                                  borderRadius: 6,
                                ),
                                title: Text(
                                  book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (book.author == null ||
                                              book.author!.trim().isEmpty)
                                          ? '未知作者'
                                          : book.author!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (book.category != null &&
                                        book.category!.trim().isNotEmpty)
                                      Text(
                                        book.category!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (book.readUpdateTime != null)
                                      Text(
                                        '最近阅读 '
                                        '${formatRelativeDate(book.readUpdateTime)}',
                                      ),
                                  ],
                                ),
                                trailing: busy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : bound
                                    ? const Text('已绑定')
                                    : const Icon(Icons.link),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
