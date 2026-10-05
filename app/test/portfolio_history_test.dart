import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/portfolio_history.dart';
import 'package:lianghua_assistant/portfolio_import_info.dart';
import 'package:lianghua_assistant/broker_import.dart';

import 'broker_import_test.dart' show snapshotBytes;

Holding holding({
  String id = 'manual-1',
  String code = '600001',
  double quantity = 10,
  double price = 12,
}) => Holding(
  id: id,
  code: code,
  name: '虚构公司',
  industry: '测试行业',
  quantity: quantity,
  price: price,
);
PortfolioImportInfo info() => PortfolioImportInfo(
  broker: '虚构券商',
  accountAlias: '主账户',
  capturedAt: '2026-10-01T09:00:00+08:00',
  importedAt: '2026-10-01T01:00:00Z',
  digest: List.filled(64, 'a').join(),
  format: 'json',
);
WorkspaceData seed() => WorkspaceData.empty().copyWith(
  cash: 100,
  deposits: 1000,
  withdrawals: 200,
  lossBudget: .15,
  priceDate: '2026-10-01',
  holdings: [holding()],
);

void main() {
  test('import history survives portable backup with complete before and after snapshots', () {
    final before = seed();
    final imported = recordPortfolioImport(
      before,
      before.copyWith(
        cash: 200,
        holdings: [holding(quantity: 30)],
        portfolioImport: info(),
      ),
    );
    final reopened = WorkspaceData.decode(imported.encode());
    expect(reopened.encode(), imported.encode());
    expect(reopened.toJson()['schemaVersion'], 8);
    expect(reopened.portfolioHistory.single.before!.assets, 220);
    expect(reopened.portfolioHistory.single.after!.assets, 560);
    expect(
      reopened.portfolioHistory.single.diff!.holdings.single.quantityDelta,
      20,
    );
    expect(reopened.toJson().containsKey('accounts'), isFalse);
  });
  test('restore and undo restore preserve CURRENT funding research reviews and preference', () {
    final original = seed();
    final imported = recordPortfolioImport(
      original,
      original.copyWith(
        cash: 300,
        holdings: [holding(quantity: 30)],
        portfolioImport: info(),
      ),
    );
    final current = imported.copyWith(
      deposits: 9000,
      withdrawals: 700,
      lossBudget: .3,
      studies: const [
        Study(
          id: 'research',
          code: '600001',
          name: '虚构公司',
          business: '导入后更新的业务',
          thesis: '新判断',
          counterEvidence: '',
          reviewCondition: '',
          source: '',
          updatedAt: '2026-10-02',
        ),
      ],
      reviews: const [
        ReviewEntry(
          id: 'review',
          company: '虚构公司',
          text: '导入后复查',
          createdAt: '2026-10-02',
        ),
      ],
    );
    final restored = restorePortfolioHistory(
      current,
      imported.portfolioHistory.single.id,
    );
    expect(restored.cash, original.cash);
    expect(restored.holdings.single.quantity, 10);
    expect(restored.portfolioImport, isNull);
    expect(restored.principal, 8300);
    expect(restored.lossBudget, .3);
    expect(identical(restored.studies, current.studies), isTrue);
    expect(identical(restored.reviews, current.reviews), isTrue);
    final undo = restorePortfolioHistory(
      restored,
      restored.portfolioHistory.last.id,
    );
    expect(undo.cash, 300);
    expect(undo.holdings.single.quantity, 30);
    expect(undo.portfolioImport!.modified, isTrue);
    expect(undo.principal, 8300);
    expect(WorkspaceData.decode(undo.encode()).encode(), undo.encode());
  });
  test('snapshot difference aggregates duplicate securities and includes unchanged, added, removed', () {
    final before = seed().copyWith(
      holdings: [
        holding(id: '1', quantity: 10),
        holding(id: '2', quantity: 10),
        holding(id: '3', code: '000001'),
      ],
    );
    final after = before.copyWith(
      cash: 80,
      holdings: [
        holding(quantity: 20),
        holding(id: '4', code: '300001'),
      ],
    );
    final diff = comparePortfolioSnapshots(
      PortfolioSnapshot.fromWorkspace(before),
      PortfolioSnapshot.fromWorkspace(after),
    );
    expect(diff.holdings.map((h) => h.code), ['000001', '300001', '600001']);
    expect(diff.additions, 1);
    expect(diff.removals, 1);
    expect(diff.changes, 0);
    expect(diff.holdings.last.isChanged, isFalse);
    expect(diff.cashDelta, -20);
    expect(diff.assetsDelta, -20);
  });
  test(
    'fixed failures deduplicate and never capture exception or path text',
    () {
      final original = seed();
      final failed = recordPortfolioFailure(original, 'read_failed');
      expect(
        identical(recordPortfolioFailure(failed, 'read_failed'), failed),
        isTrue,
      );
      expect(failed.cash, original.cash);
      expect(failed.holdings, original.holdings);
      expect(failed.portfolioHistory.single.canRestore, isFalse);
      expect(
        () => recordPortfolioFailure(failed, 'C:/private/token'),
        throwsFormatException,
      );
      expect(
        () => recordPortfolioFailure(
          failed,
          'read_failed',
          safeMessage: 'C:/private/token',
        ),
        throwsFormatException,
      );
      final tampered = failed.toJson();
      tampered['portfolioHistory'][0]['error'] = 'Exception with token';
      expect(
        () => WorkspaceData.decode(jsonEncode(tampered)),
        throwsFormatException,
      );
    },
  );
  test('twenty-entry pruning protects latest reversible entry through repeated failures', () {
    var data = seed();
    data = recordPortfolioImport(data, data.copyWith(cash: 200));
    final reversibleId = data.portfolioHistory.single.id;
    for (var i = 0; i < 30; i++) {
      data = recordPortfolioFailure(
        data,
        i.isEven ? 'read_failed' : 'invalid_snapshot',
      );
    }
    expect(data.portfolioHistory.length, 20);
    expect(data.portfolioHistory.first.id, reversibleId);
    expect(restorePortfolioHistory(data, reversibleId).cash, 100);
  });
  test('whole backup budget rejects new history without discarding current research', () {
    final base = seed().copyWith(
      reviews: const [
        ReviewEntry(
          id: 'large',
          company: '虚构公司',
          text: 'x',
          createdAt: '2026-10-01',
        ),
      ],
    );
    final text = List.filled(8000000 - base.encode().length - 100, 'x').join();
    final large = base.copyWith(
      reviews: [
        ReviewEntry(
          id: 'large',
          company: '虚构公司',
          text: text,
          createdAt: '2026-10-01',
        ),
      ],
    );
    expect(large.encode().length, lessThan(8000000));
    expect(
      () => recordPortfolioImport(large, large.copyWith(cash: 300)),
      throwsFormatException,
    );
    expect(large.portfolioHistory, isEmpty);
    expect(large.cash, 100);
    expect(large.reviews.single.text.length, text.length);
  });
  test('strict snapshot persistence rejects malformed numbers identity dates and securities', () {
    final baseline = PortfolioSnapshot.fromWorkspace(seed()).toJson();
    for (final invalid in [-1, double.infinity, double.nan, '123']) {
      final j = Map<String, dynamic>.from(baseline)..['cash'] = invalid;
      expect(() => PortfolioSnapshot.fromJson(j), throwsFormatException);
    }
    for (final invalid in ['', '  ']) {
      final j = PortfolioSnapshot.fromWorkspace(
        seed().copyWith(holdings: [holding(code: invalid)]),
      ).toJson();
      expect(() => PortfolioSnapshot.fromJson(j), throwsFormatException);
    }
    for (final quantity in [-1.0, .5, double.nan, double.infinity]) {
      final j = PortfolioSnapshot.fromWorkspace(
        seed().copyWith(holdings: [holding(quantity: quantity)]),
      ).toJson();
      expect(() => PortfolioSnapshot.fromJson(j), throwsFormatException);
    }
    expect(
      () =>
          PortfolioSnapshot.fromJson({...baseline, 'priceDate': '2026-02-30'}),
      throwsFormatException,
    );
    expect(
      () => PortfolioSnapshot.fromJson({
        ...baseline,
        'holdings': [holding().toJson(), holding().toJson()],
      }),
      throwsFormatException,
    );
    expect(
      () => PortfolioSnapshot.fromJson({
        ...baseline,
        'holdings': [holding(price: -1).toJson()],
      }),
      throwsFormatException,
    );
  });
  test('reviewed broker import can restore all valid older manual fields', () {
    final legacy = seed().copyWith(
      cash: 1e13,
      holdings: [holding(code: '旧手工代码', quantity: 1e13, price: 0)],
    );
    expect(WorkspaceData.decode(legacy.encode()).encode(), legacy.encode());
    final imported = recordPortfolioImport(
      legacy,
      applyBrokerSnapshot(
        legacy,
        parseBrokerFile(snapshotBytes()),
        sourceChangeConfirmed: true,
      ),
    );
    final restored = restorePortfolioHistory(
      WorkspaceData.decode(imported.encode()),
      imported.portfolioHistory.single.id,
    );
    expect(restored.cash, legacy.cash);
    expect(restored.holdings.single.toJson(), legacy.holdings.single.toJson());
    expect(restored.priceDate, legacy.priceDate);
    expect(restored.portfolioImport, isNull);
    expect(WorkspaceData.decode(restored.encode()).cash, legacy.cash);
    expect(() {
      final invalid = jsonDecode(utf8.decode(snapshotBytes()));
      invalid['holdings'][0]['price'] = 0;
      return parseBrokerFile(utf8.encode(jsonEncode(invalid)));
    }, throwsFormatException);
  });
  test('history validates timestamp duplicate IDs action reference and rejects schema5', () {
    final data = recordPortfolioImport(seed(), seed().copyWith(cash: 200));
    final invalids = <Map<String, dynamic>>[
      {'timestamp': '2026-10-01T25:00:00Z'},
      {'timestamp': '2026-10-01T01:00:00'},
      {'action': 'trade'},
      {'action': 'restore'},
      {'referenceId': 'unknown'},
    ];
    for (final fields in invalids) {
      final j = data.toJson();
      (j['portfolioHistory'][0] as Map).addAll(fields);
      expect(() => WorkspaceData.decode(jsonEncode(j)), throwsFormatException);
    }
    final duplicate = data.toJson();
    duplicate['portfolioHistory'].add(duplicate['portfolioHistory'][0]);
    expect(
      () => WorkspaceData.decode(jsonEncode(duplicate)),
      throwsFormatException,
    );
    expect(
      () => WorkspaceData.decode(
        jsonEncode(data.toJson()..['schemaVersion'] = 5),
      ),
      throwsFormatException,
    );
    expect(
      () => restorePortfolioHistory(seed(), 'absent'),
      throwsFormatException,
    );
    expect(
      () => recordPortfolioImport(WorkspaceData.demo(), seed()),
      throwsFormatException,
    );
  });
}
