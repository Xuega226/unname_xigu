// Uses only a bundled fictional PDF, memory stores and fake public responses.
// Run this unchanged on Windows and an Android emulator; no user credentials.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/report_fetch.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/report_widgets.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

import '../test/research_test.dart' show FakeTransport;
import '../test/third_round_flow_test.dart' show tapVisible;
import '../test/v03_test.dart' show candidateJson;

class FixtureReportTransport implements ReportFetchTransport {
  FixtureReportTransport(this.pdf);
  final Uint8List pdf;
  int downloads = 0;
  final requests = <Uri>[];

  @override
  Future<ReportFetchResponse> request(
    Uri uri, {
    Map<String, String>? form,
  }) async {
    validateReportUri(uri);
    requests.add(uri);
    if (form == null) {
      downloads++;
      expect(
        uri.toString(),
        'https://static.cninfo.com.cn/finalpage/2026-03-31/123456.pdf',
      );
      if (downloads == 1) {
        return const ReportFetchResponse(503, Stream<List<int>>.empty());
      }
      return ReportFetchResponse(
        200,
        Stream.value(pdf),
        contentLength: pdf.length,
        contentType: 'application/pdf',
      );
    }
    final Object response;
    if (uri.path.endsWith('/topSearch/query')) {
      expect(form['keyWord'], '600001');
      response = [
        {
          'code': '600001',
          'category': 'A股',
          'orgId': 'gssh600001',
          'zwjc': '虚构测试公司',
        },
      ];
    } else {
      expect(uri.path, '/new/hisAnnouncement/query');
      expect(form['stock'], '600001,gssh600001');
      expect(form['column'], 'sse');
      response = {
        'announcements': [
          {
            'secCode': '600001',
            'orgId': 'gssh600001',
            'announcementId': '123456',
            'announcementTitle': '2025年年度报告（修订版）',
            'announcementTime': DateTime.utc(
              2026,
              3,
              31,
            ).millisecondsSinceEpoch,
            'adjunctUrl': 'finalpage/2026-03-31/123456.pdf',
            'adjunctType': 'PDF',
          },
        ],
        'totalAnnouncement': 1,
        'hasMore': false,
      };
    }
    final bytes = utf8.encode(jsonEncode(response));
    return ReportFetchResponse(
      200,
      Stream.value(bytes),
      contentLength: bytes.length,
      contentType: 'application/json',
    );
  }
}

