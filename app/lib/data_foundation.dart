import 'dart:convert';

import 'research.dart';
import 'services.dart';

String _text(Map<String, dynamic> j, String key, {int max = 500}) {
  final v = j[key];
  if (v is! String ||
      v.isEmpty ||
      v.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(v)) {
    throw FormatException('$key 文本无效');
  }
  return v;
}

double _money(num value, {bool positive = false}) {
  final v = value.toDouble();
  if (!v.isFinite ||
      v > 1e12 ||
      v < 0 ||
      (positive && v <= 0) ||
      (v * 100 - (v * 100).round()).abs() > 0.001) {
    throw const FormatException('金额须为有限非负数，最多两位小数且不超过一万亿元');
  }
  return (v * 100).round() / 100;
}

double _jsonMoney(Map<String, dynamic> j, String key, {bool positive = false}) {
  final v = j[key];
  if (v is! num) throw FormatException('$key 金额无效');
  return _money(v, positive: positive);
}

double _opening(num value) {
  final v = value.toDouble();
  if (!v.isFinite || v < 0) {
    throw const FormatException('期初累计金额须为有限非负数');
  }
  return v;
}

double _jsonOpening(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! num) throw FormatException('$key 金额无效');
  return _opening(v);
}

void _date(String value) {
  if (!validDate(value)) throw const FormatException('日期须为有效 YYYY-MM-DD');
}

void _id(String value) {
  _text({'id': value}, 'id', max: 120);
}

class HistoryBar {
  HistoryBar({required this.date, required this.close}) {
    _date(date);
    if (!close.isFinite || close <= 0 || close > 1e9) {
      throw const FormatException('历史收盘价须为有限正数且不超过十亿元');
    }
  }
  final String date;
  final double close;
  Map<String, dynamic> toJson() => {'date': date, 'close': close};
  factory HistoryBar.fromJson(Map<String, dynamic> j) {
    final close = j['close'];
    if (close is! num) throw const FormatException('历史收盘价格式无效');
    return HistoryBar(date: _text(j, 'date'), close: close.toDouble());
  }
}

class PriceHistory {
  PriceHistory({
    required this.id,
    required this.symbol,
    this.adjustment = 'unadjusted',
    required this.source,
    required this.fetchedAt,
    required List<HistoryBar> bars,
  }) : bars = List.unmodifiable(bars) {
    _id(id);
    final parts = symbol.split(':');
    if (parts.length != 2 || !validAShareSymbol(parts[0], parts[1])) {
      throw const FormatException('历史序列须标明匹配交易所的 A 股代码，如 SH:600001');
    }
    if (adjustment != 'unadjusted') {
      throw const FormatException('当前只接受未复权日线，不推算复权序列');
    }
    final uri = Uri.tryParse(source);
    if (source.length > 2000 ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(source)) {
      throw const FormatException('历史来源须为不含账户信息的 HTTPS 地址');
    }
    final timestamp = DateTime.tryParse(fetchedAt);
    final stampParts = RegExp(r'T(\d{2}):(\d{2}):(\d{2})')
        .firstMatch(fetchedAt);
    final offset = RegExp(r'([+-])(\d{2}):(\d{2})$').firstMatch(fetchedAt);
    if (timestamp == null ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(fetchedAt) ||
        !validDate(fetchedAt.substring(0, 10)) ||
        stampParts == null ||
        int.parse(stampParts[1]!) > 23 ||
        int.parse(stampParts[2]!) > 59 ||
        int.parse(stampParts[3]!) > 59 ||
        (offset != null &&
            (int.parse(offset[2]!) > 14 ||
                int.parse(offset[3]!) > 59 ||
                (int.parse(offset[2]!) == 14 && int.parse(offset[3]!) != 0)))) {
      throw const FormatException('历史获取时间须为含明确时区的 ISO 时间');
    }
    if (bars.isEmpty || bars.length > 500) {
      throw const FormatException('每个历史序列须包含 1 至 500 根日线');
    }
    final fetchedChina = timestamp
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    String previous = '';
    for (final bar in bars) {
      if (bar.date.compareTo(previous) <= 0 ||
          bar.date.compareTo(fetchedChina) > 0) {
        throw const FormatException('历史日期须严格升序，不能重复或混序');
      }
      previous = bar.date;
    }
  }
  final String id, symbol, adjustment, source, fetchedAt;
  final List<HistoryBar> bars;
  Map<String, dynamic> toJson() => {
    'id': id,
    'symbol': symbol,
    'adjustment': adjustment,
    'source': source,
    'fetchedAt': fetchedAt,
    'bars': bars.map((b) => b.toJson()).toList(),
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  factory PriceHistory.decode(String raw) {
    if (raw.length > 200000) throw const FormatException('历史 JSON 过大');
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic>) {
      throw const FormatException('历史 JSON 须为单个序列对象');
    }
    return PriceHistory.fromJson(j);
  }
  factory PriceHistory.fromJson(Map<String, dynamic> j) {
    final values = j['bars'];
    if (values is! List || values.length > 500) {
      throw const FormatException('历史 bars 列表无效或超过 500 根');
    }
    return PriceHistory(
      id: _text(j, 'id'),
      symbol: _text(j, 'symbol'),
      adjustment: _text(j, 'adjustment'),
      source: _text(j, 'source', max: 2000),
      fetchedAt: _text(j, 'fetchedAt'),
      bars: values.map((v) {
        if (v is! Map<String, dynamic>) throw const FormatException('历史日线格式错误');
        return HistoryBar.fromJson(v);
      }).toList(),
    );
  }
}

