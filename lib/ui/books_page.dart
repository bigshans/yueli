import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../state/providers.dart';
import 'book_detail_page.dart';
import 'book_form_page.dart';

class BooksPage extends ConsumerWidget {
  const BooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('书架')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const BookFormPage()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('添加读物'),
      ),
      body: booksAsync.when(
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
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text('书架还是空的'),
                    const SizedBox(height: 8),
                    Text(
                      '添加一本读物，设定截止日和每天可用的时间，\n就能自动排出每天读多少页。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: books.length,
            itemBuilder: (context, i) => _BookTile(book: books[i]),
          );
        },
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
    final progress =
        book.totalPages == 0 ? 0.0 : book.currentPage / book.totalPages;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BookDetailPage(bookId: book.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _PriorityBadge(label: _priorityLabel, priority: book.priority),
                ],
              ),
              if (book.author != null && book.author!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  book.author!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${book.currentPage} / ${book.totalPages} 页',
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  planAsync.maybeWhen(
                    data: (plan) => plan == null
                        ? Text(
                            '未排期',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline),
                          )
                        : Text(
                            plan.deadline == null
                                ? '无期限'
                                : '截止 ${plan.deadline!.month}/${plan.deadline!.day}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: plan.status == 'oversubscribed'
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
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
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
