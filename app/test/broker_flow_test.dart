import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';

import 'broker_import_test.dart' show snapshotBytes;

class FakeBrokerFiles extends BrokerImportService {
  FakeBrokerFiles({
    this.invalid = false,
    this.cancel = false,
    this.csv = false,
  });
  final bool invalid, cancel, csv;
  @override
  Future<SelectedPortfolioFile?> pick() async => cancel
      ? null
      : SelectedPortfolioFile(
          bytes: invalid
              ? utf8.encode('{broken')
              : csv
              ? utf8.encode('证券代码,证券名称,持仓数量,市价\n000001,测试证券,100,10')
              : snapshotBytes(),
          name: csv ? '虚构测试.csv' : '虚构测试.json',
          path: 'unused-test-path',
        );
}

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
    testWidgets(
      'reviewed JSON import persists and manual holding edit marks provenance at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryWorkspaceStore(WorkspaceData.empty());
        await tester.pumpWidget(
          LianghuaApp(
            store: store,
            brokerImporter: FakeBrokerFiles(),
            brokerSettings: MemoryBrokerSettingsStore(),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, '账户风控');
        await tap(tester, '导入券商持仓');
        await tap(tester, '选择持仓文件');
        expect(find.textContaining('000001 测试证券'), findsOneWidget);
        expect(store.data!.holdings, isEmpty);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '确认导入'),
        );
        expect(button.onPressed, isNull);
        await tap(tester, '已核对账户、完整持仓、现金和估值日期');
        await tap(tester, '确认导入');
        expect(store.data!.holdings.single.code, '000001');
        expect(store.data!.cash, 5000);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byTooltip('编辑持仓'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('编辑持仓'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).at(3), '200');
        await tap(tester, '保存');
        expect(store.data!.portfolioImport!.modified, isTrue);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(LianghuaApp(store: store));
        await tester.pumpAndSettle();
        await tap(tester, '账户风控');
        expect(find.textContaining('自动读取已关闭'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'CSV requires explicit account, valuation date and cash before preview',
    (tester) async {
      final store = MemoryWorkspaceStore(WorkspaceData.empty());
      await tester.pumpWidget(
        LianghuaApp(store: store, brokerImporter: FakeBrokerFiles(csv: true)),
      );
      await tester.pumpAndSettle();
      await tap(tester, '账户风控');
      await tap(tester, '导入券商持仓');
      await tap(tester, '选择持仓文件');
      expect(find.text('核对 CSV 的账户信息'), findsOneWidget);
      for (final entry in [
        '测试券商',
        '主账户',
        '2026-10-01',
        '1234',
      ].asMap().entries) {
        await tester.enterText(
          find.byType(TextFormField).at(entry.key),
          entry.value,
        );
      }
      await tap(tester, '保存');
      expect(store.data!.holdings, isEmpty);
      await tap(tester, '已核对账户、完整持仓、现金和估值日期');
      await tap(tester, '确认导入');
      expect(store.data!.cash, 1234);
      expect(store.data!.portfolioImport!.format, 'csv');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  for (final files in [
    FakeBrokerFiles(cancel: true),
    FakeBrokerFiles(invalid: true),
  ]) {
    testWidgets(
      'cancelled or malformed selection never replaces portfolio invalid=${files.invalid}',
      (tester) async {
        final store = MemoryWorkspaceStore(WorkspaceData.empty());
        final initial = store.data!.encode();
        await tester.pumpWidget(
          LianghuaApp(store: store, brokerImporter: files),
        );
        await tester.pumpAndSettle();
        await tap(tester, '账户风控');
        await tap(tester, '导入券商持仓');
        await tap(tester, '选择持仓文件');
        await tap(tester, '取消');
        expect(store.data!.encode(), initial);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
