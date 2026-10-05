import 'domain.dart';
import 'quant_models.dart';
import 'research.dart';

enum QuantValueStatus { available, missing, notApplicable }

class QuantEvidence {
  const QuantEvidence({
    required this.label,
    this.rawValue,
    required this.unit,
    required this.period,
    required this.sourceId,
    required this.disclosedAt,
  });
  final String label, unit, period, sourceId, disclosedAt;
  final double? rawValue;
}

class QuantFactorValue {
  const QuantFactorValue({
    required this.status,
    this.value,
    required this.formula,
    required this.reason,
    required this.unit,
    this.evidence = const [],
  });
  final QuantValueStatus status;
  final double? value;
  final String formula, reason, unit;
  final List<QuantEvidence> evidence;
}

class QuantRuleResult {
  const QuantRuleResult({
    required this.rule,
    required this.value,
    required this.passed,
    required this.contribution,
  });
  final QuantRule rule;
  final QuantFactorValue value;
  final bool? passed;
  final double? contribution;
}

class QuantCompanyResult {
  const QuantCompanyResult({
    required this.company,
    required this.score,
    required this.selected,
    required this.excluded,
    required this.missingReasons,
    required this.rules,
  });
  final WatchCompany company;
  final double? score;
  final bool selected, excluded;
  final List<String> missingReasons;
  final List<QuantRuleResult> rules;
}

class QuantEvaluation {
  const QuantEvaluation({
    required this.config,
    required this.rows,
    required this.ranked,
    required this.status,
  });
  final QuantConfig? config;
  final List<QuantCompanyResult> rows, ranked;
  final String status;
}

QuantEvaluation evaluateQuant(WorkspaceData data, {QuantConfig? config}) {
  final candidate = config ?? data.quant.currentConfig;
  final active = candidate == null
      ? null
      : QuantConfig.fromJson(candidate.toJson());
  final ready = active != null && active.confirmed;
  final rows = <QuantCompanyResult>[];
  for (final company in data.watchlist) {
    if (!ready) {
      rows.add(
        QuantCompanyResult(
          company: company,
          score: null,
          selected: false,
          excluded: false,
          missingReasons: [active == null ? '尚未配置规则' : '规则尚未确认'],
          rules: const [],
        ),
      );
      continue;
    }
    // Constructors are intentionally convenient; the evaluator validates them too.
    final valid = active;
    final total = valid.rules.fold<double>(0, (sum, r) => sum + r.weight);
    final cache = <QuantFactor, QuantFactorValue>{};
    final results = <QuantRuleResult>[];
    final missing = <String>[];
    var weighted = 0.0, filtersPass = true;
    for (final rule in valid.rules) {
      final value = cache.putIfAbsent(
        rule.factor,
        () => _Factors(data, company, valid).calculate(rule.factor),
      );
      final available = value.status == QuantValueStatus.available;
      final passed = available ? rule.matches(value.value!) : null;
      final contribution = available && total > 0
          ? (passed! ? rule.weight / total * 100 : 0.0)
          : null;
      if (!available) missing.add('${rule.factor.label}：${value.reason}');
      if (rule.filter && passed != true) filtersPass = false;
      if (passed == true) weighted += rule.weight;
      results.add(
        QuantRuleResult(
          rule: rule,
          value: value,
          passed: passed,
          contribution: contribution,
        ),
      );
    }
    final excluded = valid.excludedIndustries.any(
      (s) => company.industry.contains(s),
    );
    final score = missing.isEmpty && total > 0 ? weighted / total * 100 : null;
    rows.add(
      QuantCompanyResult(
        company: company,
        score: score,
        selected: !excluded && missing.isEmpty && filtersPass,
        excluded: excluded,
        missingReasons: List.unmodifiable(missing),
        rules: List.unmodifiable(results),
      ),
    );
  }
  final ranked = rows.where((r) => r.selected && r.score != null).toList()
    ..sort((a, b) {
      final score = b.score!.compareTo(a.score!);
      return score != 0 ? score : a.company.symbol.compareTo(b.company.symbol);
    });
  return QuantEvaluation(
    config: active,
    rows: List.unmodifiable(rows),
    ranked: List.unmodifiable(ranked),
    status: active == null
        ? '尚未配置规则，请先创建并确认版本'
        : !active.confirmed
        ? '规则尚未确认，暂不评分'
        : '按已确认规则计算；仅有效且通过筛选的公司参与排序',
  );
}

const _formulas = {
  QuantFactor.adjustedProfitMargin: '扣非净利润 ÷ 营业收入 × 100%',
  QuantFactor.revenueGrowth: '(本年营业收入 ÷ 上一日历年营业收入 − 1) × 100%',
  QuantFactor.profitGrowth: '(本年扣非净利润 ÷ 上一日历年扣非净利润 − 1) × 100%',
  QuantFactor.cashProfitRatio: '经营现金流 ÷ 扣非净利润',
  QuantFactor.cashDebtRatio: '期末现金 ÷ 期末有息负债',
  QuantFactor.close: '截止日前最近有效交易日的未复权收盘价',
  QuantFactor.momentum: '(最近收盘价 ÷ 前 N 个交易观测间隔收盘价 − 1) × 100%',
  QuantFactor.priceSalesRatio: '未复权收盘价 × 已核验总股本 ÷ 全年营业收入（元）',
};

