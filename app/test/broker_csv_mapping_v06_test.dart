import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_import.dart';
import 'package:lianghua_assistant/broker_widgets.dart';
import 'package:lianghua_assistant/domain.dart';

import 'broker_preview_test.dart' show click, openPreview;

const unknownCsv = 'ID;Label;Total;Now\n000001;虚构证券;100;12';

Future<void> fillAccount(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(4));
  await tester.enterText(fields.at(0), '虚构测试券商');
  await tester.enterText(fields.at(1), '测试主账户');
  await tester.enterText(fields.at(2), '2026-10-01');
  await tester.enterText(fields.at(3), '100');
  await click(tester, find.widgetWithText(FilledButton, '保存'));
}

Future<void> chooseColumn(
  WidgetTester tester,
  String field,
  String label,
) async {
  await click(tester, find.byKey(ValueKey('broker-map-$field')));
  await click(tester, find.text(label).last);
}

Future<void> chooseUnknown(WidgetTester tester) async {
  await chooseColumn(tester, 'code', '1. ID · 000001');
  await chooseColumn(tester, 'name', '2. Label · 虚构证券');
  await chooseColumn(tester, 'quantity', '3. Total · 100');
  await chooseColumn(tester, 'price', '4. Now · 12');
  await click(tester, find.text('应用列映射'));
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
    testWidgets(
      'unknown columns preview requires explicit mapping on $size and cancel writes nothing',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = WorkspaceData.empty().copyWith(priceDate: '2026-10-01');
        final original = data.encode();
        BrokerImportSelection? selected;
        await openPreview(
          tester,
          data,
          utf8.encode(unknownCsv),
          (v) => selected = v,
        );
        await fillAccount(tester);
        expect(find.text('核对 CSV 列映射'), findsOneWidget);
        await click(tester, find.text('应用列映射'));
        expect(find.textContaining('缺少或存在多个'), findsOneWidget);
        await chooseUnknown(tester);
        expect(
          find.byKey(const ValueKey('broker-preview-000001')),
          findsOneWidget,
        );
        expect(
          find.text('原现金 ¥ 0.00 → ¥ 100.00 · 变化 ¥ 100.00'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('broker-adjust-mapping')),
          findsOneWidget,
        );
        await click(
          tester,
          find.byKey(const ValueKey('broker-adjust-mapping')),
        );
        await click(tester, find.widgetWithText(TextButton, '取消').last);
        expect(
          find.byKey(const ValueKey('broker-preview-000001')),
          findsOneWidget,
        );
        await click(tester, find.widgetWithText(TextButton, '取消').last);
        expect(selected, isNull);
        expect(data.encode(), original);
      },
    );
  }
  testWidgets(
    'cancel during unknown mapping does not create an applicable preview',
    (tester) async {
      final data = WorkspaceData.empty();
      final original = data.encode();
      await openPreview(tester, data, utf8.encode(unknownCsv), (_) {});
      await fillAccount(tester);
      await click(tester, find.widgetWithText(TextButton, '取消').last);
      expect(find.byKey(const ValueKey('broker-preview-000001')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入'))
            .onPressed,
        isNull,
      );
      expect(data.encode(), original);
    },
  );
  testWidgets(
    'GBK decoding needs a separate explicit confirmation then normal CSV can import',
    (tester) async {
      const known = '证券代码,证券名称,持仓数量,市价\n000001,虚构证券,100,12';
      final data = WorkspaceData.empty();
      final original = data.encode();
      BrokerImportSelection? selected;
      await openPreview(
        tester,
        data,
        const GbkCodec().encode(known),
        (v) => selected = v,
      );
      expect(find.text('核对文件编码'), findsOneWidget);
      await click(tester, find.byKey(const ValueKey('broker-encoding-gbk')));
      await fillAccount(tester);
      expect(find.text('核对 CSV 列映射'), findsNothing);
      expect(
        find.byKey(const ValueKey('broker-preview-000001')),
        findsOneWidget,
      );
      await click(tester, find.text('已核对账户、完整持仓、现金和估值日期'));
      await click(tester, find.widgetWithText(FilledButton, '确认导入'));
      expect(selected!.snapshot.assets, 1300);
      expect(data.encode(), original);
    },
  );
  testWidgets(
    'GBK encoding cancellation leaves workspace and preview untouched',
    (tester) async {
      final data = WorkspaceData.empty();
      final original = data.encode();
      await openPreview(
        tester,
        data,
        const GbkCodec().encode(unknownCsv),
        (_) {},
      );
      await click(tester, find.widgetWithText(TextButton, '取消').last);
      expect(find.text('核对 CSV 的账户信息'), findsNothing);
      expect(find.byKey(const ValueKey('broker-preview-000001')), findsNothing);
      expect(data.encode(), original);
    },
  );
  testWidgets(
    'mapping dialog rejects known cost and available columns before closing',
    (tester) async {
      final table = inspectBrokerCsv(
        utf8.encode('ID,Label,可卖数量,成本价\n000001,虚构证券,100,12'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrokerCsvMappingDialog(
              table: table,
              initial: {'code': 0, 'name': 1, 'quantity': 2, 'price': 3},
            ),
          ),
        ),
      );
      await click(tester, find.text('应用列映射'));
      expect(find.text('数量需使用总持仓列，不能使用可用或可卖数量'), findsOneWidget);
    },
  );
}
