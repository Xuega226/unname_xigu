import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/risk_charts.dart';

WorkspaceData riskFixture({int count = 2}) => WorkspaceData.empty().copyWith(
  cash: 1000,
  deposits: 5000,
  withdrawals: 1000,
  priceDate: '2026-10-01',
  holdings: count == 2
      ? [
          const Holding(
            id: 'a',
            code: '600001',
            name: '甲公司',
            industry: '制造',
            quantity: 100,
            price: 20,
          ),
          const Holding(
            id: 'b',
            code: '000001',
            name: '乙公司',
            industry: '行业资料不足',
            quantity: 200,
            price: 10,
          ),
        ]
      : [
          for (var i = 0; i < count; i++)
            Holding(
              id: '$i',
              code: '${600000 + i}',
              name: '样例公司$i',
              industry: '样例行业$i',
              quantity: 1,
              price: (count - i).toDouble(),
            ),
        ],
);

Widget riskHarness(WorkspaceData data, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (context, setState) {
              // State supplied by the parent page; no workspace save callback.
              return RiskCharts(
                data: data,
                stress: .25,
                onStressChanged: (_) {},
              );
            },
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('manual assets, concentrations, loss and principal use distinct denominators', () {
    final data = riskFixture();
    final values = RiskChartValues(data);
    expect(data.assets, 5000);
    expect(data.principal, 4000);
    expect(values.cashWeight, .2);
    expect(data.stockWeight, .8);
    expect(values.holdings.map(values.exposureWeight), [.4, .4]);
    expect(
      values.industries.map((row) => row.value).reduce((a, b) => a + b),
      4000,
    );
    expect(values.industries.map((row) => row.label), contains('行业资料不足'));
    expect(data.stressLoss(.25), .2);
    expect(values.lossAmount(.25), 1000);
    expect(values.postAssets(.25), 4000);
    expect(values.profitAmount, 1000);
    expect(data.profitRate, .25);
    expect(() => values.lossAmount(1.1), throwsArgumentError);
  });

  test('empty, cash-only, missing industry and nonpositive principal stay explicit', () {
    final empty = RiskChartValues(WorkspaceData.empty());
    expect(empty.cashWeight, isNull);
    expect(empty.data.profitRate, isNull);
    expect(empty.data.stressLoss(.5), isNull);
    expect(empty.lossAmount(.5), 0);
    final cash = RiskChartValues(WorkspaceData.empty().copyWith(cash: 100));
    expect(cash.cashWeight, 1);
    expect(cash.data.stockWeight, 0);
    expect(cash.data.stressLoss(1), 0);
    expect(cash.postAssets(1), 100);
    final missing = RiskChartValues(
      WorkspaceData.empty().copyWith(
        holdings: [
          const Holding(
            id: 'm',
            code: '600001',
            name: '缺行业',
            industry: '',
            quantity: 1,
            price: 2,
          ),
        ],
      ),
    );
    expect(missing.industries.single.label, '行业资料不足');
    expect(
      WorkspaceData.empty().copyWith(deposits: 5, withdrawals: 10).profitRate,
      isNull,
    );
  });

  testWidgets('empty charts show unknown, never fabricated 100 percent cash', (
    tester,
  ) async {
    await tester.pumpWidget(riskHarness(WorkspaceData.empty()));
    expect(find.text('暂无账户资产，现金和股票占比无法计算。'), findsOneWidget);
    expect(find.textContaining('本金不大于零'), findsOneWidget);
    expect(find.text('现金 ¥0.00 · 无法计算'), findsOneWidget);
    expect(find.textContaining('历史净值与高点回撤：资料不足'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone large text exposes all 80 holdings and industries across four pages',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final data = riskFixture(count: 80);
      final before = data.encode();
      await tester.pumpWidget(riskHarness(data, scale: 2));
      for (final name in ['个股', '行业']) {
        final seen = <String>{};
        for (var page = 0; page < 4; page++) {
          for (var i = 0; i < 80; i++) {
            final label = name == '个股' ? '样例公司$i · ${600000 + i}' : '样例行业$i';
            if (find
                .byKey(ValueKey('risk-$name-$label'))
                .evaluate()
                .isNotEmpty) {
              seen.add(label);
            }
          }
          if (page < 3) {
            // Direct activation avoids thousands of pixels of scroll for 25-row pages.
            final next = tester.widget<TextButton>(
              find.byKey(ValueKey('risk-$name-next')),
            );
            expect(next.onPressed, isNotNull);
            next.onPressed!();
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
        }
        expect(seen.length, 80);
        expect(
          tester
              .widget<TextButton>(find.byKey(ValueKey('risk-$name-next')))
              .onPressed,
          isNull,
        );
      }
      expect(data.encode(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cash-only desktop and stale estimate show zero stock loss and visible data state',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final oldDate = DateTime.now()
          .subtract(const Duration(days: 8))
          .toIso8601String()
          .substring(0, 10);
      final data = WorkspaceData.empty().copyWith(
        cash: 100,
        deposits: 100,
        priceDate: oldDate,
      );
      await tester.pumpWidget(riskHarness(data));
      expect(find.text('现金 ¥100.00 · 100.0%'), findsOneWidget);
      expect(find.text('股票 ¥0.00 · 0.0%'), findsOneWidget);
      expect(find.text('账户损失 0.0% · 损失金额 ¥0.00'), findsOneWidget);
      expect(find.textContaining('估值已超过 7 天'), findsOneWidget);
      expect(find.textContaining('尚未核验券商快照'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tap details and slider change displayed scenario without modifying workspace',
    (tester) async {
      final data = riskFixture();
      final before = data.encode();
      var stress = .25;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => RiskCharts(
                  data: data,
                  stress: stress,
                  onStressChanged: (value) => setState(() => stress = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('risk-asset-details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('现金 ¥1000.00，占账户资产 20.0%'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('risk-stress-slider')),
      );
      slider.onChanged!(.5);
      await tester.pump();
      expect(find.text('账户损失 40.0% · 损失金额 ¥2000.00'), findsOneWidget);
      expect(find.text('情景后资产 ¥3000.00'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('risk-stress-slider')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('risk-stress-slider')),
        const Offset(70, 0),
      );
      await tester.pumpAndSettle();
      expect(stress, greaterThan(.5));
      expect(
        find.text('情景后资产 ¥${(5000 - 4000 * stress).toStringAsFixed(2)}'),
        findsOneWidget,
      );
      expect(data.encode(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
