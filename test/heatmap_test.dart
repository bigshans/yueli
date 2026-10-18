import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_management/core/date_x.dart';
import 'package:reader_management/data/database.dart';
import 'package:reader_management/ui/widgets/reading_heatmap.dart';

void main() {
  testWidgets('阅读热力图按页数渲染', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = today();
    final sessions = [
      ReadingSession(
        id: 1,
        bookId: 1,
        startedAt: addDays(now, -1).add(const Duration(hours: 9)),
        endedAt: addDays(now, -1).add(const Duration(minutes: 30)),
        durationSeconds: 1800,
        pagesRead: 15,
        round: 1,
        createdAt: now,
      ),
      ReadingSession(
        id: 2,
        bookId: 1,
        startedAt: now.add(const Duration(hours: 8)),
        endedAt: now.add(const Duration(hours: 8, minutes: 20)),
        durationSeconds: 1200,
        pagesRead: 8,
        round: 1,
        createdAt: now,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReadingHeatmapCard(
              sessions: sessions,
              metric: ReadingHeatmapMetric.pages,
              today: now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读热力图'), findsOneWidget);
    expect(find.text('按页数'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
