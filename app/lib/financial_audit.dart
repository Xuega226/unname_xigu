import 'dart:convert';

import 'research.dart';

/// A user's report-level adoption, not a claim of individual human inspection
/// or permission for autonomous adoption. Snapshot data is immutable internally.
class FinancialAudit {
  FinancialAudit._(this._json);
  final String _json;
  Map<String, dynamic> toJson() => jsonDecode(_json) as Map<String, dynamic>;
  String get method => 'reportConfirmed';
  String get model => toJson()['model'] as String;
  String get fingerprint => toJson()['fingerprint'] as String;
  String get acceptedAt => toJson()['acceptedAt'] as String;

  factory FinancialAudit.fromJson(Map<String, dynamic> j) {
    final encoded = jsonEncode(j);
    _tree(j);
    if (encoded.length > 500000 ||
        j['version'] != 1 ||
        j['method'] != 'reportConfirmed') {
      throw const FormatException('财务核验审计版本、确认方式或大小无效');
    }
    for (final key in [
      'model',
      'extractionVersion',
      'reviewVersion',
      'checkVersion',
    ]) {
      _text(j, key, 120);
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(_text(j, 'fingerprint', 64))) {
      throw const FormatException('核验输入指纹无效');
    }
    final acceptedAt = _text(j, 'acceptedAt', 40);
    if (!RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(acceptedAt) ||
        DateTime.tryParse(acceptedAt) == null ||
        !validDate(acceptedAt.substring(0, 10)) ||
        int.parse(acceptedAt.substring(11, 13)) > 23 ||
        int.parse(acceptedAt.substring(14, 16)) > 59 ||
        int.parse(acceptedAt.substring(17, 19)) > 59) {
      throw const FormatException('核验采纳时间需要有效日期与时区');
    }
    if (!acceptedAt.endsWith('Z')) {
      final offset = acceptedAt.substring(acceptedAt.length - 6);
      final hour = int.parse(offset.substring(1, 3));
      final minute = int.parse(offset.substring(4));
      if (hour > 14 || minute > 59 || (hour == 14 && minute != 0)) {
        throw const FormatException('核验采纳时间的时区无效');
      }
    }
    final rawSources = _maps(j, 'sources', 100, minimum: 1);
    final sources = <String, SourceExcerpt>{};
    var total = 0;
    for (final raw in rawSources) {
      _tree(raw);
      final source = SourceExcerpt.fromJson(raw);
      if (source.id.length > 200 || sources.containsKey(source.id)) {
        throw const FormatException('核验来源 ID 重复或过长');
      }
      sources[source.id] = source;
      total += source.text.length;
    }
    if (total > 60000) throw const FormatException('核验来源最多 60000 字');
    final candidates = _maps(j, 'candidates', 20, minimum: 1);
    for (final candidate in candidates) {
      _validateCandidate(candidate);
    }
    final reviews = _maps(j, 'reviews', 20, minimum: 1);
    final byIndex = <int, Map<String, dynamic>>{};
    for (final review in reviews) {
      final index = _index(review['index'], candidates.length);
      if (byIndex.containsKey(index) ||
          ![
            'pass',
            'fail',
            'unknown',
            'notApplicable',
          ].contains(review['verdict'])) {
        throw const FormatException('复核索引重复或结论无效');
      }
      byIndex[index] = review;
      _text(review, 'reason', 2000);
      final sourceId = _text(review, 'sourceId', 200, empty: true);
      final quote = _text(review, 'quote', 24000, empty: true);
      if (review['verdict'] == 'pass' ||
          sourceId.isNotEmpty ||
          quote.isNotEmpty) {
        final source = sources[sourceId];
        if (source == null ||
            _normalize(quote).length < 8 ||
            !_normalize(source.text).contains(_normalize(quote))) {
          throw const FormatException('复核引用不在核验原文中');
        }
        if (review['verdict'] == 'pass') {
          final candidate = candidates[index];
          final proof = FinancialEvidence(
            sourceId: sourceId,
            quote: quote,
            rawValue: candidate['rawValue'] as String,
            label: candidate['label'] as String,
          );
          if (sourceId != candidate['sourceId'] || !proof.validFor(source)) {
            throw const FormatException('通过复核的引用不支持对应财务候选');
          }
        }
      }
    }
    if (byIndex.length != candidates.length) {
      throw const FormatException('逐项复核不完整');
    }
    final rawSelected = j['selected'];
    if (rawSelected is! List || rawSelected.isEmpty || rawSelected.length > 5) {
      throw const FormatException('核验采纳集合无效');
    }
    final selected = rawSelected
        .map((v) => _index(v, candidates.length))
        .toSet();
    if (selected.length != rawSelected.length) {
      throw const FormatException('采纳索引重复');
    }
    final overrides = _maps(j, 'overrides', 5);
    final overrideIndices = <int>{};
    for (final override in overrides) {
      final index = _index(override['index'], candidates.length);
      _text(override, 'reason', 2000);
      if (!selected.contains(index) || !overrideIndices.add(index)) {
        throw const FormatException('人工例外索引重复或未采纳');
      }
    }
    final metrics = <String>{};
    for (final index in selected) {
      final candidate = candidates[index];
      final source = sources[candidate['sourceId']];
      final proof = FinancialEvidence.fromJson(candidate);
      if (!metrics.add(candidate['metric'] as String) ||
          source == null ||
          source.unit != candidate['unit'] ||
          !proof.validFor(source) ||
          !financialMetricLabelValid(
            candidate['metric'] as String,
            proof.label,
          ) ||
          !financialPeriodMatches(
            source.period,
            candidate['start'] as String,
            candidate['end'] as String,
          ) ||
          candidate['end'].compareTo(source.disclosedAt) > 0 ||
          (proof.value < 0 &&
              ![
                'adjustedProfit',
                'operatingCash',
              ].contains(candidate['metric'])) ||
          (byIndex[index]!['verdict'] != 'pass' &&
              !overrideIndices.contains(index))) {
        throw const FormatException('采纳字段未通过硬规则或缺少人工例外理由');
      }
    }
    final usage = _maps(j, 'usage', 3);
    final stages = <String>{};
    for (final item in usage) {
      if (!['preparation', 'extraction', 'review'].contains(item['stage']) ||
          !stages.add(item['stage'] as String)) {
        throw const FormatException('调用阶段无效或重复');
      }
      _tree(item);
      for (final key in [
        'prompt_tokens',
        'completion_tokens',
        'total_tokens',
        'promptCacheHitTokens',
        'promptCacheMissTokens',
      ]) {
        final value = item[key];
        if (value != null &&
            (value is! int || value < 0 || value > 1000000000)) {
          throw const FormatException('实际调用用量无效');
        }
      }
      if (item['unknown'] != null && item['unknown'] is! bool) {
        throw const FormatException('调用用量未知状态无效');
      }
    }
    if (!stages.containsAll(['extraction', 'review'])) {
      throw const FormatException('缺少提取或复核调用用量记录');
    }
    if (j['preparation'] != null) {
      if (j['preparation'] is! Map<String, dynamic> ||
          jsonEncode(j['preparation']).length > 100000) {
        throw const FormatException('报告准备审计无效或过大');
      }
      _tree(j['preparation']);
    }
    return FinancialAudit._(encoded);
  }

