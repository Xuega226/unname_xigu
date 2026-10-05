import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fast_gbk/fast_gbk.dart';

import 'domain.dart';
import 'portfolio_import_info.dart';
import 'research.dart';
import 'services.dart';

const maxPortfolioBytes = 2 * 1024 * 1024;

class BrokerSnapshot {
  const BrokerSnapshot({
    required this.info,
    required this.priceDate,
    required this.cash,
    required this.holdings,
  });
  final PortfolioImportInfo info;
  final String priceDate;
  final double cash;
  final List<Holding> holdings;
  double get assets =>
      cash + holdings.fold(0.0, (sum, h) => sum + h.marketValue);
}

class CsvAccountDetails {
  const CsvAccountDetails({
    required this.broker,
    required this.accountAlias,
    required this.priceDate,
    required this.cash,
    this.columnMapping,
    this.delimiter,
    this.encoding,
  });
  final String broker, accountAlias, priceDate;
  final double cash;
  final Map<String, int>? columnMapping;
  final String? delimiter;
  final PortfolioTextEncoding? encoding;
}

enum PortfolioTextEncoding { utf8, gbk }

class BrokerEncodingRequired extends FormatException {
  const BrokerEncodingRequired()
    : super('文件不是有效 UTF-8。请确认原文件编码为 GBK，或另存为 UTF-8 后重新选择');
}

String _strictGbk(List<int> bytes) {
  // The codec's malformed mode is never enabled. Validate GBK pairs as well,
  // so truncated input and GB18030 four-byte sequences cannot be accepted.
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] < 0x80) continue;
    if (bytes[i] < 0x81 ||
        bytes[i] > 0xFE ||
        ++i >= bytes.length ||
        bytes[i] < 0x40 ||
        bytes[i] > 0xFE ||
        bytes[i] == 0x7F) {
      throw const FormatException('GBK 编码无效或文件不完整；GB18030 四字节字符请另存为 UTF-8');
    }
  }
  return const GbkCodec().decode(bytes);
}

String decodePortfolioText(List<int> bytes, {PortfolioTextEncoding? encoding}) {
  if (bytes.isEmpty || bytes.length > maxPortfolioBytes) {
    throw const FormatException('持仓文件为空或超过 2 MB');
  }
  if (bytes.any((b) => b < 0 || b > 255)) {
    throw const FormatException('持仓文件包含无效字节');
  }
  if (bytes.length >= 2 &&
      ((bytes[0] == 255 && bytes[1] == 254) ||
          (bytes[0] == 254 && bytes[1] == 255))) {
    if (bytes.length.isOdd) throw const FormatException('UTF-16 文件不完整');
    final little = bytes[0] == 255;
    final units = [
      for (var i = 2; i < bytes.length; i += 2)
        little
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
    ];
    for (var i = 0; i < units.length; i++) {
      if (units[i] >= 0xD800 && units[i] <= 0xDBFF) {
        if (++i >= units.length || units[i] < 0xDC00 || units[i] > 0xDFFF) {
          throw const FormatException('UTF-16 文件包含不完整字符');
        }
      } else if (units[i] >= 0xDC00 && units[i] <= 0xDFFF) {
        throw const FormatException('UTF-16 文件包含无效字符');
      }
    }
    return String.fromCharCodes(units);
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    // A declared UTF-8 file must never silently fall back to GBK.
    return utf8.decode(bytes.sublist(3));
  }
  if (encoding == PortfolioTextEncoding.gbk) return _strictGbk(bytes);
  try {
    return utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
  } on FormatException {
    if (encoding == PortfolioTextEncoding.utf8) rethrow;
    _strictGbk(bytes); // Only offer GBK if it is strictly valid.
    throw const BrokerEncodingRequired();
  }
}

double _amount(dynamic value, String label, {bool integer = false}) {
  final number = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value.trim().replaceAll(',', ''))
      : null;
  if (number == null ||
      !number.isFinite ||
      number < 0 ||
      number > 1e12 ||
      (integer && number != number.truncateToDouble())) {
    throw FormatException('$label 需要非负${integer ? '整数' : '数值'}，最大 1 万亿');
  }
  return number;
}

String _label(dynamic value, String label) {
  return brokerMetadataLabel(value, label);
}