WorkspaceData fictionalResearch() {
  final old = WorkspaceData.demo().studies.first;
  return WorkspaceData.empty().copyWith(
    studies: [
      Study.fromJson({...old.toJson(), 'code': '600001', 'name': '虚构测试公司'}),
    ],
    watchlist: [
      const WatchCompany(
        id: 'fictional-company',
        code: '600001',
        exchange: 'SH',
        name: '虚构测试公司',
        industry: '制造',
        source: 'https://www.cninfo.com.cn/',
        fetchedAt: '2026-10-03T00:00:00Z',
      ),
    ],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native automatic report flow: retry, cancel, human review, AI and backup',
    (tester) async {
      final bytes = (await rootBundle.load(
        'integration_test/fixtures/fictional-report.pdf',
      )).buffer.asUint8List();
      final importer = PdfImportService();
      final png = await importer.renderPage(bytes, 1);
      expect(png.take(4), [137, 80, 78, 71]);
      final transport = FixtureReportTransport(bytes);
      final fetcher = ReportFetchService(
        transport: transport,
        clock: () => DateTime(2026, 10, 3),
      );
      final store = MemoryWorkspaceStore(fictionalResearch());
      final files = MemoryReportFileStore();
      final ai = DeepSeekService(
        transport: FakeTransport((uri, body) {
          final sources =
              jsonDecode(
                    (body!['messages'] as List).last['content'] as String,
                  )['sources']
                  as List;
          final source = sources.single as Map;
          return {
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': jsonEncode({
                    'candidates': [
                      {
                        ...candidateJson(),
                        'sourceId': source['id'],
                        'quote': source['text'],
                        'unit': source['unit'],
                      },
                    ],
                    'missing': [],
                    'notes': [],
                  }),
                },
              },
            ],
          };
        }),
      );
      await tester.pumpWidget(
        LianghuaApp(
          store: store,
          pdfImporter: importer,
          reportFetcher: fetcher,
          reportFiles: files,
          ai: ai,
          credentials: MemoryCredentialStore(
            const AiSettings(key: 'native-round4-sentinel'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('公司研究').last);
      await tapVisible(tester, find.textContaining('资料与财务（').first);
      await tapVisible(tester, find.text('自动查找年报'));
      await tapVisible(tester, find.text('查询近三年年报'));
      expect(find.textContaining('缺少年度：2024、2023'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('select-report-123456')),
      );
      await tapVisible(tester, find.text('下载并逐份核对'));
      expect(find.byKey(const ValueKey('retry-report-123456')), findsOneWidget);
      expect(store.data!.documents, isEmpty);
      expect(files.files, isEmpty);
      // The failed download is retried; cancellation at review saves nothing.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('retry-report-123456')),
      );
      expect(find.byType(ReportImportDialog), findsOneWidget);
      expect(store.data!.documents, isEmpty);
      expect(files.files, isEmpty);
      await tapVisible(tester, find.text('取消').last);
      expect(store.data!.documents, isEmpty);
      expect(files.files, isEmpty);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('retry-report-123456')),
      );
      final importDialog = find.byType(ReportImportDialog);
      final checks = find.descendant(
        of: importDialog,
        matching: find.byType(Checkbox),
      );
      expect(tester.widget<Checkbox>(checks.first).value, isFalse);
      final save = find.widgetWithText(FilledButton, '保存选页与原文件');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      final unit = find.descendant(
        of: importDialog,
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tapVisible(tester, unit);
      await tapVisible(tester, find.text('万元').last);
      await tapVisible(tester, checks.first);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tapVisible(
        tester,
        find.descendant(
          of: importDialog,
          matching: find.byType(CheckboxListTile),
        ),
      );
      await tapVisible(tester, save);
      expect(store.data!.documents.length, 1);
      expect(files.files.length, 1);
      final document = store.data!.documents.single;
      expect(document.pages.single.number, 1);
      expect(
        document.pages.single.text.replaceAll(RegExp(r'\s+'), ''),
        contains('营业收入为100.00万元'),
      );
      expect(files.files[document.sha256], bytes);
      expect(document.origin!.announcementId, '123456');
      expect(document.origin!.code, '600001');
      expect(document.origin!.exchange, 'SH');
      expect(document.origin!.isRevision, isTrue);
      expect(document.start, '2025-01-01');
      expect(document.end, '2025-12-31');
      expect(document.disclosedAt, '2026-03-31');
      await tapVisible(tester, find.text('完成（已保存 1 份）'));
      await tapVisible(tester, find.text('AI 提取财务候选值'));
      await tapVisible(tester, find.text('发送选定资料并提取'));
      expect(store.data!.financials, isEmpty);
      await tapVisible(
        tester,
        find.widgetWithText(CheckboxListTile, '营业收入：100.00 万元'),
      );
      await tapVisible(tester, find.byType(CheckboxListTile).last);
      await tapVisible(tester, find.text('保存已核验财务记录'));
      expect(store.data!.financials.single.revenue, 100);
      expect(store.data!.financials.single.basis, '未注明');
      final backup = store.data!.encode();
      expect(backup, isNot(contains('native-round4-sentinel')));
      expect(backup, isNot(contains('originalBase64')));
      final restored = WorkspaceData.decode(backup);
      expect(
        restored.documents.single.origin!.toJson(),
        document.origin!.toJson(),
      );
      expect(restored.sources.single.pageNumber, 1);
      expect(restored.sources.single.url, document.url);
      expect(
        restored.financials.single.evidence['revenue']!.rawValue,
        '100.00',
      );
      expect(
        restored.financials.single.evidence['revenue']!.sourceId,
        restored.sources.single.id,
      );
      // Reopening the official catalogue disables the already saved identity.
      await tapVisible(tester, find.text('自动查找年报'));
      await tapVisible(tester, find.text('查询近三年年报'));
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('select-report-123456')),
            )
            .onChanged,
        isNull,
      );
      expect(transport.downloads, 3);
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print(
        'NATIVE_REPORT_FETCH platform=${Platform.operatingSystem} '
        'nativePdf=true rendered=true retry=true cancelNoWrite=true '
        'humanReview=true originBackup=true aiProof=true duplicate=true',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
