import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_import.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/broker_widgets.dart';
import 'package:lianghua_assistant/domain.dart';

import 'broker_import_test.dart' show snapshotBytes, snapshotJson;

class PreviewFiles extends BrokerImportService {
  PreviewFiles(this.bytes);
  final List<int> bytes;
  @override
  Future<SelectedPortfolioFile?> pick() async => SelectedPortfolioFile(
    bytes: bytes,
    name: '完整虚构账户.json',
    path: 'test-only.json',
  );
}

Future<void> click(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> openPreview(
  WidgetTester tester,
  WorkspaceData data,
  List<int> bytes,
  ValueChanged<BrokerImportSelection?> selected,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () async => selected(
                await showDialog<BrokerImportSelection>(
                  context: context,
                  builder: (_) => BrokerImportDialog(
                    data: data,
                    importer: PreviewFiles(bytes),
                  ),
                ),
              ),
              child: const Text('打开预览'),
            ),
          );
        },
      ),
    ),
  );
  await click(tester, find.text('打开预览'));
  await click(tester, find.text('选择持仓文件'));
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
    testWidgets('all 80 new and removed holdings can be reviewed at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final input = snapshotJson();
      input['holdings'] = [
        for (var i = 1; i <= 80; i++)
          {
            'code': i.toString().padLeft(6, '0'),
            'name': '新增$i',
            'quantity': i + 100,
            'price': i + .5,
          },
      ];
      final data = WorkspaceData.empty().copyWith(
        priceDate: '2026-10-01',
        holdings: [
          const Holding(
            id: 'retained',
            code: '000001',
            name: '原证券',
            industry: '测试',
            quantity: 3,
            price: 4,
          ),
          for (var i = 1; i <= 80; i++)
            Holding(
              id: 'old$i',
              code: '${600000 + i}',
              name: '移除$i',
              industry: '测试',
              quantity: i.toDouble(),
              price: i + .25,
            ),
        ],
      );
      final before = data.encode();
      BrokerImportSelection? selected;
      await openPreview(
        tester,
        data,
        utf8.encode(jsonEncode(input)),
        (value) => selected = value,
      );
      expect(find.textContaining('原 3 股 · 原市价 4.00'), findsOneWidget);
      final incoming = <String>{}, removed = <String>{};
      for (var page = 0; page < 4; page++) {
        final first = page * 25 + 1;
        final last = (first + 24).clamp(1, 80);
        for (var i = first; i <= last; i++) {
          final code = i.toString().padLeft(6, '0');
          final oldCode = '${600000 + i}';
          expect(find.byKey(ValueKey('broker-preview-$code')), findsOneWidget);
          expect(
            find.byKey(ValueKey('broker-removed-$oldCode')),
            findsOneWidget,
          );
          incoming.add(code);
          removed.add(oldCode);
        }
        final newNext = find.byKey(const ValueKey('broker-持仓-next'));
        final oldNext = find.byKey(const ValueKey('broker-移除-next'));
        if (page < 3) {
          await click(tester, newNext);
          await click(tester, oldNext);
        } else {
          expect(tester.widget<TextButton>(newNext).onPressed, isNull);
          expect(tester.widget<TextButton>(oldNext).onPressed, isNull);
        }
      }
      expect(incoming.length, 80);
      expect(removed.length, 80);
      await click(tester, find.byKey(const ValueKey('broker-持仓-previous')));
      expect(
        find.byKey(const ValueKey('broker-preview-000051')),
        findsOneWidget,
      );
      await click(tester, find.text('取消'));
      expect(selected, isNull);
      expect(data.encode(), before);
      expect(tester.takeException(), isNull);
    });
  }

  for (final existingSource in [false, true]) {
    testWidgets(
      'source ownership confirmation gates import existing=$existingSource',
      (tester) async {
        final first = parseBrokerFile(snapshotBytes());
        final data = WorkspaceData.empty().copyWith(
          priceDate: '2026-10-01',
          deposits: 10000,
          withdrawals: 500,
          portfolioImport: existingSource ? first.info : null,
        );
        final before = data.encode();
        BrokerImportSelection? selected;
        await openPreview(
          tester,
          data,
          snapshotBytes(alias: '新的别名'),
          (value) => selected = value,
        );
        final confirm = find.widgetWithText(FilledButton, '确认导入');
        await click(tester, find.text('已核对账户、完整持仓、现金和估值日期'));
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        expect(find.textContaining('不能根据当前资产倒推本金'), findsOneWidget);
        await click(
          tester,
          find.byKey(const ValueKey('broker-source-confirmation')),
        );
        expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
        await click(tester, confirm);
        expect(selected!.sourceChangeConfirmed, isTrue);
        expect(data.encode(), before);
      },
    );
  }

  testWidgets(
    'same source needs only normal review and returns no source override',
    (tester) async {
      final first = parseBrokerFile(snapshotBytes());
      final data = WorkspaceData.empty().copyWith(
        priceDate: '2026-10-01',
        deposits: 10000,
        portfolioImport: first.info,
      );
      BrokerImportSelection? selected;
      await openPreview(
        tester,
        data,
        snapshotBytes(),
        (value) => selected = value,
      );
      expect(
        find.byKey(const ValueKey('broker-source-confirmation')),
        findsNothing,
      );
      await click(tester, find.text('已核对账户、完整持仓、现金和估值日期'));
      await click(tester, find.text('确认导入'));
      expect(selected!.sourceChangeConfirmed, isFalse);
    },
  );
}