Holding _holding(Map<String, dynamic> row, int index) {
  var code = _label(row['code'], '第 $index 行证券代码').toUpperCase();
  // Preserve leading zeroes; never pad a numeric code that may be another asset.
  final match = RegExp(r'^(\d{6})(?:\.(SH|SZ|BJ))?$').firstMatch(code);
  if (match == null) throw FormatException('第 $index 行需要六位沪深北 A 股代码');
  code = match.group(1)!;
  final exchange = aShareExchangeForCode(code);
  if (exchange == null ||
      (match.group(2) != null && match.group(2) != exchange) ||
      (row['exchange'] != null && row['exchange'] != exchange)) {
    throw FormatException('第 $index 行代码与交易所不符或资产类型暂不支持');
  }
  final quantity = _amount(row['quantity'], '第 $index 行总持仓数量', integer: true);
  final price = _amount(row['price'], '第 $index 行市价');
  if (quantity > 0 && price <= 0) {
    throw FormatException('第 $index 行非零持仓缺少有效市价，未用成本价代替');
  }
  return Holding(
    id: 'broker:$exchange:$code',
    code: code,
    name: _label(row['name'], '第 $index 行证券名称'),
    industry: row['industry'] == null || row['industry'] == ''
        ? '行业资料不足'
        : _label(row['industry'], '第 $index 行行业'),
    quantity: quantity,
    price: price,
  );
}

BrokerSnapshot parseBrokerFile(
  List<int> bytes, {
  CsvAccountDetails? csv,
  DateTime? now,
}) {
  final text = decodePortfolioText(bytes, encoding: csv?.encoding);
  final clock = now ?? DateTime.now();
  final digest = sha256.convert(bytes).toString();
  late String broker, alias, date, capturedAt, format;
  late double cash;
  late List<Map<String, dynamic>> rows;
  if (text.trimLeft().startsWith('{')) {
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic> ||
        j['snapshotVersion'] != 1 ||
        j['complete'] != true ||
        j['currency'] != 'CNY' ||
        j['accountType'] != 'cash_equity') {
      throw const FormatException(
        '需要完整的 CNY 普通股票账户快照（snapshotVersion 1）；融资账户暂不支持',
      );
    }
    broker = _label(j['broker'], '券商名称');
    alias = _label(j['accountAlias'], '账户别名');
    date = dateField(j, 'priceDate');
    capturedAt = brokerTimestamp(j['capturedAt'], '快照时间');
    final captured = DateTime.parse(capturedAt);
    if (captured.isAfter(clock.toUtc().add(const Duration(minutes: 5)))) {
      throw const FormatException('快照时间无效或在未来');
    }
    final chinaDay = captured
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    if (date.compareTo(chinaDay) > 0) throw const FormatException('估值日期晚于快照时间');
    cash = _amount(j['cash'], '账户现金余额');
    final values = j['holdings'];
    if (values is! List || values.any((v) => v is! Map<String, dynamic>)) {
      throw const FormatException('holdings 必须是完整持仓列表');
    }
    rows = values.cast<Map<String, dynamic>>();
    format = 'json';
  } else {
    if (csv == null) throw const FormatException('CSV 需要填写券商、账户别名、估值日期和现金余额');
    broker = _label(csv.broker, '券商名称');
    alias = _label(csv.accountAlias, '账户别名');
    date = csv.priceDate;
    if (!validDate(date)) throw const FormatException('估值日期无效');
    cash = _amount(csv.cash, '账户现金余额');
    capturedAt = clock.toUtc().toIso8601String();
    rows = _csvHoldings(text, csv);
    format = 'csv';
  }
  final today = clock
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);
  if (date.compareTo(today) > 0) throw const FormatException('估值日期不能在未来');
  if (rows.length > 1000) throw const FormatException('最多支持 1000 项持仓');
  final codes = <String>{};
  final holdings = <Holding>[];
  for (var i = 0; i < rows.length; i++) {
    final holding = _holding(rows[i], i + 1);
    if (!codes.add(holding.code)) {
      throw FormatException('${holding.code} 重复，未自动合并');
    }
    if (holding.quantity > 0) holdings.add(holding);
  }
  final snapshot = BrokerSnapshot(
    info: PortfolioImportInfo(
      broker: broker,
      accountAlias: alias,
      capturedAt: capturedAt,
      importedAt: clock.toUtc().toIso8601String(),
      digest: digest,
      format: format,
    ),
    priceDate: date,
    cash: cash,
    holdings: holdings,
  );
  if (!snapshot.assets.isFinite) throw const FormatException('账户资产超出计算范围');
  return snapshot;
}

// CSV aliases deliberately distinguish total holdings from available shares,
// and current price from cost price. Unknown columns are never guessed.
const _columns = {
  'code': ['证券代码', '股票代码', '代码', 'code'],
  'name': ['证券名称', '股票名称', '名称', 'name'],
  'quantity': ['股票余额', '证券数量', '持仓数量', '持股数量', 'quantity'],
  'price': ['市价', '当前价', '最新价', '最新价格', 'price'],
  'industry': ['行业', 'industry'],
};

