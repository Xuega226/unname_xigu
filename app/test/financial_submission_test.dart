import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/financial_verification.dart';
import 'package:lianghua_assistant/research.dart';

import 'financial_audit_test.dart' show auditJson, recordJson;

Map<String, dynamic> mutableJson(Map<String, dynamic> input) =>
    jsonDecode(jsonEncode(input)) as Map<String, dynamic>;

Map<String, dynamic> reorderObjects(Map<String, dynamic> input) {
  dynamic reverse(dynamic value) {
    if (value is Map<String, dynamic>) {
      return {
        for (final key in value.keys.toList().reversed)
          key: reverse(value[key]),
      };
    }
    if (value is List) return value.map(reverse).toList();
    return value;
  }

  return reverse(input) as Map<String, dynamic>;
}

void main() {
  test(
    'same evidence ignores adoption time, actual usage and object key order',
    () {
      final first = FinancialRecord.fromJson(recordJson());
      final changed = recordJson()..['id'] = 'another-submission';
      changed['audit']['acceptedAt'] = '2026-10-06T10:00:00Z';
      changed['audit']['usage'] = [
        {'stage': 'extraction', 'unknown': true},
        {'stage': 'review', 'total_tokens': 300},
      ];
      final second = FinancialRecord.fromJson(reorderObjects(changed));
      expect(sameFinancialSubmission(first, second), isTrue);
      expect(sameFinancialSubmission(second, first), isTrue);
    },
  );
  test(
    'reordered candidates preserve selection, reviews and manual overrides',
    () {
      final first = mutableJson(recordJson());
      first['audit']['reviews'][1]['verdict'] = 'unknown';
      first['audit']['overrides'] = [
        {'index': 1, 'reason': '人工核对本期现金流'},
      ];
      first['audit']['candidates'][0]['extension'] = {'b': 2, 'a': 1};
      final second = recordJson();
      second['audit'] = reorderObjects(first['audit'] as Map<String, dynamic>);
      final audit = second['audit'];
      audit['candidates'] = (audit['candidates'] as List).reversed.toList();
      audit['reviews'] = [
        for (final item in (audit['reviews'] as List).reversed)
          {
            ...item as Map<String, dynamic>,
            'index': 1 - (item['index'] as int),
          },
      ];
      audit['selected'] = [1, 0];
      audit['overrides'] = [
        {'index': 0, 'reason': '人工核对本期现金流'},
      ];
      expect(
        sameFinancialSubmission(
          FinancialRecord.fromJson(first),
          FinancialRecord.fromJson(second),
        ),
        isTrue,
      );
    },
  );
  test('changed proof, selected set, model, versions and extensions remain distinct', () {
    final original = FinancialRecord.fromJson(recordJson());
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) => j['audit']['model'] = 'another-model',
      (j) => j['audit']['extractionVersion'] = '2',
      (j) => j['audit']['reviewVersion'] = '2',
      (j) => j['audit']['checkVersion'] = '2',
      (j) => j['audit']['fingerprint'] = List.filled(64, 'b').join(),
      (j) => j['audit']['extension'] = {'retained': true},
      (j) => j['audit']['candidates'][0]['extension'] = 'retained',
      (j) => j['audit']['reviews'][0]['extension'] = 'retained',
      (j) => j['audit']['reviews'][0]['reason'] = '不同核验依据',
      (j) {
        j['audit']['candidates'][0]['quote'] = '2025年度合并报表：营业收入为100万元';
        j['evidence']['revenue']['quote'] = '2025年度合并报表：营业收入为100万元';
      },
      (j) {
        j['audit']['reviews'][0]['quote'] = '2025年度合并报表：营业收入为100万元';
      },
      (j) {
        j.remove('operatingCash');
        j['evidence'].remove('operatingCash');
        j['audit']['selected'] = [0];
      },
      (j) => j.remove('audit'),
    ]) {
      final json = recordJson();
      mutate(json);
      expect(
        sameFinancialSubmission(original, FinancialRecord.fromJson(json)),
        isFalse,
      );
    }
  });
  test('manual records normalize evidence object order and retain amounts', () {
    final manual = recordJson()
      ..remove('audit')
      ..['origin'] = 'manual';
    final original = FinancialRecord.fromJson(manual);
    expect(
      sameFinancialSubmission(
        original,
        FinancialRecord.fromJson(reorderObjects(manual)),
      ),
      isTrue,
    );
    final changed = {...manual, 'debt': 0};
    expect(
      sameFinancialSubmission(original, FinancialRecord.fromJson(changed)),
      isFalse,
    );
  });
  test(
    'same duplicate candidate multiset retains reviews assigned to each proof',
    () {
      final original = recordJson();
      final audit = mutableJson(auditJson());
      audit['candidates'].add({
        ...audit['candidates'][0] as Map<String, dynamic>,
      });
      audit['reviews'].add({
        'index': 2,
        'verdict': 'unknown',
        'reason': '同指标的另一候选需排除',
        'sourceId': '',
        'quote': '',
      });
      original['audit'] = audit;
      final changed = reorderObjects(original);
      changed['audit']['reviews'][2]['reason'] = '不同排除理由';
      expect(
        sameFinancialSubmission(
          FinancialRecord.fromJson(original),
          FinancialRecord.fromJson(changed),
        ),
        isFalse,
      );
    },
  );
}
