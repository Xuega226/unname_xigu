import 'research.dart';

enum QuantFactor {
  adjustedProfitMargin('扣非净利率', '%'),
  revenueGrowth('营业收入同比', '%'),
  profitGrowth('扣非净利润同比', '%'),
  cashProfitRatio('经营现金流 / 扣非净利', '倍'),
  cashDebtRatio('现金 / 有息负债', '倍'),
  close('未复权收盘价', '元'),
  momentum('区间动量', '%'),
  priceSalesRatio('市销率', '倍');

  const QuantFactor(this.label, this.unit);
  final String label, unit;
}

enum QuantComparison { gte, lte }

T _enum<T extends Enum>(List<T> values, dynamic value, String name) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('$name 无效');
}

double _finite(Map<String, dynamic> j, String key, {double? minimum}) {
  final v = j[key];
  if (v is! num || !v.isFinite || (minimum != null && v < minimum)) {
    throw FormatException('$key 必须为有限有效数值');
  }
  return v.toDouble();
}

List<T> _list<T>(
  Map<String, dynamic> j,
  String key,
  int maximum,
  T Function(Map<String, dynamic>) parse,
) {
  final raw = j[key];
  if (raw is! List || raw.length > maximum) throw FormatException('$key 无效');
  return List.unmodifiable(
    raw.map((e) {
      if (e is! Map<String, dynamic>) throw FormatException('$key 项目无效');
      return parse(e);
    }),
  );
}

bool _validConfirmationTimestamp(String value) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|([+-])(\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null ||
      !validDate(match[1]!) ||
      DateTime.tryParse(value) == null) {
    return false;
  }
  if (int.parse(match[2]!) > 23 ||
      int.parse(match[3]!) > 59 ||
      int.parse(match[4]!) > 59) {
    return false;
  }
  if (match[5] == 'Z') return true;
  final hour = int.parse(match[7]!), minute = int.parse(match[8]!);
  return hour <= 14 && minute < 60 && (hour != 14 || minute == 0);
}

class QuantRule {
  const QuantRule({
    required this.id,
    required this.factor,
    required this.comparison,
    required this.threshold,
    required this.weight,
    required this.filter,
  });
  final String id;
  final QuantFactor factor;
  final QuantComparison comparison;
  final double threshold, weight;
  final bool filter;
  bool matches(double value) => comparison == QuantComparison.gte
      ? value >= threshold
      : value <= threshold;
  Map<String, dynamic> toJson() => {
    'id': id,
    'factor': factor.name,
    'comparison': comparison.name,
    'threshold': threshold,
    'weight': weight,
    'filter': filter,
  };
  factory QuantRule.fromJson(Map<String, dynamic> j) {
    final weight = _finite(j, 'weight', minimum: 0);
    if (j['filter'] is! bool || (weight == 0 && j['filter'] != true)) {
      throw const FormatException('规则必须参与评分或筛选');
    }
    return QuantRule(
      id: textField(j, 'id'),
      factor: _enum(QuantFactor.values, j['factor'], '因子'),
      comparison: _enum(QuantComparison.values, j['comparison'], '比较条件'),
      threshold: _finite(j, 'threshold'),
      weight: weight,
      filter: j['filter'],
    );
  }
}

class QuantConfig {
  const QuantConfig({
    required this.id,
    required this.revision,
    required this.name,
    required this.asOfDate,
    this.scope = '合并',
    this.momentumWindow = 20,
    this.maxPriceAgeDays = 7,
    this.excludedIndustries = const [],
    this.reviewIntervalDays = 30,
    this.reviewCondition = '人工复查资料与规则；不自动调仓',
    required this.rules,
    this.confirmed = false,
    this.confirmedAt,
  });
  final String id, name, asOfDate, scope, reviewCondition;
  final int revision, momentumWindow, maxPriceAgeDays, reviewIntervalDays;
  final List<String> excludedIndustries;
  final List<QuantRule> rules;
  final bool confirmed;
  final String? confirmedAt;
  QuantConfig copyWith({
    String? id,
    int? revision,
    String? name,
    String? asOfDate,
    String? scope,
    int? momentumWindow,
    int? maxPriceAgeDays,
    int? reviewIntervalDays,
    String? reviewCondition,
    List<String>? excludedIndustries,
    List<QuantRule>? rules,
    bool? confirmed,
    String? confirmedAt,
  }) => QuantConfig(
    id: id ?? this.id,
    revision: revision ?? this.revision,
    name: name ?? this.name,
    asOfDate: asOfDate ?? this.asOfDate,
    scope: scope ?? this.scope,
    momentumWindow: momentumWindow ?? this.momentumWindow,
    maxPriceAgeDays: maxPriceAgeDays ?? this.maxPriceAgeDays,
    reviewIntervalDays: reviewIntervalDays ?? this.reviewIntervalDays,
    reviewCondition: reviewCondition ?? this.reviewCondition,
    excludedIndustries: excludedIndustries ?? this.excludedIndustries,
    rules: rules ?? this.rules,
    confirmed: confirmed ?? this.confirmed,
    confirmedAt: confirmed == false ? null : confirmedAt ?? this.confirmedAt,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'revision': revision,
    'name': name,
    'asOfDate': asOfDate,
    'scope': scope,
    'momentumWindow': momentumWindow,
    'maxPriceAgeDays': maxPriceAgeDays,
    'reviewIntervalDays': reviewIntervalDays,
    'reviewCondition': reviewCondition,
    'excludedIndustries': excludedIndustries,
    'rules': rules.map((e) => e.toJson()).toList(),
    'confirmed': confirmed,
    'confirmedAt': confirmedAt,
  };
  factory QuantConfig.fromJson(Map<String, dynamic> j) {
    final revision = j['revision'],
        window = j['momentumWindow'],
        age = j['maxPriceAgeDays'];
    final excluded = j['excludedIndustries'];
    final review = j['reviewIntervalDays'];
    if (revision is! int ||
        revision < 1 ||
        revision > 1000000 ||
        window is! int ||
        window < 2 ||
        window > 250 ||
        age is! int ||
        age < 0 ||
        age > 365 ||
        review is! int ||
        review < 1 ||
        review > 3650 ||
        !['合并', '母公司'].contains(j['scope']) ||
        j['confirmed'] is! bool ||
        excluded is! List ||
        excluded.length > 100 ||
        excluded.any((e) => e is! String || e.trim().isEmpty) ||
        excluded.toSet().length != excluded.length) {
      throw const FormatException('量化版本或参数无效');
    }
    final at = j['confirmedAt'];
    if ((j['confirmed'] == true &&
            (at is! String || !_validConfirmationTimestamp(at))) ||
        (j['confirmed'] == false && at != null)) {
      throw const FormatException('量化确认时间无效');
    }
    final rules = _list(j, 'rules', 30, QuantRule.fromJson);
    if (rules.isEmpty ||
        rules.map((e) => e.id).toSet().length != rules.length ||
        rules.fold<double>(0, (a, b) => a + b.weight).isInfinite) {
      throw const FormatException('量化规则为空、重复或总权重溢出');
    }
    return QuantConfig(
      id: textField(j, 'id'),
      revision: revision,
      name: textField(j, 'name'),
      asOfDate: dateField(j, 'asOfDate'),
      scope: j['scope'],
      momentumWindow: window,
      maxPriceAgeDays: age,
      reviewIntervalDays: review,
      reviewCondition: textField(j, 'reviewCondition'),
      excludedIndustries: List.unmodifiable(excluded.cast<String>()),
      rules: rules,
      confirmed: j['confirmed'],
      confirmedAt: at as String?,
    );
  }
}