class BrokerCsvTable {
  BrokerCsvTable({
    required List<String> headers,
    required List<List<String>> rows,
    required this.delimiter,
    required Map<String, int> suggestedMapping,
  }) : headers = List.unmodifiable(headers),
       rows = List.unmodifiable(rows.map((r) => List<String>.unmodifiable(r))),
       suggestedMapping = Map.unmodifiable(suggestedMapping);

  final List<String> headers;
  final List<List<String>> rows;
  final String delimiter;

  /// Only unambiguous known headers are suggested; missing fields need review.
  final Map<String, int> suggestedMapping;
  bool get needsMapping =>
      ![
        'code',
        'name',
        'quantity',
        'price',
      ].every(suggestedMapping.containsKey) ||
      _columns.values.any(
        (aliases) => headers.where(aliases.contains).length > 1,
      );
}

BrokerCsvTable inspectBrokerCsv(
  List<int> bytes, {
  String? delimiter,
  PortfolioTextEncoding? encoding,
}) => _inspectCsvText(
  decodePortfolioText(bytes, encoding: encoding),
  delimiter: delimiter,
);

String _detectDelimiter(String text) {
  final counts = {',': 0, '\t': 0, ';': 0};
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (!quoted) {
      if (c == '\r' || c == '\n') break;
      if (counts.containsKey(c)) counts[c] = counts[c]! + 1;
    }
  }
  final maximum = counts.values.reduce((a, b) => a > b ? a : b);
  if (maximum == 0) return ',';
  final candidates = counts.keys.where((c) => counts[c] == maximum).toList();
  if (candidates.length != 1) {
    throw const FormatException('无法确定 CSV 分隔符，请指定逗号、制表符或分号');
  }
  return candidates.single;
}

BrokerCsvTable _inspectCsvText(String text, {String? delimiter}) {
  final separator = delimiter ?? _detectDelimiter(text);
  final table = parseCsv(text, delimiter: separator);
  if (table.isEmpty || table.first.every((h) => h.trim().isEmpty)) {
    throw const FormatException('CSV 没有表头');
  }
  final headers = table.first.map((h) => h.trim()).toList();
  final rows = <List<String>>[];
  for (final row in table.skip(1)) {
    if (row.every((cell) => cell.trim().isEmpty)) continue;
    if (row.length != headers.length) {
      throw const FormatException('CSV 行列数不一致，请检查分隔符与引号');
    }
    rows.add(row);
  }
  if (rows.length > 1000) throw const FormatException('最多支持 1000 项持仓');
  final indexes = <String, int>{};
  for (final entry in _columns.entries) {
    final matches = [
      for (var i = 0; i < headers.length; i++)
        if (entry.value.contains(headers[i])) i,
    ];
    if (matches.length == 1) indexes[entry.key] = matches.single;
  }
  return BrokerCsvTable(
    headers: headers,
    rows: rows,
    delimiter: separator,
    suggestedMapping: indexes,
  );
}

List<Map<String, dynamic>> _csvHoldings(String text, CsvAccountDetails csv) {
  final table = _inspectCsvText(text, delimiter: csv.delimiter);
  if (csv.columnMapping == null) {
    for (final entry in _columns.entries) {
      if (table.headers.where(entry.value.contains).length > 1) {
        throw FormatException('${entry.key} 存在多个候选列，请选择列映射');
      }
    }
  }
  final indexes = csv.columnMapping ?? table.suggestedMapping;
  validateBrokerCsvMapping(table, indexes);
  return [
    for (final row in table.rows)
      {
        for (final entry in indexes.entries)
          entry.key: entry.key == 'code'
              ? _csvCodeLiteral(row[entry.value].trim())
              : row[entry.value].trim(),
      },
  ];
}

void validateBrokerCsvMapping(BrokerCsvTable table, Map<String, int> indexes) {
  if (indexes.keys.any((key) => !_columns.containsKey(key))) {
    throw const FormatException('CSV 列映射包含未知字段');
  }
  for (final field in ['code', 'name', 'quantity', 'price']) {
    if (!indexes.containsKey(field)) {
      throw FormatException(
        '缺少或存在多个 ${_columns[field]!.first} 候选列，请选择列映射；数量需用总持仓，价格需用市价',
      );
    }
  }
  if (indexes.values.any((i) => i < 0 || i >= table.headers.length)) {
    throw const FormatException('CSV 列映射超出表头范围');
  }
  if (indexes.values.toSet().length != indexes.length) {
    throw const FormatException('CSV 列映射不能重复使用同一列');
  }
  if (RegExp(
    r'可用|可卖|可售|冻结|available|sellable|tradable|frozen',
    caseSensitive: false,
  ).hasMatch(table.headers[indexes['quantity']!])) {
    throw const FormatException('数量需使用总持仓列，不能使用可用或可卖数量');
  }
  if (RegExp(
    r'成本|买入价|购买价|均价|cost|purchase|average|avg',
    caseSensitive: false,
  ).hasMatch(table.headers[indexes['price']!])) {
    throw const FormatException('价格需使用市价列，不能使用成本价');
  }
}