class MarketHistoryService {
  MarketHistoryService({JsonTransport? transport, DateTime Function()? clock})
    : transport =
          transport ?? IoJsonTransport(timeout: const Duration(seconds: 25)),
      clock = clock ?? DateTime.now;
  final JsonTransport transport;
  final DateTime Function() clock;
  Future<PriceHistory> history(String symbol) async {
    final parts = symbol.split(':');
    if (parts.length != 2 || !validAShareSymbol(parts[0], parts[1])) {
      throw ServiceFailure('请输入匹配交易所的 A 股代码，例如 SH:600001');
    }
    final fetched = clock().toUtc();
    final china = fetched.add(const Duration(hours: 8));
    final today = DateTime.utc(china.year, china.month, china.day);
    final end = today.subtract(Duration(days: china.hour < 17 ? 1 : 0));
    String day(DateTime v) => v.toIso8601String().substring(0, 10);
    final begin = end.subtract(const Duration(days: 730));
    final market = parts[0] == 'SH' ? 1 : 0;
    final uri = Uri.https('push2his.eastmoney.com', '/api/qt/stock/kline/get', {
      'secid': '$market.${parts[1]}',
      'klt': '101',
      'fqt': '0',
      'lmt': '500',
      'beg': day(begin).replaceAll('-', ''),
      'end': day(end).replaceAll('-', ''),
      'fields1': 'f1,f2,f3,f4,f5,f6',
      'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
    });
    final response = await transport.request(uri);
    final data = response['data'];
    if (response['rc'] != 0 ||
        data is! Map<String, dynamic> ||
        data['code'] != parts[1] ||
        data['market'] != market ||
        data['klines'] is! List ||
        (data['klines'] as List).length > 500) {
      throw ServiceFailure('历史行情身份、格式或数量校验失败，旧历史已保留');
    }
    final bars = <HistoryBar>[];
    String previous = '';
    for (final row in data['klines'] as List) {
      if (row is! String) throw ServiceFailure('历史行情含无效行，未应用');
      final fields = row.split(',');
      if (fields.length < 11 || !validDate(fields[0])) {
        throw ServiceFailure('历史行情含无效日线，未应用');
      }
      final close = double.tryParse(fields[2]);
      if (close == null ||
          !close.isFinite ||
          close <= 0 ||
          close > 1e9 ||
          fields[0].compareTo(previous) <= 0 ||
          fields[0].compareTo(day(today)) > 0 ||
          fields[0].compareTo(day(begin)) < 0) {
        throw ServiceFailure('历史行情日期或收盘价校验失败，未应用');
      }
      previous = fields[0];
      // Only a validated current-day bar may be omitted before 17:00 China time.
      if (fields[0].compareTo(day(end)) <= 0) {
        bars.add(HistoryBar(date: fields[0], close: close));
      }
    }
    if (bars.isEmpty) throw ServiceFailure('本次未取得已结束交易日的日线，旧历史已保留');
    return PriceHistory(
      id: 'history-${parts.join('-')}',
      symbol: symbol,
      source: uri.toString(),
      fetchedAt: fetched.toIso8601String(),
      bars: bars,
    );
  }
}