class ShareCapitalFact {
  const ShareCapitalFact({
    required this.id,
    required this.symbol,
    required this.effectiveDate,
    required this.disclosedAt,
    required this.totalShares,
    required this.sourceId,
    this.verified = false,
  });
  final String id, symbol, effectiveDate, disclosedAt, sourceId;
  final double totalShares;
  final bool verified;
  Map<String, dynamic> toJson() => {
    'id': id,
    'symbol': symbol,
    'effectiveDate': effectiveDate,
    'disclosedAt': disclosedAt,
    'totalShares': totalShares,
    'sourceId': sourceId,
    'verified': verified,
  };
  factory ShareCapitalFact.fromJson(Map<String, dynamic> j) {
    final symbol = textField(j, 'symbol'), pieces = symbol.split(':');
    final shares = _finite(j, 'totalShares', minimum: 1);
    if (pieces.length != 2 ||
        !validAShareSymbol(pieces[0], pieces[1]) ||
        shares != shares.roundToDouble() ||
        shares > 1e15 ||
        j['verified'] is! bool) {
      throw const FormatException('总股本记录无效');
    }
    return ShareCapitalFact(
      id: textField(j, 'id'),
      symbol: symbol,
      effectiveDate: dateField(j, 'effectiveDate'),
      disclosedAt: dateField(j, 'disclosedAt'),
      totalShares: shares,
      sourceId: textField(j, 'sourceId'),
      verified: j['verified'],
    );
  }
}

class QuantState {
  const QuantState({this.versions = const [], this.shareFacts = const []});
  final List<QuantConfig> versions;
  final List<ShareCapitalFact> shareFacts;
  QuantConfig? get currentConfig => versions.isEmpty ? null : versions.last;
  QuantState copyWith({
    List<QuantConfig>? versions,
    List<ShareCapitalFact>? shareFacts,
  }) => QuantState(
    versions: List.unmodifiable(versions ?? this.versions),
    shareFacts: List.unmodifiable(shareFacts ?? this.shareFacts),
  );
  QuantState addVersion(QuantConfig config) {
    if (versions.any((v) => v.id == config.id) ||
        (currentConfig != null && config.revision <= currentConfig!.revision)) {
      throw const FormatException('新配置 ID 必须唯一且版本号必须递增');
    }
    final next = copyWith(
      versions: List.unmodifiable(
        [
          ...versions,
          config,
        ].skip(versions.length >= 20 ? versions.length - 19 : 0),
      ),
    );
    return QuantState.fromJson(next.toJson());
  }

  Map<String, dynamic> toJson() => {
    'versions': versions.map((e) => e.toJson()).toList(),
    'shareFacts': shareFacts.map((e) => e.toJson()).toList(),
  };
  factory QuantState.fromJson(Map<String, dynamic> j) {
    final versions = _list(j, 'versions', 20, QuantConfig.fromJson);
    final facts = _list(j, 'shareFacts', 1000, ShareCapitalFact.fromJson);
    if (versions.map((e) => e.id).toSet().length != versions.length ||
        versions.map((e) => e.revision).toSet().length != versions.length ||
        facts.map((e) => e.id).toSet().length != facts.length) {
      throw const FormatException('量化配置或股本 ID / 版本号重复');
    }
    for (var i = 1; i < versions.length; i++) {
      if (versions[i].revision <= versions[i - 1].revision) {
        throw const FormatException('量化版本号必须递增');
      }
    }
    return QuantState(versions: versions, shareFacts: facts);
  }
}
