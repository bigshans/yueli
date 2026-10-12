import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/timer_notification.dart';
import '../state/providers.dart';
import '../data/repository.dart';
import 'books_page.dart';
import 'calendar_page.dart';
import 'today_page.dart';
import 'widgets/timer_banner.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _pages = [TodayPage(), CalendarPage(), BooksPage()];

  @override
  void initState() {
    super.initState();
    // 启动时自愈重排：把过期的 pending 任务折进今天之后。
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(repositoryProvider).rescheduleAll();
      await TimerNotificationService.instance.init();
      await TimerNotificationService.instance.requestPermission();
      await _syncNotification(ref.read(activeTimerProvider));
    });
    // 计时状态变化时同步系统通知。
    ref.listenManual(
      activeTimerProvider,
      (_, next) => _syncNotification(next),
    );
  }

  Future<void> _syncNotification(ActiveTimer? timer) async {
    final service = TimerNotificationService.instance;
    if (timer == null) {
      await service.cancel();
      return;
    }
    var title = '阅读';
    try {
      final book = await ref.read(repositoryProvider).getBook(timer.bookId);
      if (book != null) title = book.title;
    } catch (_) {
      // 忽略
    }
    final elapsed = timer.elapsedSecondsAt(DateTime.now());
    if (timer.isRunning) {
      await service.showRunning(bookTitle: title, elapsedSeconds: elapsed);
    } else {
      await service.showPaused(bookTitle: title, elapsedSeconds: elapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TimerBanner(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: '日历',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
        ],
          ),
        ],
      ),
    );
  }
}
