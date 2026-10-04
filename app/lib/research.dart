// Shared, versioned research records. Missing financial values stay null.
bool validAShareSymbol(String exchange, String code) {
  if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;
  return switch (exchange) {
    'SH' => code.startsWith('6'),
    'SZ' => code.startsWith('0') || code.startsWith('3'),
    'BJ' =>
      code.startsWith('4') || code.startsWith('8') || code.startsWith('92'),
    _ => false
  };
}

bool validDate(String value) {
  final date = DateTime.tryParse(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      date != null &&
      date.toIso8601String().substring(0, 10) == value;
}

String textField(Map<String, dynamic> j, String key, {bool optional = false}) {
  final value = j[key];
  if (value is! String || (!optional && value.trim().isEmpty)) {
    throw FormatException('$key 文本无效');
  }
  return value;
}

String dateField(Map<String, dynamic> j, String key) {
  final value = textField(j, key);
  if (!validDate(value)) throw FormatException('$key 日期无效');
  return value;
}

String timestampField(Map<String, dynamic> j, String key) {
  final value = textField(j, key);
  if (DateTime.tryParse(value) == null) throw FormatException('$key 时间无效');
  return value;
}

String sourceUrl(Map<String, dynamic> j, String key) {
  final value = textField(j, key);
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw FormatException('$key 需要有效的 HTTPS 来源网址');
  }
  return value;
}

class WatchCompany {
  const WatchCompany(
      {required this.id,
      required this.code,
      required this.exchange,
      required this.name,
      required this.industry,
      required this.source,
      required this.fetchedAt,
      this.close,
      this.tradeDate,
      this.quoteFetchedAt,
      this.quoteSource,
      this.error = ''});
  final String id, code, exchange, name, industry, source, fetchedAt, error;
  final double? close;
  final String? tradeDate, quoteFetchedAt, quoteSource;
  String get symbol => '$exchange:$code';
  bool get specialIndustry => RegExp('银行|保险|证券').hasMatch(industry);
  WatchCompany quoted(double price, String date, String url, String time) =>
      WatchCompany(
          id: id,
          code: code,
          exchange: exchange,
          name: name,
          industry: industry,
          source: source,
          fetchedAt: fetchedAt,
          close: price,
          tradeDate: date,
          quoteFetchedAt: time,
          quoteSource: url);
  WatchCompany failed(String message) => WatchCompany(
      id: id,
      code: code,
      exchange: exchange,
      name: name,
      industry: industry,
      source: source,
      fetchedAt: fetchedAt,
      close: close,
      tradeDate: tradeDate,
      quoteFetchedAt: quoteFetchedAt,
      quoteSource: quoteSource,
      error: message);
  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'exchange': exchange,
        'name': name,
        'industry': industry,
        'source': source,
        'fetchedAt': fetchedAt,
        'close': close,
        'tradeDate': tradeDate,
        'quoteFetchedAt': quoteFetchedAt,
        'quoteSource': quoteSource,
        'error': error
      };
  factory WatchCompany.fromJson(Map<String, dynamic> j) {
    final code = textField(j, 'code'), exchange = textField(j, 'exchange');
    if (!validAShareSymbol(exchange, code)) {
      throw const FormatException('股票代码与 A 股交易所不一致或无效');
    }
    final price = j['close'];
    if (price != null && (price is! num || !price.isFinite || price <= 0)) {
      throw const FormatException('行情价格无效');
    }
    if (price == null &&
        [j['tradeDate'], j['quoteFetchedAt'], j['quoteSource']]
            .any((v) => v != null)) {
      throw const FormatException('行情字段不完整');
    }
    return WatchCompany(
        id: textField(j, 'id'),
        code: code,
        exchange: exchange,
        name: textField(j, 'name'),
        industry: textField(j, 'industry'),
        source: sourceUrl(j, 'source'),
        fetchedAt: timestampField(j, 'fetchedAt'),
        close: (price as num?)?.toDouble(),
        tradeDate: price == null ? null : dateField(j, 'tradeDate'),
        quoteFetchedAt:
            price == null ? null : timestampField(j, 'quoteFetchedAt'),
        quoteSource: price == null ? null : sourceUrl(j, 'quoteSource'),
        error: textField(j, 'error', optional: true));
  }
}

class SourceExcerpt {
  const SourceExcerpt(
      {required this.id,
      required this.studyId,
      required this.title,
      required this.url,
      required this.period,
      required this.disclosedAt,
      required this.page,
      required this.unit,
      required this.text});
  final String id, studyId, title, url, period, disclosedAt, page, unit, text;
  Map<String, dynamic> toJson() => {
        'id': id,
        'studyId': studyId,
        'title': title,
        'url': url,
        'period': period,
        'disclosedAt': disclosedAt,
        'page': page,
        'unit': unit,
        'text': text
      };
  factory SourceExcerpt.fromJson(Map<String, dynamic> j) {
    final text = textField(j, 'text');
    if (text.length > 24000) throw const FormatException('单段资料最多 24000 字');
    return SourceExcerpt(
        id: textField(j, 'id'),
        studyId: textField(j, 'studyId'),
        title: textField(j, 'title'),
        url: sourceUrl(j, 'url'),
        period: textField(j, 'period'),
        disclosedAt: dateField(j, 'disclosedAt'),
        page: textField(j, 'page'),
        unit: textField(j, 'unit'),
        text: text);
  }
}

