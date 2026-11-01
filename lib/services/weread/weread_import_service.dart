import 'dart:math';

import 'package:drift/drift.dart' show Value;

import '../../data/book_status.dart';
import '../../data/database.dart';
import '../../data/repository.dart';
import 'weread_client.dart';

const int _defaultWordsPerPage = 1000;
const int _fallbackPages = 300;

class WereadImportException implements Exception {
  const WereadImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WereadAutoBindResult {
  const WereadAutoBindResult({
    required this.bound,
    required this.ambiguous,
    required this.failed,
    required this.errors,
  });

  final int bound;
  final int ambiguous;
  final int failed;
  final List<String> errors;

  bool get changed => bound > 0;
}

class WereadImportPreview {
  const WereadImportPreview({
    required this.shelfBook,
    required this.info,
    required this.progress,
    required this.totalPages,
    required this.currentPage,
    required this.finished,
    required this.status,
  });

  final WereadShelfBook shelfBook;
  final WereadBookInfo info;
  final WereadProgress progress;
  final int totalPages;
  final int currentPage;
  final bool finished;
  final String status;

  double get progressPercent => totalPages <= 0 ? 0 : currentPage / totalPages;
}

/// 把微信读书书架书转换为阅历本地书籍。
class WereadImportService {
  WereadImportService({
    required WereadClient client,
    required ReadingRepository repository,
    required Future<String?> Function() apiKeyLoader,
  }) : _client = client,
       _repository = repository,
       _apiKeyLoader = apiKeyLoader;

  final WereadClient _client;
  final ReadingRepository _repository;
  final Future<String?> Function() _apiKeyLoader;

  String? _cachedApiKey;

  Future<String> _apiKey() async {
    final cached = _cachedApiKey;
    if (cached != null && cached.isNotEmpty) return cached;
    final key = await _apiKeyLoader();
    if (key == null || key.isEmpty) {
      throw const WereadAuthException('请先在设置中配置微信读书 API Key');
    }
    _cachedApiKey = key;
    return key;
  }

  Future<List<WereadShelfBook>> fetchShelf() async {
    final books = await _client.fetchShelf(await _apiKey());
    return books.where((book) => book.bookId.isNotEmpty).toList();
  }

  Future<WereadImportPreview> prepare(WereadShelfBook shelfBook) async {
    final key = await _apiKey();
    final info = await _client.fetchBookInfo(key, bookId: shelfBook.bookId);
    final progress = await _client.fetchProgress(key, bookId: shelfBook.bookId);
    final totalPages = estimatePages(info.wordCount);
    final finished =
        shelfBook.finishReading ||
        (progress.progress >= 100 && progress.finishTime != null);
    final currentPage = finished
        ? totalPages
        : (totalPages * progress.progress / 100).round().clamp(0, totalPages);
    final status = finished
        ? BookStatus.finished
        : currentPage > 0
        ? BookStatus.reading
        : BookStatus.want;
    return WereadImportPreview(
      shelfBook: shelfBook,
      info: info,
      progress: progress,
      totalPages: totalPages,
      currentPage: currentPage,
      finished: finished,
      status: status,
    );
  }

  Future<int> importPreview(
    WereadImportPreview preview, {
    bool addWereadTag = true,
  }) async {
    final info = preview.info;
    final shelf = preview.shelfBook;
    final tags = buildWereadTags(
      info.category ?? shelf.category,
      addWereadTag: addWereadTag,
    );
    final bookId = await _repository.createBook(
      title: info.title.trim().isEmpty ? shelf.title : info.title.trim(),
      author: _nonEmpty(info.author) ?? _nonEmpty(shelf.author),
      totalPages: preview.totalPages,
      currentPage: preview.currentPage,
      status: preview.status,
      tags: tags.isEmpty ? null : encodeTags(tags),
      coverUrl: _nonEmpty(info.cover) ?? _nonEmpty(shelf.cover),
      coverPath: null,
      description: _nonEmpty(info.intro),
      translator: _nonEmpty(info.translator),
      publisher: _nonEmpty(info.publisher),
      publishDate: _nonEmpty(info.publishDate),
      isbn: _nonEmpty(info.isbn),
      wordCount: info.wordCount,
      rating: _normalizeRating(info.rating),
      ratingCount: info.ratingCount,
      metadataSource: 'weread',
      metadataUpdatedAt: DateTime.now(),
    );
    await _repository.linkWereadBook(
      bookId: bookId,
      wereadBookId: shelf.bookId,
      readerLink: _nonEmpty(info.readerLink) ?? _nonEmpty(shelf.readerLink),
      deepLink: _nonEmpty(info.deepLink) ?? _nonEmpty(shelf.deepLink),
      remoteProgress: preview.progress.progress,
      remoteReadSeconds: preview.progress.recordReadingTime == 0
          ? null
          : preview.progress.recordReadingTime,
      remoteFinished: preview.finished,
      remoteUpdatedAt: preview.progress.updateTime ?? shelf.readUpdateTime,
    );
    return bookId;
  }

