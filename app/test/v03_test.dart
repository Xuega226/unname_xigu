import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/financial_extraction.dart';
import 'package:lianghua_assistant/financial_trends.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

import 'research_test.dart' show FakeTransport;

const originalText =
    '2025年度合并报表，单位万元。营业收入为100.00万元，扣非净利润为8.00万元，经营现金流为负20.00万元。';
ReportDocument document({String? text}) => ReportDocument(
  id: 'd0',
  studyId: 's0',
  fileName: '../../report.pdf',
  sha256: 'a' * 64,
  title: '虚构测试财报',
  url: '',
  period: '2025年度',
  start: '2025-01-01',
  end: '2025-12-31',
  disclosedAt: '2026-03-31',
  unit: '万元',
  importedAt: '2026-10-01T00:00:00Z',
  pageCount: 2,
  pages: [ReportPage(number: 2, text: text ?? originalText)],
);
Map<String, dynamic> candidateJson({
  String raw = '100.00',
  String metric = 'revenue',
  String label = '营业收入',
  String? quote,
}) => {
  'metric': metric,
  'rawValue': raw,
  'label': label,
  'unit': '万元',
  'start': '2025-01-01',
  'end': '2025-12-31',
  'scope': '合并',
  'sourceId': 'd0-p2-0',
  'quote': quote ?? originalText,
};
WorkspaceData workspace() {
  final doc = document();
  return WorkspaceData.empty().copyWith(
    studies: WorkspaceData.demo().studies,
    documents: [doc],
    sources: doc.excerpts(),
  );
}

FinancialRecord record(
  int year,
  double? revenue, {
  String unit = '万元',
  String scope = '合并',
  String basis = '原披露',
  String studyId = 's0',
  String? end,
}) => FinancialRecord(
  id: '$year-$unit-$studyId',
  studyId: studyId,
  sourceId: 's',
  start: '$year-01-01',
  end: end ?? '$year-12-31',
  disclosedAt: '${year + 1}-03-31',
  unit: unit,
  scope: scope,
  basis: basis,
  revenue: revenue,
  adjustedProfit: revenue,
);