class FinancialRecord {
  const FinancialRecord(
      {required this.id,
      required this.studyId,
      required this.sourceId,
      required this.start,
      required this.end,
      required this.disclosedAt,
      required this.unit,
      this.revenue,
      this.adjustedProfit,
      this.operatingCash,
      this.cash,
      this.debt});
  final String id, studyId, sourceId, start, end, disclosedAt, unit;
  final double? revenue, adjustedProfit, operatingCash, cash, debt;
  Map<String, dynamic> toJson() => {
        'id': id,
        'studyId': studyId,
        'sourceId': sourceId,
        'start': start,
        'end': end,
        'disclosedAt': disclosedAt,
        'unit': unit,
        'revenue': revenue,
        'adjustedProfit': adjustedProfit,
        'operatingCash': operatingCash,
        'cash': cash,
        'debt': debt
      };
  factory FinancialRecord.fromJson(Map<String, dynamic> j) {
    double? amount(String key, {bool signed = false}) {
      final v = j[key];
      if (v == null) return null;
      if (v is! num || !v.isFinite || v.abs() > 1e15 || (!signed && v < 0)) {
        throw FormatException('$key 财务数值无效');
      }
      return v.toDouble();
    }

    final start = dateField(j, 'start'),
        end = dateField(j, 'end'),
        disclosure = dateField(j, 'disclosedAt');
    if (start.compareTo(end) > 0 || end.compareTo(disclosure) > 0) {
      throw const FormatException('报告期间或披露日期顺序无效');
    }
    final unit = textField(j, 'unit');
    if (!['元', '万元', '亿元'].contains(unit)) {
      throw const FormatException('单位应为元、万元或亿元');
    }
    return FinancialRecord(
        id: textField(j, 'id'),
        studyId: textField(j, 'studyId'),
        sourceId: textField(j, 'sourceId'),
        start: start,
        end: end,
        disclosedAt: disclosure,
        unit: unit,
        revenue: amount('revenue'),
        adjustedProfit: amount('adjustedProfit', signed: true),
        operatingCash: amount('operatingCash', signed: true),
        cash: amount('cash'),
        debt: amount('debt'));
  }
  bool comparableWith(FinancialRecord other) =>
      start == other.start && end == other.end && unit == other.unit;
}

class ResearchDraft {
  ResearchDraft(this.sections);
  static const keys = ['facts', 'support', 'counter', 'missing', 'review'];
  static const labels = ['事实', '支持理由（推测）', '反面证据', '缺失信息', '复查条件'];
  final Map<String, List<DraftClaim>> sections;
  factory ResearchDraft.fromJson(Map<String, dynamic> j) {
    final sections = <String, List<DraftClaim>>{};
    for (final key in keys) {
      final values = j[key];
      if (values is! List || values.length > 30) {
        throw const FormatException('草稿缺少完整的五个章节或条目过多');
      }
      sections[key] = values.map((v) {
        if (v is! Map<String, dynamic>) throw const FormatException('草稿条目格式无效');
        return DraftClaim.fromJson(v);
      }).toList();
    }
    if (sections['facts']!.isEmpty) throw const FormatException('草稿没有可核验事实');
    return ResearchDraft(sections);
  }
  List<String> validate(List<SourceExcerpt> sources) {
    final byId = {for (final s in sources) s.id: s};
    final errors = <String>[];
    String normalize(String text) => text.replaceAll(RegExp(r'\s+'), '');
    for (final key in keys) {
      for (final claim in sections[key]!) {
        if (['facts', 'support', 'counter'].contains(key) &&
            claim.refs.isEmpty) {
          errors.add('${claim.text}：缺少引用');
        }
        for (final ref in claim.refs) {
          final source = byId[ref.sourceId], quote = normalize(ref.quote);
          if (source == null ||
              quote.length < 8 ||
              !normalize(source.text).contains(quote)) {
            errors.add('${claim.text}：引用 ${ref.sourceId} 不存在、过短或不在原文中');
          }
        }
      }
    }
    return errors;
  }

  String render(String key) => sections[key]!
      .map((c) =>
          '${c.text}${c.refs.map((r) => '\n[${r.sourceId}]「${r.quote}」').join()}')
      .join('\n\n');
}

class DraftClaim {
  DraftClaim(this.text, this.refs);
  final String text;
  final List<EvidenceRef> refs;
  factory DraftClaim.fromJson(Map<String, dynamic> j) {
    final refs = j['refs'];
    if (refs is! List || refs.length > 10) {
      throw const FormatException('引用格式无效');
    }
    return DraftClaim(
        textField(j, 'text'),
        refs.map((v) {
          if (v is! Map<String, dynamic>) throw const FormatException('引用格式无效');
          return EvidenceRef(textField(v, 'sourceId'), textField(v, 'quote'));
        }).toList());
  }
}

class EvidenceRef {
  EvidenceRef(this.sourceId, this.quote);
  final String sourceId, quote;
}
