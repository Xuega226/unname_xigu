import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/report_preparation.dart';
import 'package:lianghua_assistant/reports.dart';

import 'support/v07_fixture.dart';

const selectedPages = [
  ReportPage(number: 1, text: '2025年度 合并利润表 单位：万元 营业收入为100万元'),
  ReportPage(number: 2, text: '2025年度 合并资产负债表 单位：元 有息负债为100000元'),
  ReportPage(number: 3, text: '2025年度 附注及说明 没有金额单位的段落'),
];
const origin = ReportOrigin(
  announcementId: 'prepared-fixture',
  code: '600001',
  exchange: 'SH',
  companyName: '虚构制造',
  title: '虚构2025年报',
  downloadUrl:
      'https://static.cninfo.com.cn/finalpage/2026-04-01/prepared-fixture.pdf',
  catalogueUrl: 'https://www.cninfo.com.cn/new/hisAnnouncement/query',
  start: '2025-01-01',
  end: '2025-12-31',
  disclosedAt: '2026-04-01',
  fetchedAt: '2026-10-05T00:00:00Z',
  isRevision: false,
);
ReportDocument document({
  String id = 'old-report',
  String? preparedFrom,
  bool prepared = false,
}) {
  final base = ReportDocument(
    id: id,
    studyId: 'v07-study',
    fileName: 'fictional.pdf',
    sha256: 'b' * 64,
    title: '虚构2025年报',
    url: '',
    period: '2025年度',
    start: '2025-01-01',
    end: '2025-12-31',
    disclosedAt: '2026-04-01',
    unit: '万元',
    importedAt: '2026-10-05T00:00:00Z',
    pageCount: 3,
    pages: selectedPages,
  );
  return ReportDocument.fromJson({
    ...base.toJson(),
    if (preparedFrom != null) 'preparedFrom': preparedFrom,
    if (prepared)
      'preparation': locateReportPages('虚构制造 600001', selectedPages).toJson(),
  });
}

WorkspaceData workspace(List<ReportDocument> documents) {
  final initial = v07Fixture();
  return initial.copyWith(
    documents: documents,
    sources: [
      ...initial.sources,
      for (final document in documents) ...document.excerpts(),
    ],
  );
}

void main() {
  test(
    'prepared per-page units roundtrip and cannot be replaced by document unit',
    () {
      final prepared = document(prepared: true);
      expect(prepared.excerpts().map((s) => s.unit), ['万元', '元', '不适用']);
      final data = workspace([prepared]);
      expect(WorkspaceData.decode(data.encode()).encode(), data.encode());
      for (final unit in ['万元', '亿元']) {
        final map = data.toJson();
        final source = (map['sources'] as List).firstWhere(
          (s) => s['documentId'] == prepared.id && s['pageNumber'] == 2,
        );
        source['unit'] = unit;
        expect(
          () => WorkspaceData.decode(jsonEncode(map)),
          throwsFormatException,
        );
      }
    },
  );
  test('same-file explicit preparation versions retain old sources and corrected metadata', () {
    final original = document();
    final prepared = ReportDocument.fromJson({
      ...document(
        id: 'prepared-report',
        preparedFrom: original.id,
        prepared: true,
      ).toJson(),
      'title': '人工补正报告标题',
      'unit': '不适用',
    });
    final data = workspace([original, prepared]);
    final reopened = WorkspaceData.decode(data.encode());
    expect(reopened.encode(), data.encode());
    expect(reopened.documents.last.preparedFrom, original.id);
    expect(
      reopened.sources
          .where((s) => s.documentId == original.id)
          .map((s) => s.toJson()),
      original.excerpts().map((s) => s.toJson()),
    );
  });
  test('unknown, self, cyclic, reordered and cross-file preparation links rejected', () {
    final original = document();
    final child = document(
      id: 'prepared-report',
      preparedFrom: original.id,
      prepared: true,
    );
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) => j['documents'][1]['preparedFrom'] = 'missing',
      (j) => j['documents'][1]['preparedFrom'] = 'prepared-report',
      (j) => j['documents'][0]['preparedFrom'] = 'prepared-report',
      (j) => j['documents'] = (j['documents'] as List).reversed.toList(),
      (j) => j['documents'][1]['sha256'] = 'c' * 64,
      (j) => j['documents'][1]['pageCount'] = 4,
      (j) => j['documents'][1]['studyId'] = 'missing-study',
      (j) => j['documents'][1].remove('preparedFrom'),
    ]) {
      final map = workspace([original, child]).toJson();
      mutate(map);
      expect(
        () => WorkspaceData.decode(jsonEncode(map)),
        throwsFormatException,
      );
    }
  });
  test('prepared announcement versions keep exact original provenance', () {
    final original = ReportDocument.fromJson({
      ...document().toJson(),
      'origin': origin.toJson(),
      'url': origin.downloadUrl,
    });
    final child = ReportDocument.fromJson({
      ...document(
        id: 'new-report',
        preparedFrom: original.id,
        prepared: true,
      ).toJson(),
      'origin': origin.toJson(),
      'url': origin.downloadUrl,
    });
    final valid = workspace([original, child]);
    expect(WorkspaceData.decode(valid.encode()).encode(), valid.encode());
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) =>
          j['documents'][1]['origin']['announcementId'] = 'other-announcement',
      (j) => j['documents'][1]['origin']['fetchedAt'] = '2026-10-06T00:00:00Z',
      (j) => j['documents'][1]['origin']['isRevision'] = true,
      (j) => j['documents'][1].remove('origin'),
    ]) {
      final map = valid.toJson();
      mutate(map);
      expect(
        () => WorkspaceData.decode(jsonEncode(map)),
        throwsFormatException,
      );
    }
  });
  test('original ordinary duplicate stays rejected and schema7 cannot carry preparation metadata', () {
    expect(
      () => WorkspaceData.decode(
        workspace([document(), document(id: 'duplicate')]).encode(),
      ),
      throwsFormatException,
    );
    for (final docs in [
      [document(prepared: true)],
      [document(), document(id: 'new', preparedFrom: 'old-report')],
    ]) {
      final map = workspace(docs).toJson()..['schemaVersion'] = 7;
      expect(
        () => WorkspaceData.decode(jsonEncode(map)),
        throwsFormatException,
      );
    }
  });
}
