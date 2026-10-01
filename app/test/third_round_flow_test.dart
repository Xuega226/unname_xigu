import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/report_widgets.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/financial_widgets.dart';
import 'package:lianghua_assistant/review_widgets.dart';

import 'research_test.dart' show FakeTransport;
import 'v03_test.dart' show document, candidateJson, workspace, record;

class ChosenPdf extends PdfImportService {
  ChosenPdf({this.cancel = false, this.invalid = false});
  final bool cancel, invalid;
  @override
  Future<ParsedReport?> pick({void Function(int, int)? progress}) async {
    if (invalid) throw ServiceFailure('无法读取测试 PDF');
    if (cancel) return null;
    return ParsedReport(
      fileName: '测试财报.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
      hash: document().sha256,
      pages: [
        const ReportPage(number: 1, text: ''),
        ...document().pages,
      ],
    );
  }
}

Future<void> tapVisible(WidgetTester tester, Finder f) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> enterVisible(WidgetTester tester, Finder f, String text) async {
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> dialogHost(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showDialog<void>(context: context, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() => registerThirdRoundFlows();
void registerThirdRoundFlows({bool native = false}) {
  if (!native) {
    testWidgets(
      'history renders an imported date-only timestamp without crashing',
      (tester) async {
        final data = workspace(), old = workspace().studies.first;
        final version = StudyVersion.fromJson({
          'id': 'short-date',
          'study': old.toJson(),
          'createdAt': '2026-10-01',
          'reason': '备份中的短日期',
        });
        final restored = WorkspaceData.decode(
          data.copyWith(studyVersions: [version]).encode(),
        );
        await dialogHost(
          tester,
          StudyHistoryDialog(
            study: old.copyWith(thesis: '新假设'),
            versions: restored.studyVersions,
          ),
        );
        expect(find.textContaining('2026-10-01 · 备份中的短日期'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'whole app imports pages, accepts financial proof, restores backup and appends review',
    (tester) async {
      final old = workspace().studies.first;
      final store = MemoryWorkspaceStore(
        WorkspaceData.empty().copyWith(studies: [old]),
      );
      final files = MemoryReportFileStore();
      final ai = DeepSeekService(
        transport: FakeTransport((u, b) {
          final selected =
              jsonDecode(
                    (b!['messages'] as List).last['content'] as String,
                  )['sources']
                  as List;
          final source = selected.single as Map;
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
                    'missing': ['期末现金和有息负债资料不足'],
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
          pdfImporter: ChosenPdf(),
          reportFiles: files,
          ai: ai,
          credentials: MemoryCredentialStore(
            const AiSettings(key: 'flow-sentinel'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('公司研究').last);
      await tapVisible(tester, find.textContaining('资料与财务（').first);
      await tapVisible(tester, find.text('导入财报 PDF'));
      await tapVisible(tester, find.text('选择 PDF 文件'));
      final fields = find.byType(TextFormField);
      for (final item in [
        (2, '2025年度'),
        (3, '2025-01-01'),
        (4, '2025-12-31'),
        (5, '2026-03-31'),
      ]) {
        await enterVisible(tester, fields.at(item.$1), item.$2);
      }
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tapVisible(tester, find.text('万元').last);
      await tapVisible(tester, find.byType(Checkbox).at(1));
      await tapVisible(tester, find.byType(CheckboxListTile));
      await tapVisible(tester, find.text('保存选页与原文件'));
      expect(store.data!.documents.length, 1);
      expect(files.files.length, 1);
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
      final backup = store.data!.encode();
      expect(backup, isNot(contains('flow-sentinel')));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final restoredStore = MemoryWorkspaceStore(WorkspaceData.decode(backup));
      await tester.pumpWidget(
        LianghuaApp(store: restoredStore, reportFiles: MemoryReportFileStore()),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('复查日志').last);
      await tapVisible(tester, find.text('记录一次复查'));
      await enterVisible(
        tester,
        find.byType(TextFormField).last,
        '备份恢复后继续复查现金流。',
      );
      await tapVisible(tester, find.text('保存'));
      expect(restoredStore.data!.reviews.single.text, '备份恢复后继续复查现金流。');
      expect(
        restoredStore.data!.documents.single.sha256,
        store.data!.documents.single.sha256,
      );
      expect(
        restoredStore.data!.financials.single.evidence['revenue']!.rawValue,
        '100.00',
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final size
      in (native ? [null] : [const Size(390, 844), const Size(1280, 1000)])) {
    testWidgets('PDF selection, human confirmation and cancel fit $size', (
      tester,
    ) async {
      if (size != null) tester.view.physicalSize = size;
      if (size != null) tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      ReportDocument? saved;
      final files = MemoryReportFileStore();
      await dialogHost(
        tester,
        ReportImportDialog(
          study: workspace().studies.first,
          importer: ChosenPdf(),
          existingHashes: {},
          save: (d, bytes) async {
            saved = d;
            await files.put(d.sha256, bytes);
            return true;
          },
        ),
      );
      await tapVisible(tester, find.text('选择 PDF 文件'));
      expect(saved, isNull);
      expect(files.files, isEmpty);
      final fields = find.byType(TextFormField);
      for (final item in [
        (2, '2025年度'),
        (3, '2025-01-01'),
        (4, '2025-12-31'),
        (5, '2026-03-31'),
      ]) {
        await enterVisible(tester, fields.at(item.$1), item.$2);
      }
      final emptyCheck = tester.widget<Checkbox>(find.byType(Checkbox).at(0));
      expect(emptyCheck.onChanged, isNull);
      await tapVisible(tester, find.byType(Checkbox).at(1));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存选页与原文件'))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.byType(CheckboxListTile));
      await enterVisible(tester, fields.at(2), '2025 年度已核对');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存选页与原文件'))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.byType(CheckboxListTile));
      await tapVisible(tester, find.text('保存选页与原文件'));
      expect(saved!.pages.single.number, 2);
      expect(files.files.length, 1);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'financial candidates need explicit selection and review at $size',
      (tester) async {
        if (size != null) tester.view.physicalSize = size;
        if (size != null) tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = workspace();
        FinancialRecord? saved;
        final ai = DeepSeekService(
          transport: FakeTransport(
            (u, b) => {
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'content': jsonEncode({
                      'candidates': [
                        candidateJson(),
                        {...candidateJson(metric: 'cash'), 'rawValue': '999'},
                      ],
                      'missing': ['有息负债缺失'],
                      'notes': [],
                    }),
                  },
                },
              ],
            },
          ),
        );
        await dialogHost(
          tester,
          FinancialExtractionDialog(
            study: data.studies.first,
            sources: data.sources,
            documents: data.documents,
            store: MemoryCredentialStore(
              const AiSettings(key: 'test-only-sentinel'),
            ),
            service: ai,
            save: (f) async {
              saved = f;
              return true;
            },
          ),
        );
        await tapVisible(tester, find.text('发送选定资料并提取'));
        expect(saved, isNull);
        final candidateCheck = find.widgetWithText(
          CheckboxListTile,
          '营业收入：100.00 万元',
        );
        final invalidCheck = find.widgetWithText(
          CheckboxListTile,
          '期末现金：999 万元',
        );
        expect(tester.widget<CheckboxListTile>(invalidCheck).onChanged, isNull);
        await tapVisible(tester, candidateCheck);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, '保存已核验财务记录'),
              )
              .onPressed,
          isNull,
        );
        await tapVisible(tester, find.byType(CheckboxListTile).last);
        await tapVisible(tester, find.text('保存已核验财务记录'));
        expect(saved!.revenue, 100);
        expect(saved!.cash, isNull);
        expect(
          WorkspaceData.decode(data.copyWith(financials: [saved!]).encode())
              .financials
              .single
              .origin,
          'aiConfirmed',
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'review snapshots and trend tables fit $size after backup restoration',
      (tester) async {
        if (size != null) tester.view.physicalSize = size;
        if (size != null) tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final initial = workspace();
        final store = MemoryWorkspaceStore(
          WorkspaceData.decode(initial.encode()),
        );
        await tester.pumpWidget(LianghuaApp(store: store));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('公司研究').last);
        await tapVisible(tester, find.text('复查计划与清单').first);
        await enterVisible(tester, find.byType(TextFormField), '2026-11-01');
        await tapVisible(tester, find.text('添加待验证条件'));
        await enterVisible(
          tester,
          find
              .descendant(
                of: find.byType(ReviewTaskDialog),
                matching: find.byType(TextFormField),
              )
              .first,
          '经营现金流是否恢复',
        );
        await tapVisible(tester, find.text('保存此条件'));
        await tapVisible(tester, find.text('保存复查计划'));
        expect(store.data!.studies.first.reviewTasks.single.text, '经营现金流是否恢复');
        expect(store.data!.studyVersions.single.study.nextReviewAt, '');
        await tapVisible(tester, find.text('研究版本对照').first);
        expect(find.text('下次复查日期'), findsOneWidget);
        expect(find.text('待验证清单'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text('关闭'));
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await dialogHost(
          tester,
          FinancialTrendDialog(
            study: initial.studies.first,
            records: [record(2024, 100), record(2025, 120)],
          ),
        );
        expect(find.text('20.0%'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('cancel, invalid and duplicate PDF do not call persistence', (
    tester,
  ) async {
    for (final importer in [
      ChosenPdf(cancel: true),
      ChosenPdf(invalid: true),
      ChosenPdf(),
    ]) {
      var writes = 0;
      await dialogHost(
        tester,
        ReportImportDialog(
          study: workspace().studies.first,
          importer: importer,
          existingHashes: {document().sha256},
          save: (d, b) async {
            writes++;
            return true;
          },
        ),
      );
      await tapVisible(tester, find.text('选择 PDF 文件'));
      expect(writes, 0);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存选页与原文件'))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.text('取消'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
  testWidgets('restored page text remains readable without original PDF', (
    tester,
  ) async {
    await dialogHost(
      tester,
      PdfPageDialog(
        importer: ChosenPdf(),
        pages: document().pages,
        initialPage: 2,
      ),
    );
    expect(find.textContaining('本机尚无原 PDF'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
