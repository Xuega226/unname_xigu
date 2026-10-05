import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/report_preparation.dart';
import 'package:lianghua_assistant/report_widgets.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/services.dart';

const pages = [
  ReportPage(number: 40, text: '2025年度 合并财务报表 单位：万元 本期金额比较金额'),
  ReportPage(number: 41, text: '印刷页码 39 合并利润表 营业收入 100.00 扣除非经常性损益的净利润 8.00'),
  ReportPage(number: 42, text: '经营活动现金流量表 经营活动产生的现金流量净额 20.00'),
  ReportPage(number: 43, text: '有息负债附注 短期借款 10.00 单位：元'),
];

class Transport implements JsonTransport {
  int calls = 0;
  Map<String, dynamic>? body;
  Map<String, dynamic> result = {
    'pages': [
      {
        'number': 41,
        'title': '合并利润表',
        'reason': '收入和利润',
        'quote': pages[1].text,
      },
    ],
    'metadataEvidence': [
      {'field': 'scope', 'value': '合并', 'page': 41, 'quote': pages[1].text},
    ],
    'warnings': <String>[],
  };
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    calls++;
    this.body = body;
    if (pending != null) return pending!.future;
    return response();
  }

  Map<String, dynamic> response() => {
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': jsonEncode(result)},
      },
    ],
    'usage': {'total_tokens': 123},
  };
}

const study = Study(
  id: 's',
  code: '600660',
  name: '测试公司',
  business: '',
  thesis: '',
  counterEvidence: '',
  reviewCondition: '',
  source: '',
  updatedAt: '2026-10-05',
);

