import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/quant_models.dart';
import 'package:lianghua_assistant/quant_engine.dart';
import 'package:lianghua_assistant/data_foundation.dart';

QuantRule rule(
  QuantFactor f, {
  double t = 0,
  double w = 1,
  bool filter = false,
  String? id,
}) => QuantRule(
  id: id ?? f.name,
  factor: f,
  comparison: QuantComparison.gte,
  threshold: t,
  weight: w,
  filter: filter,
);
QuantConfig cfg(
  List<QuantRule> rules, {
  String date = '2026-06-01',
  bool confirmed = true,
}) => QuantConfig(
  id: 'q',
  revision: 1,
  name: '规则',
  asOfDate: date,
  momentumWindow: 2,
  rules: rules,
  confirmed: confirmed,
  confirmedAt: confirmed ? '2026-06-01T00:00:00+08:00' : null,
);
const co = WatchCompany(
  id: 'w',
  code: '600001',
  exchange: 'SH',
  name: '虚构制造',
  industry: '制造',
  source: 'https://example.com/company',
  fetchedAt: '2026-06-01T00:00:00+08:00',
);
const st = Study(
  id: 's',
  code: '600001',
  name: '虚构制造',
  business: '',
  thesis: '',
  counterEvidence: '',
  reviewCondition: '',
  source: '',
  updatedAt: '2026-06-01',
);
SourceExcerpt src(int y, {String? date}) => SourceExcerpt(
  id: 'src$y',
  studyId: 's',
  title: '年报',
  url: 'https://example.com/report',
  period: '$y年',
  disclosedAt: date ?? '${y + 1}-04-01',
  page: '1',
  unit: '万元',
  text: '核验原文',
);
FinancialRecord fin(
  int y, {
  double? revenue = 100,
  double? profit = 20,
  double? debt = 10,
  String? id,
  String basis = '原披露',
  String scope = '合并',
  String unit = '万元',
}) => FinancialRecord(
  id: id ?? 'f$y',
  studyId: 's',
  sourceId: 'src$y',
  start: '$y-01-01',
  end: '$y-12-31',
  disclosedAt: '${y + 1}-04-01',
  unit: unit,
  revenue: revenue,
  adjustedProfit: profit,
  operatingCash: 40,
  cash: 30,
  debt: debt,
  scope: scope,
  basis: basis,
);
PriceHistory prices(String id, String symbol, {double end = 12}) =>
    PriceHistory(
      id: id,
      symbol: symbol,
      source: 'https://example.com/prices',
      fetchedAt: co.fetchedAt,
      bars: [
        HistoryBar(date: '2026-05-27', close: 10),
        HistoryBar(date: '2026-05-28', close: 11),
        HistoryBar(date: '2026-05-29', close: end),
      ],
    );
WorkspaceData ws(
  QuantConfig config, {
  List<FinancialRecord>? financials,
  List<SourceExcerpt>? sources,
  List<PriceHistory>? history,
  List<ShareCapitalFact> facts = const [],
  List<WatchCompany> companies = const [co],
}) => WorkspaceData(
  isDemo: false,
  cash: 0,
  deposits: 0,
  withdrawals: 0,
  lossBudget: 0.1,
  priceDate: '2026-05-29',
  holdings: const [
    Holding(
      id: 'h',
      code: '600001',
      name: '虚构制造',
      industry: '制造',
      quantity: 100,
      price: 12,
    ),
  ],
  studies: const [st],
  reviews: const [],
  watchlist: companies,
  sources: sources ?? [src(2024), src(2025)],
  financials: financials ?? [fin(2024, revenue: 80, profit: 10), fin(2025)],
  quant: QuantState(versions: [config], shareFacts: facts),
  priceHistory: history ?? [prices('p', co.symbol)],
);
QuantFactorValue val(WorkspaceData data) =>
    evaluateQuant(data).rows.single.rules.single.value;
