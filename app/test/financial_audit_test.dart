import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/financial_audit.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/storage.dart';
import 'package:lianghua_assistant/quant_engine.dart';

import 'support/v07_fixture.dart';

const source = SourceExcerpt(
  id: 'audited-source',
  studyId: 'v07-study',
  title: '虚构报告',
  url: 'https://example.com/audited',
  period: '2025年度',
  disclosedAt: '2026-04-01',
  page: '第1页',
  unit: '万元',
  text: '2025年度合并报表：营业收入为100万元，经营活动现金流净额为负20万元。',
);
Map<String, dynamic> auditJson() => {
  'version': 1,
  'method': 'reportConfirmed',
  'model': 'test-model',
  'extractionVersion': '1',
  'reviewVersion': '1',
  'checkVersion': '1',
  'fingerprint': List.filled(64, 'a').join(),
  'acceptedAt': '2026-10-05T10:00:00+08:00',
  'sources': [source.toJson()],
  'candidates': [
    {
      'metric': 'revenue',
      'unit': '万元',
      'start': '2025-01-01',
      'end': '2025-12-31',
      'scope': '合并',
      'sourceId': source.id,
      'quote': '营业收入为100万元',
      'rawValue': '100',
      'label': '营业收入',
    },
    {
      'metric': 'operatingCash',
      'unit': '万元',
      'start': '2025-01-01',
      'end': '2025-12-31',
      'scope': '合并',
      'sourceId': source.id,
      'quote': '经营活动现金流净额为负20万元',
      'rawValue': '负20',
      'label': '经营活动现金流净额',
    },
  ],
  'reviews': [
    {
      'index': 0,
      'verdict': 'pass',
      'reason': '本期营业收入',
      'sourceId': source.id,
      'quote': '营业收入为100万元',
    },
    {
      'index': 1,
      'verdict': 'pass',
      'reason': '本期经营现金流，负数保留',
      'sourceId': source.id,
      'quote': '经营活动现金流净额为负20万元',
    },
  ],
  'selected': [0, 1],
  'overrides': [],
  'usage': [
    {
      'stage': 'extraction',
      'prompt_tokens': 100,
      'completion_tokens': 20,
      'total_tokens': 120,
    },
    {'stage': 'review', 'unknown': true},
  ],
  'preparation': {
    'method': 'aiSuggestion',
    'warnings': ['虚构离线夹具'],
  },
};
Map<String, dynamic> recordJson() => {
  'id': 'audited-financial',
  'studyId': source.studyId,
  'sourceId': source.id,
  'start': '2025-01-01',
  'end': '2025-12-31',
  'disclosedAt': source.disclosedAt,
  'unit': '万元',
  'scope': '合并',
  'basis': '原披露',
  'origin': 'aiConfirmed',
  'revenue': 100,
  'operatingCash': -20,
  'evidence': {
    'revenue': {
      'sourceId': source.id,
      'quote': '营业收入为100万元',
      'rawValue': '100',
      'label': '营业收入',
    },
    'operatingCash': {
      'sourceId': source.id,
      'quote': '经营活动现金流净额为负20万元',
      'rawValue': '负20',
      'label': '经营活动现金流净额',
    },
  },
  'audit': auditJson(),
};
WorkspaceData auditedWorkspace() {
  final initial = v07Fixture();
  return initial.copyWith(
    sources: [...initial.sources, source],
    financials: [...initial.financials, FinancialRecord.fromJson(recordJson())],
  );
}

