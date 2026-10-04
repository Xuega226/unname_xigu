import 'research.dart';

String brokerMetadataLabel(dynamic value, String label) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 120 ||
      RegExp(r'[\x00-\x1F\x7F-\x9F]').hasMatch(value)) {
    throw FormatException('$label 为空、过长或含控制字符');
  }
  return value.trim();
}

/// Validate each clock component before parsing: DateTime.parse normalizes
/// out-of-range hours, minutes and offsets instead of rejecting them.
String brokerTimestamp(dynamic value, String label) {
  if (value is! String || value.length > 120) {
    throw FormatException('$label 需要合法且包含明确时区的 ISO 时间');
  }
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null ||
      match.end != value.length ||
      !validDate(match.group(1)!) ||
      int.parse(match.group(2)!) > 23 ||
      int.parse(match.group(3)!) > 59 ||
      int.parse(match.group(4)!) > 59 ||
      (match.group(5) != null && int.parse(match.group(5)!) > 23) ||
      (match.group(6) != null && int.parse(match.group(6)!) > 59) ||
      DateTime.tryParse(value) == null) {
    throw FormatException('$label 需要合法且包含明确时区的 ISO 时间');
  }
  return value;
}

String brokerTimeLabel(String value) {
  final time = DateTime.parse(value).toUtc().add(const Duration(hours: 8));
  return '${time.toIso8601String().substring(0, 19).replaceFirst('T', ' ')}（北京时间）';
}

/// Audit metadata only. Credentials and local file paths are never exported.
class PortfolioImportInfo {
  const PortfolioImportInfo({
    required this.broker,
    required this.accountAlias,
    required this.capturedAt,
    required this.importedAt,
    required this.digest,
    required this.format,
    this.modified = false,
  });
  final String broker, accountAlias, capturedAt, importedAt, digest, format;
  final bool modified;
  String get identity => '$broker\u0000$accountAlias';
  PortfolioImportInfo markModified() => PortfolioImportInfo(
    broker: broker,
    accountAlias: accountAlias,
    capturedAt: capturedAt,
    importedAt: importedAt,
    digest: digest,
    format: format,
    modified: true,
  );
  Map<String, dynamic> toJson() => {
    'broker': broker,
    'accountAlias': accountAlias,
    'capturedAt': capturedAt,
    'importedAt': importedAt,
    'digest': digest,
    'format': format,
    'modified': modified,
  };
  factory PortfolioImportInfo.fromJson(Map<String, dynamic> j) {
    final digest = j['digest'];
    final format = j['format'];
    if (digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        !['csv', 'json'].contains(format) ||
        j['modified'] is! bool) {
      throw const FormatException('持仓导入记录无效');
    }
    return PortfolioImportInfo(
      broker: brokerMetadataLabel(j['broker'], '券商名称'),
      accountAlias: brokerMetadataLabel(j['accountAlias'], '账户别名'),
      capturedAt: brokerTimestamp(j['capturedAt'], '快照时间'),
      importedAt: brokerTimestamp(j['importedAt'], '导入时间'),
      digest: digest,
      format: format as String,
      modified: j['modified'] as bool,
    );
  }
}
