import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/reports.dart';

import 'v03_test.dart' show document;

Map<String, dynamic> provenance({
  String id = '1212345678',
  bool revision = false,
}) => {
  'announcementId': id,
  'code': '600001',
  'exchange': 'SH',
  'companyName': '虚构测试公司',
  'title': revision ? '2025年年度报告（修订版）' : '2025年年度报告',
  'downloadUrl': 'https://static.cninfo.com.cn/finalpage/2026-03-31/$id.PDF',
  'catalogueUrl': 'https://www.cninfo.com.cn/new/hisAnnouncement/query',
  'start': '2025-01-01',
  'end': '2025-12-31',
  'disclosedAt': '2026-03-31',
  'fetchedAt': '2026-10-03T10:00:00+08:00',
  'isRevision': revision,
};

ReportDocument imported({
  String id = 'd1',
  String hash = 'b',
  String announcement = '1212345678',
  bool revision = false,
}) {
  final origin = provenance(id: announcement, revision: revision);
  return ReportDocument.fromJson({
    ...document().toJson(),
    'id': id,
    'sha256': hash * 64,
    'url': origin['downloadUrl'],
    'origin': origin,
  });
}

WorkspaceData withReports(List<ReportDocument> reports) {
  final study = {
    ...WorkspaceData.demo().studies.first.toJson(),
    'code': '600001',
  };
  final raw = WorkspaceData.empty().toJson()
    ..['studies'] = [study]
    ..['documents'] = reports.map((d) => d.toJson()).toList()
    ..['sources'] = reports
        .expand((d) => d.excerpts())
        .map((s) => s.toJson())
        .toList();
  return WorkspaceData.decode(jsonEncode(raw));
}

void main() {
  test(
    'origin code must belong to its exchange without affecting manual PDFs',
    () {
      for (final identity in [
        ('SH', '000001'),
        ('SZ', '600001'),
        ('BJ', '300001'),
        ('SH', '60001'),
      ]) {
        expect(
          () => ReportOrigin.fromJson({
            ...provenance(),
            'exchange': identity.$1,
            'code': identity.$2,
          }),
          throwsFormatException,
        );
      }
      for (final identity in [
        ('SH', '600001'),
        ('SZ', '300001'),
        ('BJ', '920001'),
      ]) {
        expect(
          ReportOrigin.fromJson({
            ...provenance(),
            'exchange': identity.$1,
            'code': identity.$2,
          }).code,
          identity.$2,
        );
      }
      expect(ReportDocument.fromJson(document().toJson()).origin, isNull);
    },
  );
  test('schema 3 retains catalogue provenance and independent revisions', () {
    final first = imported(),
        second = imported(
          id: 'd2',
          hash: 'c',
          announcement: '1212345679',
          revision: true,
        );
    final data = withReports([first, second]);
    final restored = WorkspaceData.decode(data.encode());
    expect(restored.documents.first.origin!.toJson(), provenance());
    expect(restored.documents.last.origin!.isRevision, isTrue);
    expect(restored.documents.first.sha256, 'b' * 64);
    expect(restored.documents.last.sha256, 'c' * 64);
    expect(ReportDocument.fromJson(document().toJson()).origin, isNull);
  });
  test('same announcement with different bytes cannot enter a study twice', () {
    expect(
      () => withReports([imported(), imported(id: 'd2', hash: 'c')]),
      throwsFormatException,
    );
  });
  test('backup cannot move an announcement to a different security', () {
    final data = withReports([imported()]).toJson();
    ((data['documents'] as List).first['origin'] as Map)['code'] = '000001';
    expect(() => WorkspaceData.decode(jsonEncode(data)), throwsFormatException);
  });
  test('invalid catalogue source and tampered download link are rejected', () {
    for (final bad in [
      {
        ...provenance(),
        'downloadUrl': 'https://static.cninfo.com.cn.evil.test/report.pdf',
      },
      {...provenance(), 'catalogueUrl': 'https://www.cninfo.com.cn:8443/query'},
      {
        ...provenance(),
        'downloadUrl': 'https://user@static.cninfo.com.cn/report.pdf',
      },
      {...provenance(), 'isRevision': 'false'},
      {...provenance(), 'disclosedAt': '2025-12-01'},
    ]) {
      expect(() => ReportOrigin.fromJson(bad), throwsFormatException);
    }
    final raw = imported().toJson()
      ..['url'] = 'https://static.cninfo.com.cn/other.pdf';
    expect(() => ReportDocument.fromJson(raw), throwsFormatException);
  });
}