void main() {
  test(
    'report confirmation retains full audit, negative and missing values',
    () {
      final workspace = auditedWorkspace();
      final reopened = WorkspaceData.decode(workspace.encode());
      final record = reopened.financials.last;
      expect(reopened.encode(), workspace.encode());
      expect(record.confirmationLabel, 'AI 预核验 · 报告级确认');
      expect(record.operatingCash, -20);
      expect(record.cash, isNull);
      expect(record.audit!.toJson(), auditJson());
      final exposed = record.audit!.toJson();
      exposed['selected'].clear();
      expect(record.audit!.toJson()['selected'], [0, 1]);
      final legacy = recordJson()..remove('audit');
      expect(
        FinancialRecord.fromJson(legacy).confirmationLabel,
        'AI 提取 · 逐项人工确认',
      );
      expect(v07Fixture().financials.first.confirmationLabel, '人工录入');
    },
  );
  test('malformed audit, invented citations and false autonomous adoption rejected', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) => j['method'] = 'autoAdopted',
      (j) => j['version'] = 2,
      (j) => j['fingerprint'] = 'fake',
      (j) => j['acceptedAt'] = '2026-02-31T10:00:00Z',
      (j) => j['acceptedAt'] = '2026-10-05T25:00:00Z',
      (j) => j['acceptedAt'] = '2026-10-05T10:00:00',
      (j) => j['acceptedAt'] = '2026-10-05T10:00:00+25:00',
      (j) => j['sources'].add(j['sources'][0]),
      (j) => j['sources'][0]['period'] = '2024年度',
      (j) => j['candidates'][0]['quote'] = '虚构营业收入为200万元',
      (j) => j['reviews'][0]['quote'] = '编造的审查出处文本',
      (j) => j['reviews'][0]['quote'] = '2025年度合并报表',
      (j) => j['reviews'][0]['quote'] = '经营活动现金流净额为负20万元',
      (j) => j['reviews'][0]['verdict'] = 'passed',
      (j) => j['reviews'].removeLast(),
      (j) => j['selected'] = [0, 0],
      (j) => j['selected'] = [2],
      (j) => j['usage'][0]['total_tokens'] = -1,
      (j) => j['usage'] = [],
      (j) => j['candidates'][0]['start'] = '2025-13-01',
      (j) => j['candidates'][0]['unit'] = '亿元',
    ]) {
      final data = auditJson();
      mutate(data);
      expect(() => FinancialAudit.fromJson(data), throwsFormatException);
    }
  });
  test(
    'semantic manual exception needs reason and cannot bypass a hard error',
    () {
      final data = auditJson();
      data['reviews'][0]['verdict'] = 'unknown';
      expect(() => FinancialAudit.fromJson(data), throwsFormatException);
      data['overrides'] = [
        {'index': 0, 'reason': '人工对照本期表头并确认口径'},
      ];
      expect(FinancialAudit.fromJson(data).toJson(), data);
      data['candidates'][0]['rawValue'] = '200';
      expect(() => FinancialAudit.fromJson(data), throwsFormatException);
    },
  );
  test('hard metric labels and explicit annual period cannot be bypassed by backups', () {
    final data = auditJson();
    data['candidates'][0]['metric'] = 'debt';
    data['overrides'] = [
      {'index': 0, 'reason': '试图忽略指标错误'},
    ];
    expect(() => FinancialAudit.fromJson(data), throwsFormatException);
    expect(
      financialPeriodMatches('2025年度', '2025-01-01', '2025-12-31'),
      isTrue,
    );
    expect(
      financialPeriodMatches('2024年报', '2025-01-01', '2025-12-31'),
      isFalse,
    );
    expect(
      financialPeriodMatches('2025年第一季度', '2025-01-01', '2025-03-31'),
      isTrue,
    );
    expect(financialPeriodMatches('期间未注明', '2025-01-01', '2025-12-31'), isTrue);
  });
  test('record and immutable source snapshots must match reviewed values', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) => j['origin'] = 'manual',
      (j) => j['revenue'] = 101,
      (j) => j['end'] = '2025-06-30',
      (j) => j['cash'] = 0,
      (j) => j['audit']['selected'] = [0],
      (j) => j['audit']['sources'][0]['studyId'] = 'other-study',
    ]) {
      final json = recordJson();
      mutate(json);
      expect(() => FinancialRecord.fromJson(json), throwsFormatException);
    }
    final map = auditedWorkspace().toJson();
    (map['sources'] as List).last['text'] += '改动后的原文';
    expect(() => WorkspaceData.decode(jsonEncode(map)), throwsFormatException);
    final legacyMap = auditedWorkspace().toJson()..['schemaVersion'] = 7;
    expect(
      () => WorkspaceData.decode(jsonEncode(legacyMap)),
      throwsFormatException,
    );
  });
  test('invalid audit save preserves existing workspace bytes', () async {
    final directory = await Directory.systemTemp.createTemp('xigu-v073-audit-');
    addTearDown(() async {
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      final actual = await directory.resolveSymbolicLinks();
      if (!actual.startsWith('$temp${Platform.pathSeparator}')) {
        throw StateError('Unsafe cleanup');
      }
      await directory.delete(recursive: true);
    });
    final store = LocalWorkspaceStore(directory);
    final original = auditedWorkspace();
    await store.save(original);
    final bytes = await store.file.readAsBytes();
    final changedSource = SourceExcerpt.fromJson({
      ...source.toJson(),
      'text': '${source.text} 修改后的资料',
    });
    final changed = original.copyWith(
      sources: [
        ...original.sources.where((s) => s.id != source.id),
        changedSource,
      ],
    );
    await expectLater(store.save(changed), throwsFormatException);
    expect(await store.file.readAsBytes(), bytes);
    expect((await store.load())!.encode(), original.encode());
  });
  for (final backupOnly in [false, true]) {
    test(
      'schema7 migration from $backupOnly backup keeps exact bytes, quant and funds',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'xigu-v073-audit-',
        );
        addTearDown(() async {
          final temp = await Directory.systemTemp.resolveSymbolicLinks();
          final actual = await directory.resolveSymbolicLinks();
          if (!actual.startsWith('$temp${Platform.pathSeparator}')) {
            throw StateError('Unsafe cleanup');
          }
          await directory.delete(recursive: true);
        });
        final store = LocalWorkspaceStore(directory);
        final original = v07Fixture();
        final map = original.toJson()..['schemaVersion'] = 7;
        final bytes = utf8.encode(
          '${const JsonEncoder.withIndent('  ').convert(map).replaceAll('\n', '\r\n')}\r\n',
        );
        await (backupOnly ? store.backup : store.file).writeAsBytes(bytes);
        final migrated = (await store.load())!;
        final archive = File('${store.file.path}.v7.bak');
        expect(await archive.readAsBytes(), bytes);
        expect(migrated.encode(), original.encode());
        expect(migrated.toJson()['schemaVersion'], 8);
        expect(evaluateQuant(migrated).ranked.single.score, 75);
        expect(migrated.principal, 10500);
        expect(migrated.financials.every((r) => r.audit == null), isTrue);
        await store.save(auditedWorkspace());
        expect(
          (await store.load())!.financials.last.audit!.toJson(),
          auditJson(),
        );
        expect(await archive.readAsBytes(), bytes);
      },
    );
  }
}