class _Factors {
  _Factors(this.data, this.company, this.config);
  final WorkspaceData data;
  final WatchCompany company;
  final QuantConfig config;
  QuantFactorValue missing(
    QuantFactor f,
    String reason, [
    List<QuantEvidence> evidence = const [],
  ]) => QuantFactorValue(
    status: QuantValueStatus.missing,
    formula: _formulas[f]!,
    reason: reason,
    unit: f.unit,
    evidence: evidence,
  );
  QuantFactorValue available(
    QuantFactor f,
    double value,
    List<QuantEvidence> evidence,
  ) => value.isFinite
      ? QuantFactorValue(
          status: QuantValueStatus.available,
          value: value,
          formula: _formulas[f]!,
          reason: '',
          unit: f.unit,
          evidence: List.unmodifiable(evidence),
        )
      : missing(f, '计算结果溢出', evidence);

  QuantFactorValue calculate(QuantFactor factor) {
    if (factor == QuantFactor.close || factor == QuantFactor.momentum) {
      return _price(factor);
    }
    if (company.specialIndustry) {
      return QuantFactorValue(
        status: QuantValueStatus.notApplicable,
        formula: _formulas[factor]!,
        reason: '银行、保险、证券不适用通用财务比率',
        unit: factor.unit,
      );
    }
    final studies = data.studies.where((s) => s.code == company.code).toList();
    if (studies.length != 1) {
      return missing(factor, studies.isEmpty ? '未建立公司研究卡' : '公司研究卡归属不唯一');
    }
    final studyId = studies.single.id;
    final records =
        data.financials
            .where(
              (f) =>
                  f.studyId == studyId &&
                  f.scope == config.scope &&
                  f.basis == '原披露' &&
                  f.start == '${f.end.substring(0, 4)}-01-01' &&
                  f.end == '${f.end.substring(0, 4)}-12-31' &&
                  f.disclosedAt.compareTo(config.asOfDate) < 0,
            )
            .toList()
          ..sort((a, b) => b.end.compareTo(a.end));
    if (records.isEmpty) return missing(factor, '截止日前无同口径、原披露的完整日历年财务');
    final current = records.first;
    if (records.where((f) => f.end == current.end).length != 1) {
      return missing(factor, '最新年度报告期冲突，需核验唯一记录');
    }
    final invalid = _sourceIssue(current, studyId);
    if (invalid != null) return missing(factor, invalid);
    final evidence = <QuantEvidence>[];
    double? amount(FinancialRecord record, String metric) {
      final raw = record.amounts[metric];
      final proofSource = record.evidence[metric]?.sourceId ?? record.sourceId;
      final source = data.sources.where((s) => s.id == proofSource).toList();
      if (source.length != 1 ||
          source.single.studyId != studyId ||
          source.single.disclosedAt.compareTo(config.asOfDate) >= 0) {
        return null;
      }
      evidence.add(
        QuantEvidence(
          label:
              FinancialRecord.labels[FinancialRecord.metrics.indexOf(metric)],
          rawValue: raw,
          unit: record.unit,
          period: '${record.start} 至 ${record.end}',
          sourceId: proofSource,
          disclosedAt: source.single.disclosedAt,
        ),
      );
      final multiplier = switch (record.unit) {
        '元' => 1.0,
        '万元' => 10000.0,
        '亿元' => 100000000.0,
        _ => double.nan,
      };
      return raw == null ? null : raw * multiplier;
    }

    QuantFactorValue ratio(
      String numerator,
      String denominator,
      double multiplier,
    ) {
      final n = amount(current, numerator), d = amount(current, denominator);
      if (n == null || d == null) {
        return missing(factor, '最新年度所需字段或可用来源缺失；不回退旧年度', evidence);
      }
      if (d <= 0) return missing(factor, '分母必须大于 0', evidence);
      return available(factor, n / d * multiplier, evidence);
    }

    if (factor == QuantFactor.adjustedProfitMargin) {
      return ratio('adjustedProfit', 'revenue', 100);
    }
    if (factor == QuantFactor.cashProfitRatio) {
      return ratio('operatingCash', 'adjustedProfit', 1);
    }
    if (factor == QuantFactor.cashDebtRatio) return ratio('cash', 'debt', 1);
    if (factor == QuantFactor.revenueGrowth ||
        factor == QuantFactor.profitGrowth) {
      final year = int.parse(current.end.substring(0, 4));
      final prior = records.where((f) => f.end == '${year - 1}-12-31').toList();
      if (prior.length != 1) {
        return missing(factor, prior.isEmpty ? '缺少相邻上一日历年原披露数据' : '上一年度报告期冲突');
      }
      final invalidPrior = _sourceIssue(prior.single, studyId);
      if (invalidPrior != null) return missing(factor, invalidPrior);
      final metric = factor == QuantFactor.revenueGrowth
          ? 'revenue'
          : 'adjustedProfit';
      final n = amount(current, metric), d = amount(prior.single, metric);
      if (n == null || d == null) {
        return missing(factor, '相邻年度所需字段或可用来源缺失', evidence);
      }
      if (d <= 0) return missing(factor, '上一年度同比基数必须大于 0', evidence);
      return available(factor, (n / d - 1) * 100, evidence);
    }
    final revenue = amount(current, 'revenue');
    if (revenue == null || revenue <= 0) {
      return missing(factor, '最新全年营业收入缺失或不大于 0', evidence);
    }
    final price = _price(QuantFactor.close);
    evidence.addAll(price.evidence);
    if (price.value == null) return missing(factor, price.reason, evidence);
    final facts =
        data.quant.shareFacts
            .where(
              (s) =>
                  s.symbol == company.symbol &&
                  s.verified &&
                  s.effectiveDate.compareTo(config.asOfDate) < 0 &&
                  s.disclosedAt.compareTo(config.asOfDate) < 0,
            )
            .toList()
          ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));
    if (facts.isEmpty) {
      return missing(factor, '无截止日前已核验总股本；持仓股数不能替代总股本', evidence);
    }
    final fact = facts.first;
    if (facts.where((s) => s.effectiveDate == fact.effectiveDate).length != 1) {
      return missing(factor, '最新总股本生效日期冲突', evidence);
    }
    final source = data.sources.where((s) => s.id == fact.sourceId).toList();
    if (source.length != 1 ||
        source.single.studyId != studyId ||
        source.single.disclosedAt.compareTo(config.asOfDate) >= 0 ||
        source.single.disclosedAt != fact.disclosedAt) {
      return missing(factor, '总股本来源归属或披露日期不可用', evidence);
    }
    evidence.add(
      QuantEvidence(
        label: '已核验总股本',
        rawValue: fact.totalShares,
        unit: '股',
        period: '生效 ${fact.effectiveDate}',
        sourceId: fact.sourceId,
        disclosedAt: fact.disclosedAt,
      ),
    );
    return available(
      factor,
      price.value! * fact.totalShares / revenue,
      evidence,
    );
  }

  String? _sourceIssue(FinancialRecord record, String studyId) {
    final sources = data.sources.where((s) => s.id == record.sourceId).toList();
    if (sources.length != 1 || sources.single.studyId != studyId) {
      return '财务来源缺失或不属于当前研究卡';
    }
    if (sources.single.disclosedAt.compareTo(config.asOfDate) >= 0 ||
        sources.single.disclosedAt != record.disclosedAt) {
      return '来源披露日期与财务记录不一致或在截止日之后 / 当日';
    }
    return null;
  }

  QuantFactorValue _price(QuantFactor factor) {
    final histories = data.priceHistory
        .where(
          (h) => h.symbol == company.symbol && h.adjustment == 'unadjusted',
        )
        .toList();
    final prices = <String, double>{}, sources = <String, String>{};
    var conflicting = false;
    for (final history in histories) {
      for (final bar in history.bars) {
        if (bar.date.compareTo(config.asOfDate) >= 0) continue;
        if (prices.containsKey(bar.date) && prices[bar.date] != bar.close) {
          conflicting = true;
        }
        prices[bar.date] = bar.close;
        sources[bar.date] = history.source;
      }
    }
    if (conflicting) return missing(factor, '历史行情同日价格冲突');
    final dates = prices.keys.toList()..sort();
    if (dates.isEmpty) return missing(factor, '截止日前没有未复权历史行情');
    final last = dates.last;
    final proof = <QuantEvidence>[
      QuantEvidence(
        label: '未复权收盘价',
        rawValue: prices[last],
        unit: '元',
        period: last,
        sourceId: sources[last]!,
        disclosedAt: last,
      ),
    ];
    if (DateTime.parse(config.asOfDate)
            .difference(DateTime.parse(last))
            .inDays >
        config.maxPriceAgeDays) {
      return missing(factor, '最近行情超过允许时效 ${config.maxPriceAgeDays} 天', proof);
    }
    if (factor == QuantFactor.close) {
      return available(factor, prices[last]!, proof);
    }
    if (dates.length <= config.momentumWindow) {
      return missing(
        factor,
        '动量至少需要 ${config.momentumWindow + 1} 个交易观测',
        proof,
      );
    }
    final start = dates[dates.length - 1 - config.momentumWindow];
    proof.add(
      QuantEvidence(
        label: '动量起点未复权收盘价',
        rawValue: prices[start],
        unit: '元',
        period: start,
        sourceId: sources[start]!,
        disclosedAt: start,
      ),
    );
    return available(factor, (prices[last]! / prices[start]! - 1) * 100, proof);
  }
}
