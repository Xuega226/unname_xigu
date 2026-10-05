// Generate only fictional schema-3 upgrade data. Never reads the user store.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/reports.dart';

Future<void> main() async {
  final bytes = await File('integration_test/fixtures/fictional-report.pdf')
      .readAsBytes();
  final document = ReportDocument(
    id: 'upgrade-document',
    studyId: 's0',
    fileName: 'fictional-report.pdf',
    sha256: sha256.convert(bytes).toString(),
    title: '虚构升级验收财报',
    url: '',
    period: '2025年度',
    start: '2025-01-01',
    end: '2025-12-31',
    disclosedAt: '2026-03-31',
    unit: '万元',
    importedAt: '2026-10-01T00:00:00Z',
    pageCount: 2,
    pages: [const ReportPage(number: 1, text: '虚构升级测试原文，营业收入100.00万元。')],
  );
  final demo = WorkspaceData.demo();
  final studies = [...demo.studies];
  studies[0] = studies[0].copyWith(
    thesis: 'Round4_upgrade_preserve_v03',
    nextReviewAt: '2026-11-01',
  );
  final data = demo.copyWith(
    cash: 2345,
    studies: studies,
    documents: [document],
    sources: document.excerpts(),
  );
  WorkspaceData.decode(data.encode());
  await File('../.tools/v0.4-upgrade-fixture.json')
      .writeAsString(data.encode());
}
