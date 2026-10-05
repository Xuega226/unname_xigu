// Shared widget / native PDF preparation acceptance. Only bundled fictional
// public report text and a memory-only model credential are used.
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/financial_widgets.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/report_widgets.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/services.dart';

import 'v073_acceptance.dart';

class _PreparationTransport implements JsonTransport {
  int requests = 0;
  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    requests++;
    expect(uri, Uri.https('api.deepseek.com', '/chat/completions'));
    expect(headers['Authorization'], 'Bearer $v073Sentinel');
    final input = jsonDecode(
      (body!['messages'] as List).last['content'] as String,
    ) as Map<String, dynamic>;
    expect(input.keys.toSet(), {'company', 'pages'});
    expect(jsonEncode(input), isNot(contains(v073Sentinel)));
    final pages = (input['pages'] as List)
        .cast<Map<String, dynamic>>()
        .map(ReportPage.fromJson)
        .toList();
    return v073ModelResponse({
      'pages': [
        for (final p in pages)
          {
            'number': p.number,
            'title': p.number == 1 ? '年度业绩页' : '现金流与债务页',
            'reason': '离线标注夹具中完整财务原文及表头',
            'quote': p.text,
          },
      ],
      'metadataEvidence': [
        {
          'field': 'start',
          'value': '2025-01-01',
          'page': 1,
          'quote': pages.first.text,
        },
        {
          'field': 'end',
          'value': '2025-12-31',
          'page': 1,
          'quote': pages.first.text,
        },
        {'field': 'scope', 'value': '合并', 'page': 1, 'quote': pages.first.text},
        for (final p in pages)
          {'field': 'unit', 'value': '万元', 'page': p.number, 'quote': p.text},
      ],
      'warnings': <String>[],
    });
  }
}

void registerV073ReportAcceptance({bool native = false}) {
  testWidgets(
    'v073 production PDF preparation once adoption portable metadata and financial prefills',
    (tester) async {
      if (!native) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final bytes = (await rootBundle.load(
        'integration_test/fixtures/fictional-report.pdf',
      )).buffer.asUint8List();
      final importer = PdfImportService();
      final parsed = native
          ? (await tester.runAsync(
              () => importer.parse(bytes, 'fictional-report.pdf'),
            ))!
          : ParsedReport(
              fileName: 'fictional-report.pdf',
              bytes: bytes,
              hash: crypto.sha256.convert(bytes).toString(),
              pages: const [
                ReportPage(
                  number: 1,
                  text: '虚构测试公司2025年度合并报表，单位万元。营业收入为100.00万元，扣非净利润为8.00万元。',
                ),
                ReportPage(
                  number: 2,
                  text: '合并报表，单位：万元，数字为本期列。经营活动产生的现金流量净额为-20.00万元。期末货币资金为30.00万元，有息负债为50.00万元。',
                ),
              ],
            );
      expect(parsed.pages.length, 2);
      final transport = _PreparationTransport();
      final initial = WorkspaceData.demo();
      final study = initial.studies.first;
      ReportDocument? adopted;
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ReportImportDialog(
                    study: study,
                    importer: importer,
                    existingHashes: const {},
                    initialReport: parsed,
                    store: MemoryCredentialStore(
                      const AiSettings(key: v073Sentinel),
                    ),
                    service: DeepSeekService(transport: transport),
                    save: (document, pdf) async {
                      writes++;
                      adopted = document;
                      expect(pdf, bytes);
                      return true;
                    },
                  ),
                ),
                child: const Text('open-report-preparation'),
              ),
            ),
          ),
        ),
      );
      await v073Tap(tester, find.text('open-report-preparation'));
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[2].controller!.text, '2025 年度');
      expect(fields[3].controller!.text, '2025-01-01');
      expect(fields[4].controller!.text, '2025-12-31');
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.textContaining('PDF 页序 1、2'), findsOneWidget);
      await v073Tap(tester, find.widgetWithText(FilledButton, 'AI 选页与预填'));
      expect(transport.requests, 1);
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, '披露日期 YYYY-MM-DD'),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '披露日期 YYYY-MM-DD'),
        '2026-03-31',
      );
      await v073Tap(tester, find.widgetWithText(FilledButton, '采用范围并保存原文'));
      expect(writes, 1);
      expect(adopted, isNotNull);
      expect(adopted!.preparation!.method, 'ai');
      expect(adopted!.preparation!.model, DeepSeekService.defaultModel);
      expect(adopted!.preparation!.usage!['total_tokens'], 200);
      expect(adopted!.preparation!.scope, '合并');
      expect(adopted!.pages.map((p) => p.number), [1, 2]);
      expect(adopted!.excerpts().map((s) => s.unit), everyElement('万元'));
      final roundTrip = WorkspaceData.decode(
        initial
            .copyWith(documents: [adopted!], sources: adopted!.excerpts())
            .encode(),
      );
      expect(
        roundTrip.documents.single.preparation!.toJson(),
        adopted!.preparation!.toJson(),
      );
      final legacyJson = roundTrip.toJson();
      legacyJson['schemaVersion'] = 7;
      for (final document in legacyJson['documents'] as List) {
        (document as Map).remove('preparation');
      }
      final legacy = WorkspaceData.decode(jsonEncode(legacyJson));
      expect(legacy.documents.single.preparation, isNull);
      expect(legacy.documents.single.sha256, adopted!.sha256);
      ReportDocument? revised;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ReportImportDialog(
                    study: study,
                    importer: importer,
                    existingHashes: const {},
                    initialReport: parsed,
                    existingDocument: adopted,
                    save: (document, pdf) async {
                      revised = document;
                      final combined = WorkspaceData.decode(
                        initial
                            .copyWith(
                              documents: [adopted!, document],
                              sources: [
                                ...adopted!.excerpts(),
                                ...document.excerpts(),
                              ],
                            )
                            .encode(),
                      );
                      expect(
                        combined.documents.first.toJson(),
                        adopted!.toJson(),
                      );
                      expect(combined.documents.last.preparedFrom, adopted!.id);
                      expect(combined.documents.last.sha256, adopted!.sha256);
                      return true;
                    },
                  ),
                ),
                child: const Text('reprepare-report'),
              ),
            ),
          ),
        ),
      );
      await v073Tap(tester, find.text('reprepare-report'));
      await v073Tap(tester, find.widgetWithText(FilledButton, '采用范围并保存原文'));
      expect(revised, isNotNull);
      expect(revised!.id, isNot(adopted!.id));
      expect(revised!.preparedFrom, adopted!.id);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FinancialExtractionDialog(
              study: study,
              sources: adopted!.excerpts(),
              documents: [adopted!],
              store: MemoryCredentialStore(const AiSettings(key: v073Sentinel)),
              service: DeepSeekService(
                transport: V073OfflineTransport(candidates: const []),
              ),
              save: (_) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final financialFields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(financialFields[0].controller!.text, '2025-01-01');
      expect(financialFields[1].controller!.text, '2025-12-31');
      expect(find.text('合并'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print(
        'V073_REPORT_PREPARATION native=$native pages=2 requests=1 metadataPreserved=true legacyMigration=true reprepareKeepsOld=true financialPrefill=true',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