  /// Bind adopted candidates to the exact record saved with this audit.
  void validateRecord(FinancialRecord record) {
    final data = toJson();
    final candidates = data['candidates'] as List;
    final sources = {
      for (final raw in data['sources'] as List)
        raw['id']: SourceExcerpt.fromJson(raw as Map<String, dynamic>),
    };
    final metrics = <String>{};
    final adoptedSourceIds = <String>{};
    for (final index in data['selected'] as List) {
      final c = candidates[index as int] as Map<String, dynamic>;
      final source = sources[c['sourceId']]!;
      final metric = c['metric'] as String;
      final proof = FinancialEvidence.fromJson(c);
      metrics.add(metric);
      adoptedSourceIds.add(proof.sourceId);
      if (source.studyId != record.studyId ||
          source.disclosedAt != record.disclosedAt ||
          c['start'] != record.start ||
          c['end'] != record.end ||
          c['unit'] != record.unit ||
          c['scope'] != record.scope ||
          proof.value != record.amounts[metric] ||
          jsonEncode(proof.toJson()) !=
              jsonEncode(record.evidence[metric]?.toJson())) {
        throw const FormatException('核验审计与采纳财务记录不一致');
      }
    }
    if (record.origin != 'aiConfirmed' ||
        record.scope == '未注明' ||
        record.amounts.entries.any(
          (e) => e.value != null && !metrics.contains(e.key),
        ) ||
        !adoptedSourceIds.contains(record.sourceId)) {
      throw const FormatException('核验审计确认方式或字段集合不一致');
    }
  }

