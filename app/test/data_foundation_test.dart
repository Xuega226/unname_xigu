import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/data_foundation.dart';
import 'package:lianghua_assistant/services.dart';

class FakeHistoryTransport implements JsonTransport {
  FakeHistoryTransport(this.response);
  Map<String, dynamic> response;
  Uri? requested;
  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    requested = uri;
    return response;
  }
}

Map<String, dynamic> historyJson() => {
  'id': 'history-SH-600001',
  'symbol': 'SH:600001',
  'adjustment': 'unadjusted',
  'source': 'https://example.org/fictional-history',
  'fetchedAt': '2026-10-05T10:00:00Z',
  'bars': [
    {'date': '2026-09-29', 'close': 10},
    {'date': '2026-09-30', 'close': 12},
  ],
};

Map<String, dynamic> response(List<dynamic> rows) => {
  'rc': 0,
  'data': {'code': '600001', 'market': 1, 'klines': rows},
};
String row(String date, [String close = '10']) =>
    '$date,10,$close,12,9,100,1000,1,2,3,4';

void main() {
  test('history retains provenance, identity, order and exact round trip', () {
    final h = PriceHistory.fromJson(historyJson());
    expect(PriceHistory.decode(h.encode()).toJson(), h.toJson());
    expect(h.bars.last.close / h.bars.first.close - 1, closeTo(0.2, 1e-10));
    expect(
      () => h.bars.add(HistoryBar(date: '2026-10-01', close: 9)),
      throwsUnsupportedError,
    );
  });

  test('history rejects wrong identity, adjustment, source and timestamp', () {
    for (final change in [
      {'symbol': 'SZ:600001'},
      {'adjustment': 'forward'},
      {'source': 'http://example.org/price'},
      {'source': 'https://user:secret@example.org'},
      {'fetchedAt': '2026-10-05T10:00:00'},
      {'fetchedAt': '2026-02-30T10:00:00Z'},
      {'fetchedAt': '2026-10-05T25:00:00Z'},
      {'fetchedAt': '2026-10-05T10:00:00+99:99'},
      {'fetchedAt': '2026-10-05T10:00:00+15:00'},
      {'fetchedAt': '2026-10-05T10:00:00+14:01'},
    ]) {
      expect(
        () => PriceHistory.fromJson({...historyJson(), ...change}),
        throwsFormatException,
      );
    }
  });

  test('history refuses duplicated, unordered, impossible and future bars', () {
    for (final bars in [
      [
        {'date': '2026-09-30', 'close': 10},
        {'date': '2026-09-30', 'close': 11},
      ],
      [
        {'date': '2026-09-30', 'close': 10},
        {'date': '2026-09-29', 'close': 11},
      ],
      [
        {'date': '2026-02-30', 'close': 10},
      ],
      [
        {'date': '2026-10-06', 'close': 10},
      ],
      [
        {'date': '2026-09-30', 'close': 0},
      ],
      [
        {'date': '2026-09-30', 'close': double.nan},
      ],
      <dynamic>[],
    ]) {
      expect(
        () => PriceHistory.fromJson({...historyJson(), 'bars': bars}),
        throwsFormatException,
      );
    }
    expect(
      () => PriceHistory.fromJson({
        ...historyJson(),
        'bars': List.filled(501, {'date': '2026-09-30', 'close': 10}),
      }),
      throwsFormatException,
    );
  });

  test('public history requests unadjusted data and discards only validated partial today', () async {
    final t = FakeHistoryTransport(
      response([row('2026-09-30', '10'), row('2026-10-05', '12')]),
    );
    final service = MarketHistoryService(
      transport: t,
      clock: () => DateTime.utc(2026, 10, 5, 8),
    );
    final h = await service.history('SH:600001');
    expect(h.bars.map((b) => b.date), ['2026-09-30']);
    expect(t.requested!.queryParameters['fqt'], '0');
    expect(t.requested!.queryParameters['lmt'], '500');
    expect(t.requested!.queryParameters['end'], '20261004');
    expect(h.source, t.requested.toString());
    expect(h.fetchedAt, '2026-10-05T08:00:00.000Z');
    final after = await MarketHistoryService(
      transport: t,
      clock: () => DateTime.utc(2026, 10, 5, 10),
    ).history('SH:600001');
    expect(after.bars.length, 2);
  });

  test('public history rejects bad row instead of silently filtering, even partial day', () async {
    for (final rows in [
      [row('2026-09-30'), row('2026-10-05', 'NaN')],
      [row('2026-09-30'), 12],
      [row('2026-09-30'), row('2026-10-06')],
      [row('2026-09-30'), row('2026-09-30')],
      [row('2026-09-30'), row('2026-09-29')],
      [row('2026-02-30')],
    ]) {
      final t = FakeHistoryTransport(response(rows));
      await expectLater(
        MarketHistoryService(
          transport: t,
          clock: () => DateTime.utc(2026, 10, 5, 8),
        ).history('SH:600001'),
        throwsA(isA<ServiceFailure>()),
      );
    }
  });

  test('public history rejects response identity mismatch and empty/oversized response', () async {
    for (final json in [
      {
        'rc': 0,
        'data': {
          'code': '000001',
          'market': 1,
          'klines': [row('2026-09-30')],
        },
      },
      {
        'rc': 0,
        'data': {
          'code': '600001',
          'market': 0,
          'klines': [row('2026-09-30')],
        },
      },
      response([]),
      response(List.filled(501, row('2026-09-30'))),
    ]) {
      await expectLater(
        MarketHistoryService(
          transport: FakeHistoryTransport(json),
          clock: () => DateTime.utc(2026, 10, 5, 10),
        ).history('SH:600001'),
        throwsA(isA<ServiceFailure>()),
      );
    }
  });

  test(
    'funding preserves undocumented opening totals and adds exact cents',
    () {
      final ledger = FundingLedger(
        coverageStart: '2026-09-01',
        openingDeposits: 1000.10,
        openingWithdrawals: 100.20,
        entries: [
          DatedCashFlow(
            id: 'in',
            date: '2026-09-02',
            kind: CashFlowKind.deposit,
            amount: 200.30,
            source: '手动录入',
          ),
          DatedCashFlow(
            id: 'out',
            date: '2026-09-03',
            kind: CashFlowKind.withdrawal,
            amount: 50.40,
            source: '银行流水核对',
          ),
        ],
      );
      expect(ledger.deposits, 1200.40);
      expect(ledger.withdrawals, 150.60);
      expect(ledger.principal, closeTo(1049.80, 1e-10));
      expect(FundingLedger.fromJson(ledger.toJson()).toJson(), ledger.toJson());
      expect(ledger.copyWith(entries: []).deposits, 1000.10);
      expect(() => ledger.entries.clear(), throwsUnsupportedError);
    },
  );

  test('funding refuses false precision, overflow, duplicates and dates before coverage', () {
    DatedCashFlow flow({String id = 'same', String date = '2026-09-02'}) =>
        DatedCashFlow(
          id: id,
          date: date,
          kind: CashFlowKind.deposit,
          amount: 1,
          source: '手动录入',
        );
    for (final n in [0.0, -1.0, 1.001, double.infinity, double.nan, 1e12 + 1]) {
      expect(
        () => DatedCashFlow(
          id: 'x',
          date: '2026-09-02',
          kind: CashFlowKind.deposit,
          amount: n,
          source: '手动录入',
        ),
        throwsFormatException,
      );
    }
    for (final entries in [
      [flow(), flow()],
      [flow(date: '2026-08-31')],
      List.generate(1001, (i) => flow(id: '$i')),
    ]) {
      expect(
        () => FundingLedger(
          coverageStart: '2026-09-01',
          openingDeposits: 100,
          openingWithdrawals: 0,
          entries: entries,
        ),
        throwsFormatException,
      );
    }
    final legacy = FundingLedger(
      coverageStart: '2026-09-01',
      openingDeposits: 1e13,
      openingWithdrawals: 1.1234,
      entries: [],
    );
    expect(legacy.deposits, 1e13);
    expect(legacy.withdrawals, 1.1234);
    expect(FundingLedger.fromJson(legacy.toJson()).withdrawals, 1.1234);
    // Decoding old state deliberately does not depend on today's system clock.
    expect(
      FundingLedger(
        coverageStart: '2099-01-01',
        openingDeposits: 0,
        openingWithdrawals: 0,
        entries: [],
      ).coverageStart,
      '2099-01-01',
    );
  });
}
