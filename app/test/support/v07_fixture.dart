// All companies, sources and amounts here are fictional offline evidence.
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/quant_models.dart';
import 'package:lianghua_assistant/data_foundation.dart';

WorkspaceData v07Fixture({bool configured = true, bool ledger = true}) {
  const company = WatchCompany(
    id: 'v07-company',
    code: '600001',
    exchange: 'SH',
    name: '虚构制造',
    industry: '虚构制造',
    source: 'https://example.com/company',
    fetchedAt: '2026-10-05T00:00:00+08:00',
  );
  const study = Study(
    id: 'v07-study',
    code: '600001',
    name: '虚构制造',
    business: '虚构业务',
    thesis: '等待原文核验后的人工判断',
    counterEvidence: '下一年盈利是否持续',
    reviewCondition: '新年报披露后人工复查',
    source: 'https://example.com/report',
    updatedAt: '2026-10-05',
    nextReviewAt: '2026-11-04',
  );
  final sources = [
    for (final y in [2024, 2025])
      SourceExcerpt(
        id: 'v07-source-$y',
        studyId: study.id,
        title: '虚构 $y 年报',
        url: 'https://example.com/report/$y',
        period: '$y年度',
        disclosedAt: '${y + 1}-04-01',
        page: '1',
        unit: '万元',
        text: '虚构营收、扣非净利润、经营现金、现金及有息负债；仅用于验收。',
      ),
  ];
  final financials = [
    for (final y in [2024, 2025])
      FinancialRecord(
        id: 'v07-financial-$y',
        studyId: study.id,
        sourceId: 'v07-source-$y',
        start: '$y-01-01',
        end: '$y-12-31',
        disclosedAt: '${y + 1}-04-01',
        unit: '万元',
        revenue: y == 2025 ? 100 : 80,
        adjustedProfit: y == 2025 ? 20 : 10,
        operatingCash: 40,
        cash: 30,
        debt: 10,
        scope: '合并',
        basis: '原披露',
      ),
  ];
  final config = QuantConfig(
    id: 'v07-config',
    revision: 1,
    name: '虚构手算规则',
    asOfDate: '2026-10-05',
    momentumWindow: 2,
    rules: const [
      QuantRule(
        id: 'margin',
        factor: QuantFactor.adjustedProfitMargin,
        comparison: QuantComparison.gte,
        threshold: 15,
        weight: 3,
        filter: true,
      ),
      QuantRule(
        id: 'growth',
        factor: QuantFactor.revenueGrowth,
        comparison: QuantComparison.gte,
        threshold: 30,
        weight: 1,
        filter: false,
      ),
    ],
    confirmed: true,
    confirmedAt: '2026-10-05T00:00:00+08:00',
  );
  final funding = FundingLedger(
    coverageStart: '2026-10-01',
    openingDeposits: 10000,
    openingWithdrawals: 500,
    entries: [
      DatedCashFlow(
        id: 'v07-flow',
        date: '2026-10-02',
        kind: CashFlowKind.deposit,
        amount: 1000,
        source: '虚构银行转入回单',
      ),
    ],
  );
  return WorkspaceData.empty().copyWith(
    cash: 4500,
    deposits: ledger ? 11000 : 10000,
    withdrawals: 500,
    priceDate: '2026-09-30',
    holdings: const [
      Holding(
        id: 'v07-holding',
        code: '600001',
        name: '虚构制造',
        industry: '虚构制造',
        quantity: 100,
        price: 12,
      ),
    ],
    watchlist: [company],
    studies: [study],
    sources: sources,
    financials: financials,
    quant: QuantState(
      versions: configured ? [config] : [],
      shareFacts: const [
        ShareCapitalFact(
          id: 'v07-shares',
          symbol: 'SH:600001',
          effectiveDate: '2025-12-31',
          disclosedAt: '2026-04-01',
          totalShares: 100000,
          sourceId: 'v07-source-2025',
          verified: true,
        ),
      ],
    ),
    priceHistory: [
      PriceHistory(
        id: 'v07-prices',
        symbol: 'SH:600001',
        source: 'https://example.com/prices',
        fetchedAt: '2026-10-05T00:00:00+08:00',
        bars: [
          HistoryBar(date: '2026-09-28', close: 10),
          HistoryBar(date: '2026-09-29', close: 11),
          HistoryBar(date: '2026-09-30', close: 12),
        ],
      ),
    ],
    funding: ledger ? funding : null,
  );
}