  /// Backup/import cannot substitute the current source for the reviewed one.
  void validateSources(List<SourceExcerpt> current, String studyId) {
    final byId = {for (final source in current) source.id: source};
    for (final raw in toJson()['sources'] as List) {
      final snapshot = SourceExcerpt.fromJson(raw as Map<String, dynamic>);
      final source = byId[snapshot.id];
      if (source == null ||
          source.studyId != studyId ||
          jsonEncode(source.toJson()) != jsonEncode(snapshot.toJson())) {
        throw const FormatException('核验来源快照与当前公司原文不一致');
      }
    }
  }
}

String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), '');
String _text(
  Map<String, dynamic> map,
  String key,
  int max, {
  bool empty = false,
}) {
  final value = map[key];
  if (value is! String ||
      value.length > max ||
      (!empty && value.trim().isEmpty)) {
    throw FormatException('核验 $key 文本无效');
  }
  return value;
}

int _index(dynamic value, int length) {
  if (value is! int || value < 0 || value >= length) {
    throw const FormatException('核验索引越界');
  }
  return value;
}

List<Map<String, dynamic>> _maps(
  Map<String, dynamic> map,
  String key,
  int max, {
  int minimum = 0,
}) {
  final value = map[key];
  if (value is! List ||
      value.length < minimum ||
      value.length > max ||
      value.any((e) => e is! Map<String, dynamic>)) {
    throw FormatException('核验 $key 列表无效');
  }
  return value.cast<Map<String, dynamic>>();
}

void _validateCandidate(Map<String, dynamic> candidate) {
  if (!FinancialRecord.metrics.contains(candidate['metric']) ||
      !['元', '万元', '亿元'].contains(candidate['unit']) ||
      !['合并', '母公司', '未注明'].contains(candidate['scope'])) {
    throw const FormatException('核验候选指标、单位或口径无效');
  }
  final start = dateField(candidate, 'start'),
      end = dateField(candidate, 'end');
  if (start.compareTo(end) > 0) throw const FormatException('核验期间顺序无效');
  for (final key in ['sourceId', 'rawValue', 'label']) {
    _text(candidate, key, 200);
  }
  _text(candidate, 'quote', 24000);
  FinancialEvidence.fromJson(candidate);
  _tree(candidate);
}

void _tree(dynamic value, [int depth = 0]) {
  if (depth > 12) throw const FormatException('核验附加资料嵌套过深');
  if (value == null || value is bool) return;
  if (value is String && value.length <= 60000) return;
  if (value is num && value.isFinite) return;
  if (value is List && value.length <= 100) {
    for (final item in value) {
      _tree(item, depth + 1);
    }
    return;
  }
  if (value is Map<String, dynamic> && value.length <= 100) {
    for (final entry in value.entries) {
      if (entry.key.length > 200) throw const FormatException('核验附加字段名过长');
      _tree(entry.value, depth + 1);
    }
    return;
  }
  throw const FormatException('核验附加资料格式或大小无效');
}
