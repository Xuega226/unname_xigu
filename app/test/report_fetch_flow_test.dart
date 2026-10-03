import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/report_fetch.dart';
import 'package:lianghua_assistant/report_fetch_widgets.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/report_widgets.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/services.dart';

const study = Study(
  id: 's0',
  code: '600660',
  name: '虚构研究公司',
  business: '',
  thesis: '',
  counterEvidence: '',
  reviewCondition: '',
  source: '',
  updatedAt: '2026-10-03',
);

ReportAnnouncement announcement(String id, int year, {bool revised = false}) =>
    ReportAnnouncement(
      id: id,
      code: study.code,
      exchange: 'SH',
      companyName: '来源测试公司',
      title: '$year 年年度报告${revised ? '（修订版）' : ''}',
      url: Uri.parse(
        'https://static.cninfo.com.cn/finalpage/2026-03-31/$id.PDF',
      ),
      start: DateTime(year, 1, 1),
      end: DateTime(year, 12, 31),
      disclosedAt: DateTime(year + 1, 3, 31),
      isRevision: revised,
      year: year,
    );

class FakeReports extends ReportFetchService {
  FakeReports(this.items);
  final List<ReportAnnouncement> items;
  int searchCalls = 0;
  final downloads = <String>[];
  bool failSearch = false;
  final failDownloads = <String>{};
  Completer<ReportSearchResult>? pendingSearch;
  Completer<Uint8List>? pendingDownload;
  String? pendingId;
  ReportSearchResult get result => ReportSearchResult(
    companyName: '来源测试公司',
    code: study.code,
    exchange: 'SH',
    reports: items,
    missingYears: const [2023],
    warnings: const ['查询页数受限，结果可能不完整'],
  );
  @override
  Future<ReportSearchResult> search(
    String exchange,
    String code, {
    int years = 3,
  }) async {
    searchCalls++;
    if (failSearch) throw ServiceFailure('测试查询失败');
    return pendingSearch == null ? result : pendingSearch!.future;
  }

  @override
  Future<Uint8List> download(
    ReportAnnouncement item, {
    void Function(int received, int? total)? progress,
  }) async {
    downloads.add(item.id);
    if (failDownloads.contains(item.id)) throw ServiceFailure('测试下载失败');
    if (pendingDownload != null && item.id == pendingId) {
      return pendingDownload!.future;
    }
    progress?.call(1, 2);
    return Uint8List.fromList([item.id == 'a' ? 1 : 2]);
  }
}

class FakePdf extends PdfImportService {
  @override
  Future<ParsedReport> parse(
    Uint8List bytes,
    String fileName, {
    void Function(int done, int total)? progress,
  }) async => ParsedReport(
    fileName: fileName,
    bytes: bytes,
    hash: (bytes.first == 1 ? 'a' : 'b') * 64,
    pages: const [ReportPage(number: 1, text: '虚构公司合并报表，营业收入 100.00 万元。')],
  );
}

ReportDocument existing({ReportOrigin? origin, String hash = 'a'}) =>
    ReportDocument(
      id: 'existing',
      studyId: study.id,
      fileName: 'existing.pdf',
      sha256: hash * 64,
      title: '已导入报告',
      url: origin?.downloadUrl ?? '',
      period: '2025 年度',
      start: '2025-01-01',
      end: '2025-12-31',
      disclosedAt: '2026-03-31',
      unit: '万元',
      importedAt: '2026-10-01',
      pageCount: 1,
      pages: const [ReportPage(number: 1, text: '原有资料')],
      origin: origin,
    );

ReportOrigin origin(ReportAnnouncement item) => ReportOrigin(
  announcementId: item.id,
  code: item.code,
  exchange: item.exchange,
  companyName: item.companyName,
  title: item.title,
  downloadUrl: item.url.toString(),
  catalogueUrl: item.sourceUrl,
  start: '${item.year}-01-01',
  end: '${item.year}-12-31',
  disclosedAt: '${item.year + 1}-03-31',
  fetchedAt: '2026-10-03T00:00:00Z',
  isRevision: item.isRevision,
);

Future<void> tap(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> open(
  WidgetTester tester,
  FakeReports service, {
  List<ReportDocument> existingDocuments = const [],
  Future<bool> Function(ReportDocument, Uint8List)? save,
  void Function(List<ReportDocument>?)? returned,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final docs = await showDialog<List<ReportDocument>>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ReportFetchDialog(
                  study: study,
                  exchange: 'SH',
                  service: service,
                  importer: FakePdf(),
                  existingDocuments: existingDocuments,
                  save: save ?? (_, _) async => true,
                ),
              );
              returned?.call(docs);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, find.text('open'));
}

Future<void> select(WidgetTester tester, String id) =>
    tap(tester, find.byKey(ValueKey('select-report-$id')));