enum CashFlowKind { deposit, withdrawal }

class DatedCashFlow {
  DatedCashFlow({
    required this.id,
    required this.date,
    required this.kind,
    required double amount,
    required this.source,
  }) : amount = _money(amount, positive: true) {
    _id(id);
    _date(date);
    _text({'source': source}, 'source', max: 500);
  }
  final String id, date, source;
  final CashFlowKind kind;
  final double amount;
  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'kind': kind.name,
    'amount': amount,
    'source': source,
  };
  factory DatedCashFlow.fromJson(Map<String, dynamic> j) {
    final kind = j['kind'];
    if (!['deposit', 'withdrawal'].contains(kind)) {
      throw const FormatException('现金流种类无效');
    }
    return DatedCashFlow(
      id: _text(j, 'id'),
      date: _text(j, 'date'),
      kind: kind == 'deposit' ? CashFlowKind.deposit : CashFlowKind.withdrawal,
      amount: _jsonMoney(j, 'amount', positive: true),
      source: _text(j, 'source'),
    );
  }
}

class FundingLedger {
  FundingLedger({
    required this.coverageStart,
    required double openingDeposits,
    required double openingWithdrawals,
    required List<DatedCashFlow> entries,
  }) : openingDeposits = _opening(openingDeposits),
       openingWithdrawals = _opening(openingWithdrawals),
       entries = List.unmodifiable(entries) {
    _date(coverageStart);
    if (entries.length > 1000) throw const FormatException('资金流水最多 1000 条');
    final ids = <String>{};
    for (final entry in entries) {
      if (!ids.add(entry.id) || entry.date.compareTo(coverageStart) < 0) {
        throw const FormatException('流水 ID 重复或日期早于覆盖起点');
      }
    }
    _opening(deposits);
    _opening(withdrawals);
  }
  final String coverageStart;
  final double openingDeposits, openingWithdrawals;
  final List<DatedCashFlow> entries;
  double get deposits =>
      openingDeposits +
      (entries
                  .where((e) => e.kind == CashFlowKind.deposit)
                  .fold<double>(0, (n, e) => n + e.amount * 100))
              .round() /
          100;
  double get withdrawals =>
      openingWithdrawals +
      (entries
                  .where((e) => e.kind == CashFlowKind.withdrawal)
                  .fold<double>(0, (n, e) => n + e.amount * 100))
              .round() /
          100;
  double get principal => deposits - withdrawals;
  FundingLedger copyWith({List<DatedCashFlow>? entries}) => FundingLedger(
    coverageStart: coverageStart,
    openingDeposits: openingDeposits,
    openingWithdrawals: openingWithdrawals,
    entries: entries ?? this.entries,
  );
  Map<String, dynamic> toJson() => {
    'coverageStart': coverageStart,
    'openingDeposits': openingDeposits,
    'openingWithdrawals': openingWithdrawals,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
  factory FundingLedger.fromJson(Map<String, dynamic> j) {
    final values = j['entries'];
    if (values is! List || values.length > 1000) {
      throw const FormatException('资金流水列表无效');
    }
    return FundingLedger(
      coverageStart: _text(j, 'coverageStart'),
      openingDeposits: _jsonOpening(j, 'openingDeposits'),
      openingWithdrawals: _jsonOpening(j, 'openingWithdrawals'),
      entries: values.map((v) {
        if (v is! Map<String, dynamic>) throw const FormatException('资金流水格式无效');
        return DatedCashFlow.fromJson(v);
      }).toList(),
    );
  }
}
