import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/research_widgets.dart';
import 'package:lianghua_assistant/services.dart';

import 'research_test.dart' show FakeTransport, testSource;
import 'v03_test.dart' show document;

Future<void> _open(
  WidgetTester tester, {
  bool allowAI = true,
  bool empty = false,
  double textScale = 1,
  Future<bool> Function(SourceExcerpt)? saveSource,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EvidenceDialog(
                study: WorkspaceData.demo().studies.first,
                sources: empty ? [] : [testSource],
                documents: empty ? [] : [document()],
                financials: empty
                    ? []
                    : [
                        const FinancialRecord(
                          id: 'financial-1',
                          studyId: 's0',
                          sourceId: 'source-1',
                          start: '2025-01-01',
                          end: '2025-12-31',
                          disclosedAt: '2026-03-31',
                          unit: '万元',
                          revenue: 100,
                          adjustedProfit: -20,
                        ),
                      ],
                specialIndustry: false,
                allowAI: allowAI,
                importer: PdfImportService(),
                files: MemoryReportFileStore(),
                store: MemoryCredentialStore(),
                service: DeepSeekService(
                  transport: FakeTransport((_, _) => throw StateError('No AI')),
                ),
                addSource: saveSource ?? (_) async => true,
                addFinancial: (_) async => true,
                addDocument: (_, _) async => true,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'evidence exposes annual-report fetch and keeps traceable detail on demand',
    (tester) async {
      await _open(tester);
      expect(find.text('1 添加资料 → 2 核验财务 → 3 用于研究'), findsOneWidget);
      expect(find.text('核对财务字段'), findsNothing);
      expect(find.text('自动查找年报'), findsOneWidget);
      expect(find.text('AI 预核验'), findsNothing);
      expect(find.textContaining('SHA-256：'), findsNothing);
      await _tap(tester, find.text(document().fileName));
      expect(find.text('SHA-256：${document().sha256}'), findsOneWidget);
      expect(find.text('查看原页与选页原文'), findsOneWidget);
      await _tap(tester, find.text(testSource.title));
      expect(find.textContaining(testSource.text), findsOneWidget);
      expect(find.text('来源 ID：source-1'), findsOneWidget);
      await _tap(tester, find.text('添加资料'));
      expect(find.text('查询年报（更多）'), findsOneWidget);
      expect(find.text('导入财报 PDF'), findsOneWidget);
      expect(find.text('添加原文片段'), findsOneWidget);
      await _tap(tester, find.text('添加原文片段'));
      expect(find.text('录入原始资料片段'), findsOneWidget);
      await _tap(tester, find.text('取消'));
      expect(find.text('PDF 1 份 · 原文 1 段'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('financial view keeps missing and negative amounts visible', (
    tester,
  ) async {
    await _open(tester);
    await _tap(tester, find.text('财务核验'));
    expect(find.text('核对财务字段'), findsOneWidget);
    expect(find.text('AI 预核验'), findsOneWidget);
    expect(find.text('营收 100.00 · 扣非净利 -20.00'), findsOneWidget);
    expect(find.text('经营现金流 资料不足'), findsOneWidget);
    expect(find.text('期末现金 资料不足 · 有息负债 资料不足'), findsOneWidget);
    expect(find.textContaining('来源 [source-1]'), findsNothing);
    await _tap(tester, find.text('来源与核验依据'));
    expect(find.textContaining('来源 [source-1]'), findsOneWidget);
    await _tap(tester, find.text('资料原文'));
    expect(find.text(testSource.title), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty and demo states explain requirements without bypassing AI',
    (tester) async {
      await _open(tester, empty: true, allowAI: false);
      await _tap(tester, find.text('财务核验'));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'AI 预核验'))
            .onPressed,
        isNull,
      );
      await _tap(tester, find.text('核对财务字段'));
      expect(find.text('先录入带出处的原文，再据此核对财务字段'), findsOneWidget);
      await _tap(tester, find.text('添加资料'));
      for (final label in ['查询年报（更多）', '导入财报 PDF']) {
        expect(
          tester
              .widget<PopupMenuItem<String>>(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(PopupMenuItem<String>),
                ),
              )
              .enabled,
          isFalse,
        );
      }
      await _tap(tester, find.text('添加原文片段'));
      await _tap(tester, find.text('取消'));
      expect(find.text('先录入带出处的原文，再据此核对财务字段'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow screen and large text keep evidence actions reachable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(tester, textScale: 2);
    await _tap(tester, find.text('财务核验'));
    await _tap(tester, find.text('核对财务字段'));
    expect(find.text('选择财务来源片段'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('添加资料'));
    await _tap(tester, find.text('添加原文片段'));
    await _tap(tester, find.text('取消'));
    await _tap(tester, find.text('关闭'));
    expect(find.text('open'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed source save keeps current view and previous evidence', (
    tester,
  ) async {
    SourceExcerpt? attempted;
    await _open(
      tester,
      saveSource: (source) async {
        attempted = source;
        return false;
      },
    );
    await _tap(tester, find.text('财务核验'));
    await _tap(tester, find.text('添加资料'));
    await _tap(tester, find.text('添加原文片段'));
    final values = [
      '新增资料',
      'https://example.com/new-report',
      '2025年度',
      '2026-03-31',
      '第12页',
      '万元',
      '本年度营业收入为200万元。',
    ];
    for (var i = 0; i < values.length; i++) {
      final field = find.byType(TextFormField).at(i);
      await tester.ensureVisible(field);
      await tester.enterText(field, values[i]);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _tap(tester, find.text('保存'));
    expect(attempted?.title, '新增资料');
    expect(find.text('保存失败，片段未应用'), findsOneWidget);
    expect(find.text('核对财务字段'), findsOneWidget);
    await _tap(tester, find.text('资料原文'));
    expect(find.text('PDF 1 份 · 原文 1 段'), findsOneWidget);
    expect(find.text('新增资料'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
