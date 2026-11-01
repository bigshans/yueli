import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format_x.dart';
import '../data/book_status.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../state/providers.dart';
import 'book_detail_page.dart';
import 'book_form_page.dart';
import 'weread_import_page.dart';
import 'widgets/book_cover.dart';
import 'widgets/tag_picker_sheet.dart';

class BooksPage extends ConsumerStatefulWidget {
  const BooksPage({super.key});

  @override
  ConsumerState<BooksPage> createState() => _BooksPageState();
}

class _BooksPageState extends ConsumerState<BooksPage>
    with SingleTickerProviderStateMixin {
  final _search = TextEditingController();
  String _query = '';
  final _selectedTags = <String>{};
  late final TabController _tabs;

  static const _statuses = <String?>[
    null,
    BookStatus.reading,
    BookStatus.want,
    BookStatus.finished,
    BookStatus.shelved,
  ];
  static const _tabLabels = ['全部', '在读', '想读', '已读', '搁置'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _statuses.length,
      vsync: this,
      initialIndex: 1,
    )..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickTags(List<String> allTags) async {
    final picked = await showTagPickerSheet(
      context,
      allTags: allTags,
      selected: _selectedTags,
      title: '筛选标签',
      onDeleteTag: (tag) async {
        await ref.read(repositoryProvider).deleteTagGlobally(tag);
        if (mounted) setState(() => _selectedTags.remove(tag));
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTags
          ..clear()
          ..addAll(picked);
      });
    }
  }

  List<Book> _filter(List<Book> books) {
    final q = _query.trim().toLowerCase();
    return books.where((b) {
      if (q.isNotEmpty &&
          !b.title.toLowerCase().contains(q) &&
          !(b.author ?? '').toLowerCase().contains(q)) {
        return false;
      }
      if (_selectedTags.isEmpty) return true;
      final tags = parseTags(b.tags).toSet();
      return _selectedTags.any(tags.contains);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    final scheme = Theme.of(context).colorScheme;
    final allBooks = booksAsync.valueOrNull ?? const <Book>[];
    final availableTags = <String>{
      for (final b in allBooks) ...parseTags(b.tags),
    }.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            tooltip: '从微信读书导入',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: () async {
              final imported = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const WereadImportPage()),
              );
              if (imported == true && context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已从微信读书导入书籍')));
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final label in _tabLabels) Tab(text: label)],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const BookFormPage())),
        icon: const Icon(Icons.add),
        label: const Text('添加读物'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索书名 / 作者',
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
          ),
          if (availableTags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickTags(availableTags),
                    icon: const Icon(Icons.local_offer_outlined, size: 18),
                    label: Text(
                      _selectedTags.isEmpty
                          ? '标签筛选'
                          : '标签筛选 · ${_selectedTags.length}',
                    ),
                  ),
                  for (final tag in _selectedTags)
                    InputChip(
                      label: Text('#$tag'),
                      onDeleted: () =>
                          setState(() => _selectedTags.remove(tag)),
                    ),
                  if (_selectedTags.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(_selectedTags.clear),
                      child: const Text('清除'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: booksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('出错了：$e')),
              data: (books) {
                if (books.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 56,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 16),
                          const Text('书架还是空的'),
                          const SizedBox(height: 8),
                          Text(
                            '添加一本读物，设定截止日和每天可用的时间，\n就能自动排出每天读多少页。',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final tabStatus = _statuses[_tabs.index];
                final filtered = _filter(books)
                    .where((b) => tabStatus == null || b.status == tabStatus)
                    .toList();
                if (filtered.isEmpty) {
                  final label = _tabLabels[_tabs.index];
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? '「$label」里还没有书'
                          : '「$label」里没有找到匹配「$_query」的书',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _BookTile(book: filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BookTile extends ConsumerWidget {
  const _BookTile({required this.book});
  final Book book;

  String get _priorityLabel =>
      const {1: '高', 2: '中', 3: '低'}[book.priority] ?? '中';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final planAsync = ref.watch(planForBookProvider(book.id));
    final progress = book.totalPages == 0
        ? 0.0
        : book.currentPage / book.totalPages;
    final tags = parseTags(book.tags);
    final rating = formatRating(book.rating);
    final author = (book.author == null || book.author!.trim().isEmpty)
        ? '未知作者'
        : book.author!;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BookDetailPage(bookId: book.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(book: book, width: 56, height: 80),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (rating.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 2),
                          Text(rating, style: theme.textTheme.labelSmall),
                        ],
                        PopupMenuButton<String>(
                          tooltip: '修改阅读状态',
                          initialValue: book.status,
                          onSelected: (next) async {
                            await ref
                                .read(repositoryProvider)
                                .setBookStatus(book.id, next);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '已标记为「${BookStatus.label(next)}」',
                                  ),
                                ),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            for (final status in BookStatus.all)
                              CheckedPopupMenuItem(
                                value: status,
                                checked: book.status == status,
                                child: Text(BookStatus.label(status)),
                              ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.more_vert, size: 18),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 3,
                        children: [
                          for (final t in tags.take(3))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '#$t',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          if (tags.length > 3)
                            Text(
                              '+${tags.length - 3}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          '${book.currentPage} / ${book.totalPages} 页',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '剩余 ${book.totalPages - book.currentPage} 页',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const Spacer(),
                        _PriorityBadge(
                          label: _priorityLabel,
                          priority: book.priority,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    planAsync.maybeWhen(
                      data: (plan) {
                        if (book.status != BookStatus.reading) {
                          return Text(
                            BookStatus.label(book.status),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.tertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }
                        return Text(
                          plan == null
                              ? '未排期'
                              : plan.deadline == null
                              ? '无期限'
                              : '截止 ${plan.deadline!.month}/${plan.deadline!.day}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: plan?.status == 'oversubscribed'
                                ? theme.colorScheme.error
                                : plan == null
                                ? theme.colorScheme.outline
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.label, required this.priority});
  final String label;
  final int priority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (priority) {
      1 => scheme.error,
      3 => scheme.outline,
      _ => scheme.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label优先级',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
