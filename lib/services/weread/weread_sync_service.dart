import 'dart:math';

import 'package:drift/drift.dart' show Value;

import '../../data/book_status.dart';
import '../../data/database.dart';
import '../../data/repository.dart';
import 'weread_client.dart';
import 'weread_import_service.dart';

class WereadSyncResult {
  const WereadSyncResult({
    required this.bookId,
    required this.remoteProgress,
    required this.estimatedPage,
    required this.localPage,
    required this.changed,
    required this.finished,
    required this.message,
  });

  final int bookId;
  final int remoteProgress;

  /// 按本地总页数换算出的估算页，不等同于微信读书的真实页码。
  final int estimatedPage;
  final int localPage;
  final bool changed;
  final bool finished;
  final String message;
}

class WereadSyncAllResult {
  const WereadSyncAllResult({
    required this.changed,
    required this.finished,
    required this.kept,
    required this.failed,
    required this.errors,
  });

  final int changed;
  final int finished;
  final int kept;
  final int failed;
  final List<String> errors;
}

/// 把微信读书进度同步到已经绑定的本地书籍。
class WereadSyncService {
  WereadSyncService({
    required WereadClient client,
    required ReadingRepository repository,
    required Future<String?> Function() apiKeyLoader,
  }) : _client = client,
       _repository = repository,
       _apiKeyLoader = apiKeyLoader;

  final WereadClient _client;
  final ReadingRepository _repository;
  final Future<String?> Function() _apiKeyLoader;

  Future<String> _apiKey() async {
    final key = await _apiKeyLoader();
    if (key == null || key.isEmpty) {
      throw const WereadAuthException('请先在设置中配置微信读书 API Key');
    }
    return key;
  }

  Future<WereadSyncResult> syncBook(
    int bookId, {
    bool updatePages = false,
  }) async {
    final link = await _repository.getWereadLink(bookId);
    if (link == null) {
      throw const WereadImportException('这本书还没有绑定微信读书');
    }
    final book = await _repository.getBook(bookId);
    if (book == null) {
      throw const WereadImportException('本地书籍不存在');
    }

    final progress = await _client.fetchProgress(
      await _apiKey(),
      bookId: link.wereadBookId,
    );
    final remoteFinished =
        progress.progress >= 100 && progress.finishTime != null;
    final remotePage = remoteFinished
        ? book.totalPages
        : (book.totalPages * progress.progress / 100)
              .round()
              .clamp(0, max(0, book.totalPages - 1))
              .toInt();

    var changed = false;
    var finished = false;
    var message = '';
    if (book.round > 1) {
      message = '正在重读，已跳过进度覆盖';
    } else if (remoteFinished) {
      if (book.status != BookStatus.finished) {
        await _repository.setBookStatus(bookId, BookStatus.finished);
        changed = true;
        finished = true;
        message = '已同步为读完';
      } else {
        message = '已读完，无需更新';
      }
    } else if (progress.progress >= 100) {
      message = '微信读书进度 100%，但缺少读完时间，未改动本地进度';
    } else if (updatePages && remotePage > book.currentPage) {
      await applyEstimatedPage(bookId, remotePage);
      changed = true;
      message = '本地页码已按比例更新到第 $remotePage 页（估算）';
    } else if (updatePages) {
      message = '本地进度领先，已保留本地进度';
    } else {
      message = '已记录微信读书进度 ${progress.progress}%，本地页码未改动';
    }

    await _repository.updateWereadLinkSync(
      bookId,
      remoteProgress: progress.progress,
      remoteReadSeconds: progress.recordReadingTime == 0
          ? null
          : progress.recordReadingTime,
      remoteFinished: remoteFinished,
      remoteUpdatedAt: progress.updateTime,
    );

    final updated = await _repository.getBook(bookId);
    return WereadSyncResult(
      bookId: bookId,
      remoteProgress: progress.progress,
      estimatedPage: remotePage,
      localPage: updated?.currentPage ?? book.currentPage,
      changed: changed,
      finished: finished,
      message: message,
    );
  }

  /// 用户确认后，把按比例估算出的页码写入本地书籍并重排计划。
  Future<void> applyEstimatedPage(int bookId, int page) async {
    final book = await _repository.getBook(bookId);
    if (book == null || book.totalPages <= 0) return;
    final target = page.clamp(0, book.totalPages);
    if (target <= book.currentPage) return;
    await _repository.updateBook(
      bookId,
      BooksCompanion(
        currentPage: Value(target),
        status: Value(
          book.status == BookStatus.want ? BookStatus.reading : book.status,
        ),
      ),
    );
    final plan = await _repository.getPlanForBook(bookId);
    if (plan != null) await _repository.reschedulePlan(plan.id);
  }

  Future<WereadSyncAllResult> syncAll({
    bool updatePages = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final links = await _repository.allWereadLinks();
    var changed = 0;
    var finished = 0;
    var kept = 0;
    var failed = 0;
    final errors = <String>[];

    for (var i = 0; i < links.length; i++) {
      final link = links[i];
      try {
        final result = await syncBook(link.bookId, updatePages: updatePages);
        if (result.changed) {
          changed++;
          if (result.finished) finished++;
        } else {
          kept++;
        }
      } catch (e) {
        failed++;
        final book = await _repository.getBook(link.bookId);
        errors.add('《${book?.title ?? link.wereadBookId}》：$e');
      }
      onProgress?.call(i + 1, links.length);
    }

    return WereadSyncAllResult(
      changed: changed,
      finished: finished,
      kept: kept,
      failed: failed,
      errors: errors,
    );
  }
}