const shares = ShareCapitalFact(
  id: 'share',
  symbol: 'SH:600001',
  effectiveDate: '2025-12-31',
  disclosedAt: '2026-04-01',
  totalShares: 100000,
  sourceId: 'src2025',
  verified: true,
);
void main() {
  test('全部公式手算、单位归一和持仓不能代替股本', () {
    final expected = {
      QuantFactor.adjustedProfitMargin: 20.0,
      QuantFactor.revenueGrowth: 25.0,
      QuantFactor.profitGrowth: 100.0,
      QuantFactor.cashProfitRatio: 2.0,
      QuantFactor.cashDebtRatio: 3.0,
      QuantFactor.close: 12.0,
      QuantFactor.momentum: 20.0,
      QuantFactor.priceSalesRatio: 1.2,
    };
    for (final e in expected.entries) {
      final v = val(ws(cfg([rule(e.key)]), facts: [shares]));
      expect(v.value, closeTo(e.value, 1e-9));
      expect(v.evidence, isNotEmpty);
      expect(v.formula, isNotEmpty);
    }
    expect(val(ws(cfg([rule(QuantFactor.priceSalesRatio)]))).value, isNull);
  });
  test('缺值不重分配权重且不能入选', () {
    final r = evaluateQuant(
      ws(
        cfg([
          rule(QuantFactor.adjustedProfitMargin, w: 99),
          rule(QuantFactor.cashDebtRatio),
        ]),
        financials: [fin(2025, debt: null)],
      ),
    ).rows.single;
    expect(r.score, isNull);
    expect(r.selected, false);
    expect(r.rules.first.contribution, 99);
  });
  test('阈值与权重以及独立筛选', () {
    final config = cfg([
      rule(QuantFactor.adjustedProfitMargin, t: 10, w: 3),
      rule(QuantFactor.cashDebtRatio, t: 4, filter: true),
    ]);
    final a = evaluateQuant(ws(config)).rows.single;
    expect(a.score, 75);
    expect(a.selected, false);
    final b = evaluateQuant(
      ws(
        config.copyWith(
          rules: [
            rule(QuantFactor.adjustedProfitMargin, t: 30, w: 1),
            rule(QuantFactor.cashDebtRatio, t: 2, w: 3),
          ],
        ),
      ),
    ).rows.single;
    expect(b.score, 75);
    expect(b.selected, true);
  });
  test('同日和未来披露排除，来源披露也严格校验', () {
    for (final date in ['2026-04-01', '2026-03-31']) {
      expect(
        val(ws(cfg([rule(QuantFactor.adjustedProfitMargin)], date: date)))
            .value,
        12.5,
      );
    }
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.adjustedProfitMargin)]),
          sources: [src(2025, date: '2026-06-01')],
        ),
      ).value,
      isNull,
    );
  });
  test('最新缺值不可用旧年度掩盖，重述不同口径排除', () {
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.adjustedProfitMargin)]),
          financials: [
            fin(2024),
            fin(2025, revenue: null),
            fin(2025, basis: '重述', id: 'revision'),
          ],
        ),
      ).value,
      isNull,
    );
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.adjustedProfitMargin)]),
          financials: [
            fin(2024),
            fin(2025, scope: '母公司'),
          ],
        ),
      ).evidence.first.period,
      contains('2024'),
    );
  });
  test('年度冲突和非相邻同比', () {
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.revenueGrowth)]),
          financials: [
            fin(2025),
            fin(2025, id: 'second'),
          ],
        ),
      ).reason,
      contains('冲突'),
    );
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.revenueGrowth)]),
          financials: [fin(2023), fin(2025)],
        ),
      ).reason,
      contains('相邻'),
    );
  });
  test('零负分母未知，负当期同比保留', () {
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.cashDebtRatio)]),
          financials: [fin(2025, debt: 0)],
        ),
      ).value,
      isNull,
    );
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.profitGrowth)]),
          financials: [fin(2024, profit: 10), fin(2025, profit: -5)],
        ),
      ).value,
      -150,
    );
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.cashProfitRatio)]),
          financials: [fin(2025, profit: -5)],
        ),
      ).value,
      isNull,
    );
  });
  test('行情过期、观测不足和同日冲突', () {
    expect(
      val(ws(cfg([rule(QuantFactor.momentum)], date: '2026-05-29'))).reason,
      contains('3 个'),
    );
    expect(
      val(ws(cfg([rule(QuantFactor.close)], date: '2026-06-20'))).reason,
      contains('时效'),
    );
    expect(
      val(
        ws(
          cfg([rule(QuantFactor.close)]),
          history: [prices('a', co.symbol), prices('b', co.symbol, end: 13)],
        ),
      ).reason,
      contains('冲突'),
    );
  });
  test('金融N/A不参加通用比率，行业排除不改变价格事实', () {
    final bank = WatchCompany(
      id: 'bank',
      code: co.code,
      exchange: 'SH',
      name: '银行',
      industry: '银行',
      source: co.source,
      fetchedAt: co.fetchedAt,
    );
    expect(
      val(ws(cfg([rule(QuantFactor.adjustedProfitMargin)]), companies: [bank]))
          .status,
      QuantValueStatus.notApplicable,
    );
    final r = evaluateQuant(
      ws(
        cfg([rule(QuantFactor.close)]).copyWith(excludedIndustries: ['银行']),
        companies: [bank],
      ),
    ).rows.single;
    expect(r.score, 100);
    expect(r.excluded, true);
    expect(r.selected, false);
  });
  test('未确认不评分，同分稳定按symbol', () {
    expect(
      evaluateQuant(ws(cfg([rule(QuantFactor.close)], confirmed: false)))
          .ranked,
      isEmpty,
    );
    final other = WatchCompany(
      id: 'other',
      code: '600002',
      exchange: 'SH',
      name: '其他',
      industry: '制造',
      source: co.source,
      fetchedAt: co.fetchedAt,
    );
    final d = ws(
      cfg([rule(QuantFactor.close)]),
      companies: [other, co],
      history: [prices('other', other.symbol), prices('co', co.symbol)],
    );
    expect(evaluateQuant(d).ranked.map((r) => r.company.symbol), [
      'SH:600001',
      'SH:600002',
    ]);
    expect(
      evaluateQuant(d).rows.map((r) => r.score),
      evaluateQuant(d).rows.map((r) => r.score),
    );
  });
  test('严格JSON与20版本保留', () {
    final state = QuantState(
      versions: [
        cfg([rule(QuantFactor.close)]),
      ],
    );
    expect(
      QuantState.fromJson(jsonDecode(jsonEncode(state.toJson()))).toJson(),
      state.toJson(),
    );
    for (final patch in [
      {'momentumWindow': 1},
      {'reviewIntervalDays': 0},
      {'confirmedAt': null},
      {'scope': '未知'},
    ]) {
      expect(
        () =>
            QuantConfig.fromJson({...state.currentConfig!.toJson(), ...patch}),
        throwsFormatException,
      );
    }
    expect(
      () => QuantRule.fromJson({
        ...rule(QuantFactor.close).toJson(),
        'weight': double.nan,
      }),
      throwsFormatException,
    );
    var many = const QuantState();
    for (var i = 1; i <= 20; i++) {
      many = many.addVersion(
        cfg([rule(QuantFactor.close)]).copyWith(id: 'q$i', revision: i),
      );
    }
    final before = jsonEncode(many.toJson());
    final next = many.addVersion(
      cfg([rule(QuantFactor.close)]).copyWith(id: 'q21', revision: 21),
    );
    expect(next.versions.length, 20);
    expect(next.versions.first.revision, 2);
    expect(next.currentConfig!.revision, 21);
    expect(jsonEncode(many.toJson()), before);
    expect(
      () => next.addVersion(
        cfg([rule(QuantFactor.close)]).copyWith(id: 'duplicate', revision: 21),
      ),
      throwsFormatException,
    );
  });
  test('未核验、未来、冲突及错来源股本均未知', () {
    for (final facts in [
      [
        ShareCapitalFact.fromJson({...shares.toJson(), 'verified': false}),
      ],
      [
        ShareCapitalFact.fromJson({
          ...shares.toJson(),
          'effectiveDate': '2026-06-01',
        }),
      ],
      [
        shares,
        ShareCapitalFact.fromJson({...shares.toJson(), 'id': 'second'}),
      ],
      [
        ShareCapitalFact.fromJson({...shares.toJson(), 'sourceId': 'wrong'}),
      ],
    ]) {
      expect(
        val(ws(cfg([rule(QuantFactor.priceSalesRatio)]), facts: facts)).value,
        isNull,
      );
    }
  });
  test('仅筛选规则可以入选但无分数且不排序；缺失则不入选', () {
    final c = cfg([rule(QuantFactor.cashDebtRatio, w: 0, filter: true, t: 2)]);
    final valid = evaluateQuant(ws(c));
    expect(valid.rows.single.selected, true);
    expect(valid.rows.single.score, isNull);
    expect(valid.ranked, isEmpty);
    expect(valid.rows.single.missingReasons, isEmpty);
    expect(
      evaluateQuant(ws(c, financials: [fin(2025, debt: null)]))
          .rows
          .single
          .selected,
      false,
    );
  });
  test('跨年度单位归一；半年度不能代替全年', () {
    final d = ws(
      cfg([rule(QuantFactor.revenueGrowth)]),
      financials: [
        fin(2024, revenue: 800000, unit: '元'),
        fin(2025, revenue: 100, unit: '万元'),
      ],
    );
    expect(val(d).value, 25);
    final half = FinancialRecord(
      id: 'half',
      studyId: 's',
      sourceId: 'src2025',
      start: '2025-01-01',
      end: '2025-06-30',
      disclosedAt: '2026-04-01',
      unit: '万元',
      revenue: 100,
      adjustedProfit: 20,
      scope: '合并',
      basis: '原披露',
    );
    expect(
      val(ws(cfg([rule(QuantFactor.adjustedProfitMargin)]), financials: [half]))
          .value,
      isNull,
    );
  });
  test('错误公司来源不可作证据，修订来源不能回看；未带时区确认拒绝', () {
    final bad = SourceExcerpt(
      id: 'src2025',
      studyId: 'other',
      title: '其他公司',
      url: 'https://example.com/report',
      period: '2025',
      disclosedAt: '2026-04-01',
      page: '1',
      unit: '万元',
      text: '原文',
    );
    expect(
      val(ws(cfg([rule(QuantFactor.adjustedProfitMargin)]), sources: [bad]))
          .reason,
      contains('当前研究卡'),
    );
    expect(
      () => QuantConfig.fromJson({
        ...cfg([rule(QuantFactor.close)]).toJson(),
        'confirmedAt': '2026-06-01T12:00:00',
      }),
      throwsFormatException,
    );
  });
  test('确认时间拒绝溢出日历、时分秒及非法时区', () {
    for (final bad in [
      '2026-02-30T10:00:00Z',
      '2026-06-01T25:00:00Z',
      '2026-06-01T10:60:00Z',
      '2026-06-01T10:00:00+15:00',
      '2026-06-01T10:00:00+08:99',
    ]) {
      expect(
        () => QuantConfig.fromJson({
          ...cfg([rule(QuantFactor.close)]).toJson(),
          'confirmedAt': bad,
        }),
        throwsFormatException,
      );
    }
    expect(
      QuantConfig.fromJson({
        ...cfg([rule(QuantFactor.close)]).toJson(),
        'confirmedAt': '2026-06-01T10:00:00+14:00',
      }).confirmed,
      true,
    );
  });
}