  /// 扫描本地书籍与微信读书书架，自动绑定唯一同名同作者的书。
  ///
  /// 同名但无法唯一确定、或已经绑定的书会跳过，不会猜测。
  Future<WereadAutoBindResult> autoBindExistingBooks({
    void Function(int done, int total)? onProgress,
  }) async {
    final shelf = await fetchShelf();
    final links = await _repository.allWereadLinks();
    final linkedWereadIds = links.map((e) => e.wereadBookId).toSet();
    final linkedLocalIds = links.map((e) => e.bookId).toSet();
    final localBooks = await _repository.allBooks();

    final shelfByTitle = <String, List<WereadShelfBook>>{};
    for (final item in shelf) {
      if (linkedWereadIds.contains(item.bookId)) continue;
      final key = normalizeWereadTitle(item.title);
      if (key.isEmpty) continue;
      shelfByTitle.putIfAbsent(key, () => []).add(item);
    }

    final matches = <(Book, WereadShelfBook)>[];
    var ambiguous = 0;
    for (final book in localBooks) {
      if (linkedLocalIds.contains(book.id)) continue;
      final key = normalizeWereadTitle(book.title);
      if (key.isEmpty) continue;
      final candidates = shelfByTitle[key];
      if (candidates == null || candidates.isEmpty) continue;
      final localAuthor = normalizeWereadAuthor(book.author);
      final filtered = candidates.where((item) {
        final shelfAuthor = normalizeWereadAuthor(item.author);
        if (localAuthor.isEmpty || shelfAuthor.isEmpty) return true;
        return localAuthor == shelfAuthor;
      }).toList();
      if (filtered.length == 1) {
        matches.add((book, filtered.single));
      } else if (filtered.length > 1) {
        ambiguous++;
      }
    }

    final used = <String>{};
    final errors = <String>[];
    var bound = 0;
    var failed = 0;
    for (var i = 0; i < matches.length; i++) {
      final (book, shelfBook) = matches[i];
      if (used.contains(shelfBook.bookId)) {
        ambiguous++;
        onProgress?.call(i + 1, matches.length);
        continue;
      }
      try {
        await bindExistingBook(bookId: book.id, shelfBook: shelfBook);
        used.add(shelfBook.bookId);
        bound++;
      } catch (e) {
        failed++;
        errors.add('《${book.title}》：$e');
      }
      onProgress?.call(i + 1, matches.length);
    }

    return WereadAutoBindResult(
      bound: bound,
      ambiguous: ambiguous,
      failed: failed,
      errors: errors,
    );
  }