void main() {
  test(
    'v2 disk migration retains original bytes and legacy unknown basis',
    () async {
      final old = workspace().toJson()
        ..['schemaVersion'] = 2
        ..remove('documents')
        ..remove('studyVersions');
      old['sources'] = [];
      old['studies'] = WorkspaceData.demo().studies
          .map(
            (s) => s.toJson()
              ..remove('nextReviewAt')
              ..remove('reviewTasks'),
          )
          .toList();
      final raw = jsonEncode(old),
          dir = await Directory.systemTemp.createTemp('xigu-v2-');
      addTearDown(() => dir.delete(recursive: true));
      final store = LocalWorkspaceStore(dir);
      await store.file.writeAsString(raw);
      final upgraded = (await store.load())!;
      expect(upgraded.studies.first.nextReviewAt, '');
      expect(upgraded.documents, isEmpty);
      expect(await File('${store.file.path}.v2.bak').readAsString(), raw);
      expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 3);
    },
  );
  test(
    'portable PDF pages and company identity reject tampered backup links',
    () {
      final data = workspace();
      final restored = WorkspaceData.decode(data.encode());
      expect(restored.sources.single.pageNumber, 2);
      expect(restored.documents.single.fileName, '../../report.pdf');
      for (final changed in [
        {'pageNumber': 1},
        {'studyId': 's1'},
        {'text': '伪造的财务原文'},
        {'unit': '元'},
        {'disclosedAt': '2026-04-01'},
      ]) {
        final bad = SourceExcerpt.fromJson({
          ...data.sources.single.toJson(),
          ...changed,
        });
        expect(
          () => WorkspaceData.decode(data.copyWith(sources: [bad]).encode()),
          throwsFormatException,
        );
      }
      expect(
        () => WorkspaceData.decode(
          data
              .copyWith(
                documents: [
                  document(),
                  ReportDocument.fromJson({...document().toJson(), 'id': 'd1'}),
                ],
              )
              .encode(),
        ),
        throwsFormatException,
      );
    },
  );
  test('PDF text chunking preserves surrogate pairs and page anchors', () {
    final text = '${'字' * 23999}😀末尾';
    final chunks = document(text: text).excerpts();
    expect(chunks.map((s) => s.text).join(), text);
    expect(chunks.first.text.length, 23999);
    expect(chunks.last.id, 'd0-p2-23999');
    expect(
      WorkspaceData.decode(
        workspace()
            .copyWith(
              documents: [document(text: text)],
              sources: chunks,
            )
            .encode(),
      ).sources.length,
      2,
    );
  });
  test('candidate numeric tokens reject partial, percentage, invented and wrong period values', () {
    final sources = document().excerpts();
    final good = FinancialCandidate.fromJson(candidateJson());
    expect(good.error(sources, '2025-01-01', '2025-12-31', '合并'), isNull);
    for (final fields in [
      {'rawValue': '00'},
      {'rawValue': '1'},
      {'sourceId': 'missing'},
      {'label': '不存在的指标'},
      {'quote': '营业收入为100.00万元但现金流已经改善'},
      {'unit': '元'},
      {'scope': '母公司'},
      {'end': '2025-06-30'},
    ]) {
      final c = FinancialCandidate.fromJson({...candidateJson(), ...fields});
      expect(c.error(sources, '2025-01-01', '2025-12-31', '合并'), isNotNull);
    }
    final percent = document(text: '营业收入同比增长100.00%，未给出金额。').excerpts();
    final c = FinancialCandidate.fromJson(
      candidateJson(quote: percent.single.text),
    );
    expect(c.error(percent, c.start, c.end, c.scope), isNotNull);
    for (final raw in ['1e5', '1,00', '20%', '1+2']) {
      expect(() => parseFinancialNumber(raw), throwsFormatException);
    }
    expect(parseFinancialNumber('(1,234.50)'), -1234.5);
    expect(parseFinancialNumber('−20.00'), -20);
    expect(parseFinancialNumber('负20.00'), -20);
  });
  test('confirmed candidates retain exact evidence, missing stays null and backup revalidates', () {
    final data = workspace();
    final revenue = FinancialCandidate.fromJson(candidateJson());
    final cashflow = FinancialCandidate.fromJson(
      candidateJson(raw: '负20.00', metric: 'operatingCash', label: '经营现金流'),
    );
    FinancialRecord confirm(
      List<FinancialCandidate> cs, {
      String studyId = 's0',
    }) => confirmFinancialCandidates(
      studyId: studyId,
      candidates: cs,
      sources: data.sources,
      start: '2025-01-01',
      end: '2025-12-31',
      scope: '合并',
      basis: '原披露',
    );
    final f = confirm([revenue, cashflow]);
    final restored = WorkspaceData.decode(
      data.copyWith(financials: [f]).encode(),
    ).financials.single;
    expect(restored.origin, 'aiConfirmed');
    expect(restored.operatingCash, -20);
    expect(restored.cash, isNull);
    expect(restored.evidence['revenue']!.rawValue, '100.00');
    expect(() => confirm([]), throwsFormatException);
    expect(() => confirm([revenue, revenue]), throwsFormatException);
    expect(() => confirm([revenue], studyId: 's1'), throwsFormatException);
    expect(
      () => FinancialRecord.fromJson({...f.toJson(), 'revenue': 101}),
      throwsFormatException,
    );
    expect(
      () => FinancialRecord.fromJson({...f.toJson(), 'evidence': {}}),
      throwsFormatException,
    );
    final wrongPeriod = FinancialRecord.fromJson({
      ...f.toJson(),
      'end': '2025-06-30',
    });
    expect(
      () => WorkspaceData.decode(
        data.copyWith(financials: [wrongPeriod]).encode(),
      ),
      throwsFormatException,
    );
  });
  test('financial prompt sends only selected text and rejects incomplete model response', () async {
    final transport = FakeTransport(
      (u, b) => {
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {
              'content': jsonEncode({
                'candidates': [candidateJson()],
                'missing': ['有息负债缺失'],
                'notes': [],
              }),
            },
          },
        ],
      },
    );
    final batch = await DeepSeekService(transport: transport).extractFinancials(
      key: 'sentinel',
      model: 'deepseek-flash',
      company: '虚构公司',
      sources: document().excerpts(),
      start: '2025-01-01',
      end: '2025-12-31',
      scope: '合并',
    );
    expect(batch.candidates.single.value, 100);
    expect(jsonEncode(transport.sent), isNot(contains('sentinel')));
    expect(jsonEncode(transport.sent), isNot(contains('holdings')));
    final tooLarge = List.generate(
      3,
      (_) => document(text: '字' * 24000).excerpts().single,
    );
    expect(
      () => DeepSeekService(transport: transport).extractFinancials(
        key: 'sentinel',
        model: 'm',
        company: 'c',
        sources: tooLarge,
        start: '2025-01-01',
        end: '2025-12-31',
        scope: '合并',
      ),
      throwsA(isA<ServiceFailure>()),
    );
    final incomplete = FakeTransport(
      (u, b) => {
        'choices': [
          {
            'finish_reason': 'length',
            'message': {'content': '{}'},
          },
        ],
      },
    );
    expect(
      () => DeepSeekService(transport: incomplete).extractFinancials(
        key: 'sentinel',
        model: 'm',
        company: 'c',
        sources: document().excerpts(),
        start: '2025-01-01',
        end: '2025-12-31',
        scope: '合并',
      ),
      throwsA(isA<ServiceFailure>()),
    );
  });
  test('year growth converts units and omits incomparable, missing, duplicate or zero bases', () {
    final current = record(2025, 1.2, unit: '亿元'),
        prior = record(2024, 100000000, unit: '元');
    expect(
      financialYearGrowth(current, 'revenue', [prior, current]),
      closeTo(.2, 1e-10),
    );
    for (final base in [
      record(2024, 0),
      record(2024, null),
      record(2024, 100, scope: '母公司'),
      record(2024, 100, basis: '重述'),
      record(2024, 100, studyId: 's1'),
      record(2023, 100),
      record(2024, 100, end: '2024-06-30'),
    ]) {
      expect(financialYearGrowth(current, 'revenue', [current, base]), isNull);
    }
    expect(
      financialYearGrowth(current, 'revenue', [prior, current, prior]),
      isNull,
    );
    final loss = record(2025, -5);
    expect(
      financialYearGrowth(loss, 'adjustedProfit', [record(2024, 10), loss]),
      isNull,
    );
    expect(
      financialYearGrowth(current, 'adjustedProfit', [
        record(2024, -10),
        current,
      ]),
      isNull,
    );
    final unknown = record(2025, 100, scope: '未注明');
    expect(
      financialYearGrowth(unknown, 'revenue', [
        unknown,
        record(2024, 80, scope: '未注明'),
      ]),
      isNull,
    );
  });
  test('review plan and previous study snapshots survive transfer and another edit', () {
    final data = workspace(), old = workspace().studies.first;
    final updated = old.copyWith(
      thesis: '新假设',
      nextReviewAt: '2026-11-01',
      reviewTasks: [
        ReviewTask(
          id: 't1',
          text: '验证现金流',
          sourceIds: [data.sources.single.id],
        ),
      ],
    );
    final next = WorkspaceData.decode(
      saveStudyVersion(data, updated, '更新复查计划').encode(),
    );
    expect(next.studyVersions.single.study.thesis, old.thesis);
    expect(next.studies.first.reviewTasks.single.status, '待验证');
    final second = WorkspaceData.decode(
      saveStudyVersion(
        next,
        next.studies.first.copyWith(
          reviewTasks: [
            ReviewTask(
              id: 't1',
              text: '验证现金流',
              status: '不成立',
              note: '原文经营现金流为负',
              sourceIds: [data.sources.single.id],
            ),
          ],
        ),
        '追加复查',
      ).encode(),
    );
    expect(second.studyVersions.length, 2);
    expect(second.studyVersions.last.study.reviewTasks.single.status, '待验证');
    expect(second.studies.first.reviewTasks.single.status, '不成立');
    expect(
      () => Study.fromJson({...updated.toJson(), 'nextReviewAt': '2026-02-30'}),
      throwsFormatException,
    );
    expect(
      () => ReviewTask.fromJson({
        'id': 't',
        'text': '条件',
        'status': '成立',
        'note': '',
        'sourceIds': [],
      }),
      throwsFormatException,
    );
    final wrong = old.copyWith(
      reviewTasks: [
        ReviewTask(id: 't', text: '条件', sourceIds: ['unknown']),
      ],
    );
    expect(
      () => WorkspaceData.decode(data.copyWith(studies: [wrong]).encode()),
      throwsFormatException,
    );
  });
}
