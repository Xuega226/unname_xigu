import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/data_foundation.dart';
import 'package:lianghua_assistant/data_foundation_widgets.dart';
import 'package:lianghua_assistant/domain.dart';

import 'data_foundation_test.dart'
    show historyJson, FakeHistoryTransport, response, row;

Future<void> click(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty &&
      find.byKey(const Key('funding-details')).evaluate().isNotEmpty) {
    await tester.ensureVisible(find.byKey(const Key('funding-details')));
    await tester.tap(find.byKey(const Key('funding-details')));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class Harness extends StatefulWidget {
  const Harness({
    super.key,
    required this.initial,
    required this.saved,
    this.fail = false,
    this.scale = 1,
    this.service,
  });
  final WorkspaceData initial;
  final ValueChanged<WorkspaceData> saved;
  final bool fail;
  final double scale;
  final MarketHistoryService? service;
  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  late WorkspaceData data = widget.initial;
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(widget.scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: QuantDataPanel(
            data: data,
            historyService: widget.service,
            onSave: (next) async {
              if (widget.fail) return false;
              widget.saved(next);
              setState(() => data = next);
              return true;
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'history preview cancel and save failure preserve all old fields',
    (tester) async {
      final original = WorkspaceData.empty().copyWith(
        cash: 200,
        deposits: 1000,
      );
      var calls = 0;
      await tester.pumpWidget(
        Harness(initial: original, fail: true, saved: (_) => calls++),
      );
      await click(tester, find.byKey(const Key('history-import-json')));
      await tester.enterText(
        find.byKey(const Key('history-json-input')),
        jsonEncode(historyJson()),
      );
      await click(tester, find.text('校验并预览'));
      expect(find.text('确认新增历史序列'), findsOneWidget);
      await click(tester, find.text('取消'));
      expect(calls, 0);
      await click(tester, find.byKey(const Key('history-import-json')));
      await tester.enterText(
        find.byKey(const Key('history-json-input')),
        jsonEncode(historyJson()),
      );
      await click(tester, find.text('校验并预览'));
      await click(tester, find.byKey(const Key('history-confirm-save')));
      expect(find.text('保存失败，旧历史已保留，可以重试或取消'), findsOneWidget);
      expect(calls, 0);
      await click(tester, find.text('取消'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history import replacement is confirmed and never updates holdings or funds',
    (tester) async {
      final original = WorkspaceData.empty().copyWith(
        cash: 200,
        deposits: 1000,
        holdings: [
          const Holding(
            id: 'h',
            code: '600001',
            name: '虚构公司',
            industry: '测试',
            quantity: 2,
            price: 20,
          ),
        ],
      );
      WorkspaceData? saved;
      await tester.pumpWidget(
        Harness(initial: original, saved: (next) => saved = next),
      );
      Future<void> import(Map<String, dynamic> json) async {
        await click(tester, find.byKey(const Key('history-import-json')));
        await tester.enterText(
          find.byKey(const Key('history-json-input')),
          jsonEncode(json),
        );
        await click(tester, find.text('校验并预览'));
      }

      await import(historyJson());
      expect(saved, isNull);
      await click(tester, find.byKey(const Key('history-confirm-save')));
      expect(saved!.priceHistory.length, 1);
      expect(saved!.holdings.single.price, 20);
      expect(saved!.cash, 200);
      expect(saved!.deposits, 1000);
      final changed = {
        ...historyJson(),
        'bars': [
          {'date': '2026-09-30', 'close': 999},
        ],
      };
      await import(changed);
      expect(find.text('确认替换 SH:600001 的历史序列'), findsOneWidget);
      await click(tester, find.text('取消'));
      expect(saved!.priceHistory.single.bars.last.close, 12);
      await import(changed);
      await click(tester, find.byKey(const Key('history-confirm-save')));
      expect(saved!.priceHistory.single.bars.last.close, 999);
      expect(saved!.holdings.single.price, 20);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bad public response leaves history untouched and never saves', (
    tester,
  ) async {
    var saves = 0;
    final t = FakeHistoryTransport(response([row('2026-09-30'), 'bad-row']));
    await tester.pumpWidget(
      Harness(
        initial: WorkspaceData.empty(),
        saved: (_) => saves++,
        service: MarketHistoryService(
          transport: t,
          clock: () => DateTime.utc(2026, 10, 5, 10),
        ),
      ),
    );
    await click(tester, find.byKey(const Key('history-fetch')));
    await click(tester, find.text('获取并预览'));
    expect(saves, 0);
    expect(
      find.text('历史行情获取或校验失败，旧历史已保留；可检查代码、网络或改用 JSON 导入。'),
      findsOneWidget,
    );
  });

  testWidgets(
    'funding opening totals remain intact; additions and confirmed deletion change principal only',
    (tester) async {
      WorkspaceData? saved;
      await tester.pumpWidget(
        Harness(
          initial: WorkspaceData.empty().copyWith(
            cash: 300,
            deposits: 1000,
            withdrawals: 100,
          ),
          saved: (next) => saved = next,
        ),
      );
      await click(tester, find.byKey(const Key('funding-enable')));
      await tester.enterText(
        find.byKey(const Key('funding-start-input')),
        '2026-09-01',
      );
      await click(tester, find.byKey(const Key('funding-enable-confirm')));
      expect(saved!.funding!.openingDeposits, 1000);
      expect(saved!.principal, 900);
      await click(tester, find.byKey(const Key('funding-add')));
      await tester.enterText(
        find.byKey(const Key('funding-date-input')),
        '2026-09-02',
      );
      await tester.enterText(
        find.byKey(const Key('funding-amount-input')),
        '123.45',
      );
      await click(tester, find.byKey(const Key('funding-flow-save')));
      expect(saved!.principal, closeTo(1023.45, 1e-8));
      expect(saved!.cash, 300);
      final id = saved!.funding!.entries.single.id;
      await click(tester, find.byKey(Key('funding-delete-$id')));
      await click(tester, find.text('取消'));
      expect(saved!.funding!.entries.length, 1);
      await click(tester, find.byKey(Key('funding-delete-$id')));
      await click(tester, find.text('确认'));
      expect(saved!.funding!.entries, isEmpty);
      expect(saved!.principal, 900);
      expect(saved!.cash, 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'future date and failed flow persistence leave cumulative totals unchanged',
    (tester) async {
      final ledger = FundingLedger(
        coverageStart: '2026-09-01',
        openingDeposits: 1000,
        openingWithdrawals: 100,
        entries: [],
      );
      var saves = 0;
      await tester.pumpWidget(
        Harness(
          initial: WorkspaceData.empty().copyWith(
            funding: ledger,
            deposits: 1000,
            withdrawals: 100,
          ),
          fail: true,
          saved: (_) => saves++,
        ),
      );
      await click(tester, find.byKey(const Key('funding-add')));
      await tester.enterText(
        find.byKey(const Key('funding-date-input')),
        '2099-01-01',
      );
      await tester.enterText(
        find.byKey(const Key('funding-amount-input')),
        '123.45',
      );
      await click(tester, find.byKey(const Key('funding-flow-save')));
      expect(find.text('发生日期须有效且不在未来'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('funding-date-input')),
        '2026-09-02',
      );
      await click(tester, find.byKey(const Key('funding-flow-save')));
      expect(find.text('保存失败，流水与累计本金未改变'), findsOneWidget);
      expect(saves, 0);
      await click(tester, find.text('取消'));
      expect(find.textContaining('净本金 900.00'), findsOneWidget);
    },
  );

  testWidgets(
    '390px with double text supports complete ledger paging without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ledger = FundingLedger(
        coverageStart: '2026-09-01',
        openingDeposits: 1000,
        openingWithdrawals: 100,
        entries: [
          for (var i = 0; i < 25; i++)
            DatedCashFlow(
              id: '$i',
              date: '2026-09-02',
              kind: CashFlowKind.deposit,
              amount: 1,
              source: '手动录入与银行凭证核对记录 $i',
            ),
        ],
      );
      await tester.pumpWidget(
        Harness(
          initial: WorkspaceData.empty().copyWith(
            funding: ledger,
            deposits: ledger.deposits,
            withdrawals: ledger.withdrawals,
            priceHistory: [PriceHistory.fromJson(historyJson())],
          ),
          scale: 2,
          saved: (_) {},
        ),
      );
      expect(find.byKey(const Key('funding-delete-0')), findsNothing);
      await click(tester, find.byKey(const Key('funding-details')));
      expect(find.byKey(const Key('funding-delete-0')), findsOneWidget);
      expect(find.byKey(const Key('funding-delete-24')), findsNothing);
      await click(tester, find.byKey(const Key('funding-next')));
      expect(find.byKey(const Key('funding-delete-24')), findsOneWidget);
      expect(find.text('2/2 · 共 25 条'), findsOneWidget);
      await click(tester, find.byKey(const Key('funding-edit-24')));
      await tester.enterText(
        find.byKey(const Key('funding-amount-input')),
        '2',
      );
      await click(tester, find.text('取消'));
      expect(tester.takeException(), isNull);
    },
  );
}