  /// 把已有本地书籍绑定到微信读书书籍。
  ///
  /// 只补齐本地为空的元数据，不覆盖用户已填内容；进度只前进不后退。
  Future<void> bindExistingBook({
    required int bookId,
    required WereadShelfBook shelfBook,
  }) async {
    final existing = await _repository.getWereadLinkByWereadId(
      shelfBook.bookId,
    );
    if (existing != null && existing.bookId != bookId) {
      throw const WereadImportException('这本书已经绑定到另一本本地书籍');
    }
    final book = await _repository.getBook(bookId);
    if (book == null) throw const WereadImportException('本地书籍不存在');

    final preview = await prepare(shelfBook);
    final info = preview.info;
    final rating = _normalizeRating(info.rating);
    final cover = _nonEmpty(info.cover) ?? _nonEmpty(shelfBook.cover);
    final author = _nonEmpty(info.author) ?? _nonEmpty(shelfBook.author);
    final filledMetadata =
        (book.coverUrl == null && cover != null) ||
        (book.description == null && _nonEmpty(info.intro) != null) ||
        (book.translator == null && _nonEmpty(info.translator) != null) ||
        (book.publisher == null && _nonEmpty(info.publisher) != null) ||
        (book.publishDate == null && _nonEmpty(info.publishDate) != null) ||
        (book.isbn == null && _nonEmpty(info.isbn) != null) ||
        (book.wordCount == null && info.wordCount != null) ||
        (book.rating == null && rating != null) ||
        (book.ratingCount == null && info.ratingCount != null);

    await _repository.updateBook(
      bookId,
      BooksCompanion(
        author: Value(book.author ?? author),
        coverUrl: Value(book.coverUrl ?? cover),
        description: Value(book.description ?? _nonEmpty(info.intro)),
        translator: Value(book.translator ?? _nonEmpty(info.translator)),
        publisher: Value(book.publisher ?? _nonEmpty(info.publisher)),
        publishDate: Value(book.publishDate ?? _nonEmpty(info.publishDate)),
        isbn: Value(book.isbn ?? _nonEmpty(info.isbn)),
        wordCount: Value(book.wordCount ?? info.wordCount),
        rating: Value(book.rating ?? rating),
        ratingCount: Value(book.ratingCount ?? info.ratingCount),
        metadataSource: Value(
          filledMetadata && book.metadataSource == 'manual'
              ? 'weread'
              : book.metadataSource,
        ),
        metadataUpdatedAt: Value(
          filledMetadata ? DateTime.now() : book.metadataUpdatedAt,
        ),
      ),
    );
    await _repository.linkWereadBook(
      bookId: bookId,
      wereadBookId: shelfBook.bookId,
      readerLink: _nonEmpty(info.readerLink) ?? _nonEmpty(shelfBook.readerLink),
      deepLink: _nonEmpty(info.deepLink) ?? _nonEmpty(shelfBook.deepLink),
      remoteProgress: preview.progress.progress,
      remoteReadSeconds: preview.progress.recordReadingTime == 0
          ? null
          : preview.progress.recordReadingTime,
      remoteFinished: preview.finished,
      remoteUpdatedAt: preview.progress.updateTime ?? shelfBook.readUpdateTime,
    );
  }

  static int estimatePages(int? wordCount) {
    if (wordCount == null || wordCount <= 0) return _fallbackPages;
    return max(1, (wordCount / _defaultWordsPerPage).ceil());
  }

  /// 官方 newRating 是百分制；本地按 0-10 存储。
  static double? _normalizeRating(double? rating) {
    if (rating == null || rating <= 0) return null;
    final value = rating > 10 ? rating / 10 : rating;
    return value.clamp(0, 10).toDouble();
  }

  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}

String normalizeWereadTitle(String? title) {
  var text = (title ?? '').trim().toLowerCase();
  text = text.replaceAll(RegExp(r'\s+'), '');
  text = text.replaceAll(RegExp(r'[《》【】\[\]（）()：:·,，.。!！?？\-—_/\\]'), '');
  return text;
}

String normalizeWereadAuthor(String? author) {
  var text = (author ?? '').trim().toLowerCase();
  // 去掉常见的国籍前缀，如「[美] 作者」「【英】作者」。
  text = text.replaceFirst(RegExp(r'^[\[【（(][^\]】）)]*[\]】）)]\s*'), '');
  text = text.replaceAll(RegExp(r'\s+'), '');
  text = text.replaceAll(RegExp(r'[\[\]【】（）()]'), '');
  return text;
}

/// 分类转标签。分类可能是 `计算机/编程/程序设计` 这类路径。
List<String> buildWereadTags(String? category, {bool addWereadTag = true}) {
  final tags = <String>{};
  final text = category?.trim() ?? '';
  if (text.isNotEmpty) {
    for (final part in text.split(RegExp(r'[/>·|,，]'))) {
      final tag = part.trim().replaceAll(',', '');
      if (tag.isNotEmpty && tag.length <= 40) tags.add(tag);
    }
  }
  if (addWereadTag) tags.add('微信读书');
  return tags.toList();
}
