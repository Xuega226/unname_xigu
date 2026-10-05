import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/portfolio_history.dart';
import 'package:lianghua_assistant/portfolio_history_widgets.dart';

import 'portfolio_history_test.dart' show holding, seed;

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
    testWidgets(
      'full difference shows all 80 securities with pagination at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final before = seed().copyWith(
          holdings: List.generate(
            80,
            (i) => holding(id: '$i', code: '${600000 + i}'),
          ),
        );
        final after = before.copyWith(
          holdings: List.generate(
            80,
            (i) => holding(id: '$i', code: '${600000 + i}', quantity: i + 20),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PortfolioDiffView(
                  before: PortfolioSnapshot.fromWorkspace(before),
                  after: PortfolioSnapshot.fromWorkspace(after),
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining('证券并集 80 项'), findsOneWidget);
        for (var page = 0; page < 4; page++) {
          final start = page * 25, end = ((page + 1) * 25).clamp(0, 80);
          for (var i = start; i < end; i++) {
            expect(find.textContaining('${600000 + i} 虚构公司'), findsOneWidget);
          }
          if (page < 3) {
            final next = find.byKey(const ValueKey('portfolio-diff-next'));
            await tester.ensureVisible(next);
            await tester.tap(next);
            await tester.pumpAndSettle();
          }
        }
        expect(find.text('第 4 / 4 页 · 每页 25 项'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'history shows safe failures, complete diff and only calls restore callback',
    (tester) async {
      final original = seed();
      var data = recordPortfolioImport(original, original.copyWith(cash: 500));
      data = recordPortfolioFailure(data, 'read_failed');
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PortfolioHistoryPanel(
                data: data,
                onRestore: (id) => selected = id,
              ),
            ),
          ),
        ),
      );
      expect(
        find.text(portfolioFailureMessages['read_failed']!),
        findsOneWidget,
      );
      expect(find.text('恢复此记录之前'), findsOneWidget);
      expect(find.textContaining('只改变持仓、现金'), findsOneWidget);
      await tester.tap(
        find.byKey(ValueKey('history-diff-${data.portfolioHistory.first.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('完整持仓差异'), findsOneWidget);
      expect(find.textContaining('现金：¥ 100.00 → ¥ 500.00'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          ValueKey('history-restore-${data.portfolioHistory.first.id}'),
        ),
      );
      expect(selected, data.portfolioHistory.first.id);
      expect(data.cash, 500);
      expect(data.portfolioHistory.length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('empty history offers no restore action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioHistoryPanel(
            data: WorkspaceData.empty(),
            onRestore: (_) => fail('no selectable event'),
          ),
        ),
      ),
    );
    expect(find.text('暂无导入或恢复记录。'), findsOneWidget);
    expect(find.text('恢复此记录之前'), findsNothing);
  });
}
