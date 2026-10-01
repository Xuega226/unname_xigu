import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';

void main() {
  test('portfolio weights include cash; stress is a weighted scenario', () {
    final data = WorkspaceData.demo();
    expect(data.assets, 95000);
    expect(data.profitRate, closeTo(-.05, 1e-10));
    expect(data.stockWeight, closeTo(55000 / 95000, 1e-10));
    expect(data.weight(data.holdings.first), closeTo(20000 / 95000, 1e-10));
    expect(data.stressLoss(.4), closeTo(22000 / 95000, 1e-10));
    expect(data.industries['制造'], 20000);
  });
  test(
      'empty account and nonpositive principal do not produce misleading ratios',
      () {
    final data = WorkspaceData.empty();
    expect(data.profitRate, isNull);
    expect(data.stockWeight, isNull);
    expect(data.stressLoss(.3), isNull);
    expect(
        data.copyWith(cash: 5000, deposits: 1000, withdrawals: 2000).profitRate,
        isNull);
  });
  test('cash flows change principal; stock transactions do not', () {
    final data =
        WorkspaceData.demo().copyWith(deposits: 120000, withdrawals: 20000);
    expect(data.principal, 100000);
    expect(data.profitRate, closeTo(-.05, 1e-10));
  });
  test('backup roundtrip retains identifiers, mode, budget and source gaps',
      () {
    final original = WorkspaceData.demo();
    final restored = WorkspaceData.decode(original.encode());
    expect(restored.encode(), original.encode());
    expect(restored.isDemo, isTrue);
    expect(restored.studies.first.source, isEmpty);
  });
  test('invalid imports fail before they can replace existing records', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (j) => j['schemaVersion'] = 99,
      (j) => j['cash'] = -1,
      (j) => j['lossBudget'] = 1.1,
      (j) => j['priceDate'] = '2026-02-31',
      (j) => j['holdings'][0]['quantity'] = 1.5,
      (j) => j['holdings'][0]['code'] = '',
      (j) => j['holdings'][1]['id'] = j['holdings'][0]['id'],
      (j) => j['studies'] = 'invalid',
    ]) {
      final json = WorkspaceData.demo().toJson();
      change(json);
      expect(
          () => WorkspaceData.decode(jsonEncode(json)), throwsFormatException);
    }
    expect(() => WorkspaceData.demo().stressLoss(1.2), throwsArgumentError);
  });
}
