import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/financial_extraction.dart';
import 'package:lianghua_assistant/financial_verification.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/services.dart';

import 'support/v073_acceptance.dart';

class ReviewTransport implements JsonTransport {
  ReviewTransport(this.reviews);
  final List<Map<String, dynamic>> reviews;
  Map<String, dynamic>? payload;
  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    payload = jsonDecode(
      (body!['messages'] as List).last['content'] as String,
    ) as Map<String, dynamic>;
    return v073ModelResponse({'reviews': reviews});
  }
}

void main() {
  final data = v073Fixture(),
      sources = v073Fixture().documents.single.excerpts();
  final candidates = v073Candidates(sources)
      .map(FinancialCandidate.fromJson)
      .toList();
  final batch = FinancialCandidateBatch(candidates, [], []);
  final pass = FinancialReviewResult([
    for (var i = 0; i < 5; i++)
      FinancialReviewDecision(
        i,
        'pass',
        '本期依据',
        sources.first.id,
        sources.first.text,
      ),
  ], null);
  String? problem(FinancialCandidate c) => financialCandidateProblem(
    c,
    studyId: data.studies.single.id,
    sources: sources,
    documents: data.documents,
    start: '2025-01-01',
    end: '2025-12-31',
    scope: '合并',
  );

  test(
    'all five unique supported fields preselect, negative values remain',
    () {
      expect(defaultFinancialSelection(batch, pass, problem, sources), {
        0,
        1,
        2,
        3,
        4,
      });
      expect(candidates[1].value, -8);
      expect(candidates[2].value, -20);
    },
  );
  test('duplicates and semantic unknown never default in', () {
    final duplicate = FinancialCandidateBatch(
      [candidates.first, candidates.first],
      [],
      [],
    );
    final reviews = FinancialReviewResult([
      pass.decisions.first,
      const FinancialReviewDecision(1, 'pass', '本期依据', '', ''),
    ], null);
    expect(
      defaultFinancialSelection(duplicate, reviews, problem, sources),
      isEmpty,
    );
    final unknown = FinancialReviewResult([
      for (var i = 0; i < 5; i++)
        FinancialReviewDecision(i, 'unknown', '缺少表头', '', ''),
    ], null);
    expect(
      defaultFinancialSelection(batch, unknown, problem, sources),
      isEmpty,
    );
  });
  test('explicit source year and metric meaning are hard checks', () {
    final wrongYear = SourceExcerpt.fromJson({
      ...sources.first.toJson(),
      'documentId': null,
      'pageNumber': null,
      'url': 'https://example.com/report',
      'period': '2024年度',
    });
    expect(
      financialCandidateProblem(
        candidates.first,
        studyId: data.studies.single.id,
        sources: [wrongYear],
        documents: [],
        start: '2025-01-01',
        end: '2025-12-31',
        scope: '合并',
      ),
      contains('年度'),
    );
    final wrongMetric = FinancialCandidate.fromJson({
      ...candidates.first.toJson(),
      'metric': 'debt',
    });
    expect(
      wrongMetric.error(sources, '2025-01-01', '2025-12-31', '合并'),
      contains('指标名称'),
    );
  });
  test('input fingerprint binds range and basis', () {
    String fingerprint(String basis, List<SourceExcerpt> s) =>
        financialInputFingerprint(
          studyId: data.studies.single.id,
          sources: s,
          start: '2025-01-01',
          end: '2025-12-31',
          scope: '合并',
          basis: basis,
        );
    expect(fingerprint('原披露', sources), isNot(fingerprint('重述', sources)));
    expect(fingerprint('原披露', sources), isNot(fingerprint('原披露', [])));
  });
  test('same-page unrelated review proof downgrades to unknown', () async {
    final transport = ReviewTransport([
      {
        'index': 0,
        'verdict': 'pass',
        'reason': '声称正确',
        'sourceId': sources.first.id,
        'quote': '虚构制造 600001 2025年度合并财务报表',
      },
    ]);
    final result = await DeepSeekService(transport: transport).reviewFinancials(
      key: v073Sentinel,
      model: 'offline-model',
      company: '虚构制造',
      sources: sources,
      batch: FinancialCandidateBatch([candidates.first], [], []),
      start: '2025-01-01',
      end: '2025-12-31',
      scope: '合并',
    );
    expect(result.decisions.single.verdict, 'unknown');
    expect(result.decisions.single.quote, isEmpty);
    expect(transport.payload!.containsKey('notes'), isFalse);
    expect(transport.payload!.containsKey('confidence'), isFalse);
  });
  test('incomplete/duplicate review output cannot become pass', () async {
    final transport = ReviewTransport([]);
    expect(
      DeepSeekService(transport: transport).reviewFinancials(
        key: v073Sentinel,
        model: 'offline-model',
        company: '虚构制造',
        sources: sources,
        batch: batch,
        start: '2025-01-01',
        end: '2025-12-31',
        scope: '合并',
      ),
      throwsA(isA<ServiceFailure>()),
    );
  });
}