void main() {
  test('production PDF ISO report range fills period without treating disclosure as end', () {
    final p = locateReportPages('c', const [
      ReportPage(
        number: 1,
        text: '虚构测试公司 - 财报流程验证\n报告期间：2025-01-01 至 2025-12-31\n披露日期：2026-03-31\n合并报表，单位：万元，数字为本期列。营业收入为100.00万元。',
      ),
    ]);
    expect(p.start, '2025-01-01');
    expect(p.end, '2025-12-31');
    expect(p.periodLabel, '2025 年度');
    final ambiguous = locateReportPages('c', const [
      ReportPage(
        number: 1,
        text: '合并利润表 本期2025-01-01至2025-12-31 比较期2024-01-01至2024-12-31',
      ),
    ]);
    expect(ambiguous.start, isNull);
    expect(ambiguous.end, isNull);
  });
  ReportDocument document({PreparationSuggestion? preparation}) =>
      ReportDocument(
        id: 'old',
        studyId: study.id,
        fileName: 'r.pdf',
        sha256: 'a' * 64,
        title: '人工保留标题',
        url: '',
        period: '2024 年度',
        start: '2024-01-01',
        end: '2024-12-31',
        disclosedAt: '2026-03-31',
        unit: '亿元',
        importedAt: '2026-10-01T00:00:00Z',
        pageCount: 44,
        pages: pages,
        preparation: preparation,
      );
  test('report preparation persists with source binding and per-table excerpt units', () {
    final p = locateReportPages('c', pages);
    final copy = ReportDocument.fromJson(document(preparation: p).toJson());
    expect(copy.preparation!.end, '2025-12-31');
    expect(copy.excerpts().first.unit, '万元');
    expect(copy.excerpts().last.unit, '元');
    // New table with no own unit cannot inherit across a mixed-unit document.
    expect(copy.excerpts()[1].unit, '不适用');
    final altered = document(preparation: p).toJson();
    altered['pages'] = [
      const ReportPage(number: 40, text: '与旧引用无关的新原文文本').toJson(),
    ];
    expect(() => ReportDocument.fromJson(altered), throwsFormatException);
  });
  testWidgets(
    'existing input conflict and failed AI preserve metadata and local range',
    (tester) async {
      final t = Transport()..result = {'invalid': 'result'};
      final existing = document();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportImportDialog(
              study: study,
              importer: PdfImportService(),
              existingHashes: const {},
              existingDocument: existing,
              coverageOnly: true,
              initialReport: ParsedReport(
                fileName: 'r.pdf',
                bytes: Uint8List(0),
                hash: 'a' * 64,
                pages: pages,
              ),
              store: MemoryCredentialStore(
                const AiSettings(key: 'fake', model: 'fixture'),
              ),
              service: DeepSeekService(transport: t),
              save: (_, _) async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('当前 2024-01-01'), findsOneWidget);
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(fields[0].controller!.text, '人工保留标题');
      expect(fields[3].controller!.text, '2024-01-01');
      final ai = find.widgetWithText(FilledButton, 'AI 选页与预填');
      await tester.ensureVisible(ai);
      await tester.tap(ai);
      await tester.pumpAndSettle();
      expect(find.textContaining('校验失败'), findsOneWidget);
      expect(fields[3].controller!.text, '2024-01-01');
      expect(find.textContaining('PDF 页序 40、41、42、43'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'local real PDF numbering, adjacent header, mixed units and annual period',
    () {
      final p = locateReportPages('600660 测试公司', pages);
      expect(p.pages.map((p) => p.number), [40, 41, 42, 43]);
      expect(p.start, '2025-01-01');
      expect(p.end, '2025-12-31');
      expect(p.unit, isNull);
      expect(p.tableUnits.map((e) => e.value), ['万元', '元']);
      expect(p.warnings.single, contains('单位不同'));
      p.validateSources(pages);
      final copy = PreparationSuggestion.fromJson(p.toJson());
      copy.validateSources(pages);
    },
  );
  test('no tables and comparative annual headings never guessed', () {
    expect(
      locateReportPages('c', const [
        ReportPage(number: 1, text: '公司董事会成员个人介绍'),
      ]).pages,
      isEmpty,
    );
    final p = locateReportPages('c', const [
      ReportPage(number: 1, text: '合并利润表 2025年度 2024年度 单位未知 营业收入'),
    ]);
    expect(p.start, isNull);
    expect(p.end, isNull);
    expect(p.unit, isNull);
  });
  test(
    'explicit body date range is parsed without disclosure-date guessing',
    () {
      final p = locateReportPages('c', const [
        ReportPage(
          number: 7,
          text: '合并现金流量表 单位：万元 2025年01月01日至2025年06月30日 本期上期',
        ),
      ]);
      expect(p.start, '2025-01-01');
      expect(p.end, '2025-06-30');
      expect(p.periodLabel, '2025-01-01 至 2025-06-30');
      p.validateSources(const [
        ReportPage(
          number: 7,
          text: '合并现金流量表 单位：万元 2025年01月01日至2025年06月30日 本期上期',
        ),
      ]);
    },
  );
  test('model preserves sent adjacent header, verifies sources and records actual usage', () async {
    final t = Transport();
    final p = await ReportPreparationService(DeepSeekService(transport: t))
        .prepare(key: 'fake-key', model: 'fixture', company: 'c', pages: pages);
    expect(t.calls, 1);
    expect(p.pages.map((p) => p.number), [40, 41, 42]);
    expect(p.start, '2025-01-01');
    expect(p.unit, '万元');
    expect(p.usage!['total_tokens'], 123);
    expect(t.body!['model'], 'fixture');
  });
  test(
    'fake page, false quote and unsupported metadata are rejected',
    () async {
      for (final invalid in [
        {
          'pages': [
            {
              'number': 39,
              'title': 'fake',
              'reason': 'fake',
              'quote': pages[1].text,
            },
          ],
          'metadataEvidence': [],
          'warnings': [],
        },
        {
          'pages': [
            {
              'number': 41,
              'title': 'fake',
              'reason': 'fake',
              'quote': '该公司没有提供的摘录',
            },
          ],
          'metadataEvidence': [],
          'warnings': [],
        },
        {
          'pages': [
            {
              'number': 41,
              'title': 'fake',
              'reason': 'fake',
              'quote': pages[1].text,
            },
          ],
          'metadataEvidence': [
            {
              'field': 'unit',
              'value': '亿元',
              'page': 41,
              'quote': pages[1].text,
            },
          ],
          'warnings': [],
        },
      ]) {
        final t = Transport()..result = invalid;
        await expectLater(
          ReportPreparationService(
            DeepSeekService(transport: t),
          ).prepare(key: 'fake', model: 'fixture', company: 'c', pages: pages),
          throwsA(isA<ServiceFailure>()),
        );
      }
    },
  );
  test(
    'no text, absent key and oversized range make no paid request',
    () async {
      final t = Transport();
      final s = ReportPreparationService(DeepSeekService(transport: t));
      for (final range in [
        <ReportPage>[],
        [ReportPage(number: 1, text: 'a' * 60001)],
      ]) {
        await expectLater(
          s.prepare(key: 'fake', model: 'fixture', company: 'c', pages: range),
          throwsA(isA<ServiceFailure>()),
        );
      }
      await expectLater(
        s.prepare(key: '', model: 'fixture', company: 'c', pages: pages),
        throwsA(isA<ServiceFailure>()),
      );
      expect(t.calls, 0);
    },
  );
  testWidgets(
    'preparation cancellation and late result preserve edited inputs at mobile 2x',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final t = Transport()..pending = Completer<Map<String, dynamic>>();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: ReportImportDialog(
                study: study,
                importer: PdfImportService(),
                existingHashes: const {},
                initialReport: ParsedReport(
                  fileName: 'r.pdf',
                  bytes: Uint8List(0),
                  hash: 'a' * 64,
                  pages: pages,
                ),
                coverageOnly: true,
                store: MemoryCredentialStore(
                  const AiSettings(key: 'fake', model: 'fixture'),
                ),
                service: DeepSeekService(transport: t),
                save: (_, _) async => true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ai = find.widgetWithText(FilledButton, 'AI 选页与预填');
      await tester.ensureVisible(ai);
      await tester.tap(ai);
      await tester.pump();
      expect(t.calls, 1);
      final stop = find.text('停止等待');
      await tester.ensureVisible(stop);
      await tester.tap(stop);
      await tester.pump();
      expect(find.textContaining('已停止等待'), findsOneWidget);
      t.pending!.complete(t.response());
      await tester.pumpAndSettle();
      expect(find.textContaining('已停止等待'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