Future<void> confirmPdf(WidgetTester tester, {bool settle = true}) async {
  expect(find.byType(ReportImportDialog), findsOneWidget);
  final save = find.widgetWithText(FilledButton, '保存选页与原文件');
  expect(tester.widget<FilledButton>(save).onPressed, isNull);
  await tap(tester, find.byType(DropdownButtonFormField<String>));
  await tap(tester, find.text('万元').last);
  await tap(
    tester,
    find
        .descendant(
          of: find.byType(ReportImportDialog),
          matching: find.byType(Checkbox),
        )
        .first,
  );
  expect(tester.widget<FilledButton>(save).onPressed, isNull);
  await tap(tester, find.byType(CheckboxListTile));
  await tap(tester, save, settle: settle);
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
    testWidgets('query failure, provenance, revisions and warnings at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = FakeReports([
        announcement('a', 2025),
        announcement('b', 2025, revised: true),
      ])..failSearch = true;
      await open(tester, source);
      await tap(tester, find.text('查询近三年年报'));
      expect(find.text('测试查询失败'), findsOneWidget);
      source.failSearch = false;
      await tap(tester, find.text('查询近三年年报'));
      expect(find.textContaining('来源公司：来源测试公司'), findsOneWidget);
      expect(find.textContaining('缺少年度：2023'), findsOneWidget);
      expect(find.textContaining('结果可能不完整'), findsOneWidget);
      for (final checkbox in tester.widgetList<Checkbox>(
        find.byType(Checkbox),
      )) {
        expect(checkbox.value, false);
      }
      await select(tester, 'b');
      expect(find.text('已选 1 份 · 已保存 0 份'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'partial success, retry cancellation and late download preserve saved result',
    (tester) async {
      final source = FakeReports([
        announcement('a', 2025),
        announcement('b', 2024),
      ])..failDownloads.add('b');
      final stored = <ReportDocument>[];
      List<ReportDocument>? returned;
      await open(
        tester,
        source,
        save: (d, _) async {
          stored.add(d);
          return true;
        },
        returned: (value) => returned = value,
      );
      await tap(tester, find.text('查询近三年年报'));
      await select(tester, 'a');
      await select(tester, 'b');
      await tap(tester, find.text('下载并逐份核对'));
      expect(stored, isEmpty);
      await confirmPdf(tester);
      expect(stored.length, 1);
      expect(stored.single.origin!.announcementId, 'a');
      expect(stored.single.unit, '万元');
      expect(find.text('失败：测试下载失败'), findsOneWidget);
      source.failDownloads.clear();
      source.pendingId = 'b';
      source.pendingDownload = Completer<Uint8List>();
      await tap(
        tester,
        find.byKey(const ValueKey('retry-report-b')),
        settle: false,
      );
      await tap(tester, find.text('停止当前操作'));
      await tap(tester, find.text('完成（已保存 1 份）'));
      expect(returned!.length, 1);
      source.pendingDownload!.complete(Uint8List.fromList([2]));
      await tester.pumpAndSettle();
      expect(stored.length, 1);
      expect(find.byType(ReportImportDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'announcement identity and file hash duplicates never overwrite old reports',
    (tester) async {
      final a = announcement('a', 2025), b = announcement('b', 2024);
      final source = FakeReports([a, b]);
      var writes = 0;
      await open(
        tester,
        source,
        existingDocuments: [
          existing(origin: origin(a)),
          existing(hash: 'b'),
        ],
        save: (_, _) async {
          writes++;
          return true;
        },
      );
      await tap(tester, find.text('查询近三年年报'));
      expect(
        tester
            .widget<Checkbox>(find.byKey(const ValueKey('select-report-a')))
            .onChanged,
        isNull,
      );
      await select(tester, 'b');
      await tap(tester, find.text('下载并逐份核对'));
      expect(find.text('原文件相同，已跳过'), findsOneWidget);
      expect(find.byType(ReportImportDialog), findsNothing);
      expect(writes, 0);
      expect(source.downloads, ['b']);
    },
  );

  testWidgets(
    'cancelled confirmation stops the queue and back returns previous successful saves',
    (tester) async {
      final source = FakeReports([
        announcement('a', 2025),
        announcement('b', 2024),
      ]);
      List<ReportDocument>? returned;
      await open(tester, source, returned: (docs) => returned = docs);
      await tap(tester, find.text('查询近三年年报'));
      await select(tester, 'a');
      await select(tester, 'b');
      await tap(tester, find.text('下载并逐份核对'));
      await confirmPdf(tester);
      expect(find.byType(ReportImportDialog), findsOneWidget);
      await tap(tester, find.text('取消'));
      expect(find.textContaining('已停止余下队列'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(returned!.single.origin!.announcementId, 'a');
    },
  );

  testWidgets(
    'closing a pending query ignores late results and returns empty saves',
    (tester) async {
      final source = FakeReports([announcement('a', 2025)])
        ..pendingSearch = Completer<ReportSearchResult>();
      List<ReportDocument>? returned;
      await open(tester, source, returned: (docs) => returned = docs);
      await tap(tester, find.text('查询近三年年报'), settle: false);
      await tap(tester, find.text('关闭'));
      expect(returned, isEmpty);
      source.pendingSearch!.complete(source.result);
      await tester.pumpAndSettle();
      expect(find.byType(ReportFetchDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'query rejects another company before exposing download choices',
    (tester) async {
      final source = FakeReports([announcement('a', 2025)])
        ..pendingSearch = Completer<ReportSearchResult>();
      await open(tester, source);
      await tap(tester, find.text('查询近三年年报'), settle: false);
      source.pendingSearch!.complete(
        ReportSearchResult(
          companyName: '另一家公司',
          code: '000001',
          exchange: 'SZ',
          reports: const [],
          missingYears: const [],
          warnings: const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('与当前研究卡代码不一致'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
    },
  );

  testWidgets(
    'a failed save keeps the reviewed PDF available without recording a success',
    (tester) async {
      final source = FakeReports([announcement('a', 2025)]);
      var attempts = 0;
      List<ReportDocument>? returned;
      await open(
        tester,
        source,
        save: (_, _) async => ++attempts > 1,
        returned: (docs) => returned = docs,
      );
      await tap(tester, find.text('查询近三年年报'));
      await select(tester, 'a');
      await tap(tester, find.text('下载并逐份核对'));
      await confirmPdf(tester);
      expect(find.text('保存失败，财报未加入工作区'), findsOneWidget);
      expect(find.byType(ReportImportDialog), findsOneWidget);
      expect(attempts, 1);
      await tap(tester, find.text('保存选页与原文件'));
      expect(find.byType(ReportImportDialog), findsNothing);
      await tap(tester, find.text('完成（已保存 1 份）'));
      expect(attempts, 2);
      expect(returned!.length, 1);
    },
  );

  testWidgets(
    'system back during a pending write cannot dismiss or duplicate the save',
    (tester) async {
      final source = FakeReports([announcement('a', 2025)]);
      final pending = Completer<bool>();
      var writes = 0;
      List<ReportDocument>? returned;
      await open(
        tester,
        source,
        save: (_, _) {
          writes++;
          return pending.future;
        },
        returned: (docs) => returned = docs,
      );
      await tap(tester, find.text('查询近三年年报'));
      await select(tester, 'a');
      await tap(tester, find.text('下载并逐份核对'));
      await confirmPdf(tester, settle: false);
      expect(writes, 1);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ReportImportDialog), findsOneWidget);
      expect(returned, isNull);
      final save = find.widgetWithText(FilledButton, '保存选页与原文件');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(save);
      await tester.pump();
      expect(writes, 1);
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(ReportImportDialog), findsNothing);
      await tap(tester, find.text('完成（已保存 1 份）'));
      expect(returned!.single.origin!.announcementId, 'a');
      expect(writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicitly selected original and revision both preserve separate provenance',
    (tester) async {
      final source = FakeReports([
        announcement('a', 2025),
        announcement('b', 2025, revised: true),
      ]);
      final stored = <ReportDocument>[];
      await open(
        tester,
        source,
        save: (d, _) async {
          stored.add(d);
          return true;
        },
      );
      await tap(tester, find.text('查询近三年年报'));
      await select(tester, 'a');
      await select(tester, 'b');
      await tap(tester, find.text('下载并逐份核对'));
      await confirmPdf(tester);
      await confirmPdf(tester);
      expect(stored.length, 2);
      expect(stored.map((d) => d.origin!.isRevision), [false, true]);
      expect(stored.map((d) => d.origin!.announcementId), ['a', 'b']);
      expect(stored[0].sha256, isNot(stored[1].sha256));
      expect(stored.map((d) => d.start), ['2025-01-01', '2025-01-01']);
    },
  );

  testWidgets(
    'a stopped query cannot overwrite results from a subsequent query',
    (tester) async {
      final stale = Completer<ReportSearchResult>();
      final source = FakeReports([announcement('a', 2025)])
        ..pendingSearch = stale;
      await open(tester, source);
      await tap(tester, find.text('查询近三年年报'), settle: false);
      await tap(tester, find.text('停止当前操作'));
      source.pendingSearch = null;
      await tap(tester, find.text('查询近三年年报'));
      stale.complete(
        ReportSearchResult(
          companyName: '迟到的旧目录',
          code: study.code,
          exchange: 'SH',
          reports: const [],
          missingYears: const [],
          warnings: const [],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('来源公司：来源测试公司'), findsOneWidget);
      expect(find.textContaining('迟到的旧目录'), findsNothing);
      expect(source.searchCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