String _csvCodeLiteral(String code) {
  // An apostrophe is Excel's explicit text marker, not a formula. Only strip
  // it when the entire remaining value is an A-share code; never evaluate =.
  if (RegExp(
    r"^'\d{6}(?:\.(?:SH|SZ|BJ))?$",
    caseSensitive: false,
  ).hasMatch(code)) {
    return code.substring(1);
  }
  return code;
}

/// RFC-style quoted cells, escaped quotes, CRLF and embedded newlines.
List<List<String>> parseCsv(String text, {String delimiter = ','}) {
  if (![',', '\t', ';'].contains(delimiter)) {
    throw const FormatException('CSV 分隔符需为逗号、制表符或分号');
  }
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false, closed = false;
  void finishCell() {
    row.add(cell.toString());
    cell = StringBuffer();
    closed = false;
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
      }
    } else if (c == delimiter) {
      finishCell();
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      finishCell();
      rows.add(row);
      row = [];
    } else if (c == '"' && cell.isEmpty && !closed) {
      quoted = true;
    } else if (closed || c == '"') {
      throw const FormatException('CSV 引号格式无效');
    } else {
      cell.write(c);
    }
  }
  if (quoted) throw const FormatException('CSV 引号未闭合，文件可能未写完');
  if (cell.isNotEmpty || row.isNotEmpty || closed) {
    finishCell();
    rows.add(row);
  }
  return rows;
}

bool brokerSourceChangeNeedsConfirmation(
  WorkspaceData data,
  BrokerSnapshot snapshot,
) {
  final previous = data.portfolioImport;
  return previous != null
      ? previous.identity != snapshot.info.identity
      : data.deposits > 0 || data.withdrawals > 0;
}

WorkspaceData applyBrokerSnapshot(
  WorkspaceData data,
  BrokerSnapshot snapshot, {
  bool automatic = false,
  bool sourceChangeConfirmed = false,
}) {
  if (data.isDemo) throw const FormatException('请先新建空白工作区，真实持仓不可混入演示');
  if ((data.holdings.isNotEmpty ||
          data.cash > 0 ||
          data.portfolioImport != null) &&
      snapshot.priceDate.compareTo(data.priceDate) < 0) {
    throw const FormatException('快照估值日期早于当前账户，未回退');
  }
  final previous = data.portfolioImport;
  if (!automatic &&
      previous != null &&
      previous.identity != snapshot.info.identity &&
      !sourceChangeConfirmed) {
    throw const FormatException('导入来源账户已改变，请先核对累计入金与出金的账户归属');
  }
  if (previous != null &&
      previous.identity == snapshot.info.identity &&
      DateTime.parse(snapshot.info.capturedAt)
          .isBefore(DateTime.parse(previous.capturedAt))) {
    throw const FormatException('快照时间早于上次导入，未回退');
  }
  if (automatic) {
    if (snapshot.info.format != 'json' ||
        previous == null ||
        previous.modified ||
        previous.identity != snapshot.info.identity) {
      throw const FormatException('自动导入需要已核对的同一账户 JSON；账户改变或人工修改后需重新确认');
    }
    if (snapshot.holdings.isEmpty) {
      throw const FormatException('空持仓需要手动确认，自动导入未清空账户');
    }
    if (DateTime.parse(snapshot.info.capturedAt)
            .isAtSameMomentAs(DateTime.parse(previous.capturedAt)) &&
        snapshot.info.digest != previous.digest) {
      throw const FormatException('相同快照时间对应不同内容，需要手动核对');
    }
  }
  final byCode = {for (final h in data.holdings) h.code: h};
  final result = data.copyWith(
    cash: snapshot.cash,
    priceDate: snapshot.priceDate,
    holdings: snapshot.holdings.map((h) {
      final old = byCode[h.code];
      return Holding(
        id: old?.id ?? h.id,
        code: h.code,
        name: h.name,
        industry: h.industry == '行业资料不足'
            ? old?.industry ?? h.industry
            : h.industry,
        quantity: h.quantity,
        price: h.price,
      );
    }).toList(),
    portfolioImport: snapshot.info,
  );
  // Validate the whole workspace before any persistent write.
  return WorkspaceData.decode(result.encode());
}

String portfolioFingerprint(WorkspaceData data) => jsonEncode({
  'cash': data.cash,
  'priceDate': data.priceDate,
  'holdings': data.holdings.map((h) => h.toJson()).toList(),
});
