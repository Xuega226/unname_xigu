// Manual visual QA of third-round dialogs using fictional data only.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/financial_widgets.dart';
import 'package:lianghua_assistant/review_widgets.dart';
import 'package:lianghua_assistant/services.dart';

import '../test/research_test.dart' show FakeTransport;
import '../test/v03_test.dart' show workspace, candidateJson;

void main() {
  testWidgets('capture third round Chinese dialogs', (tester) async {
    await tester.runAsync(() async {
      for (final pair in [
        ('PreviewSans', 'C:/Windows/Fonts/msyh.ttc'),
        (
          'MaterialIcons',
          '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ),
      ]) {
        final loader = FontLoader(pair.$1)
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(pair.$2).readAsBytes()),
            ),
          );
        await loader.load();
      }
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = workspace(), old = workspace().studies.first;
    final next = old.copyWith(
      thesis: '收入增长仍须与现金回收同步验证。',
      nextReviewAt: '2026-11-01',
      reviewTasks: [
        const ReviewTask(
          id: 't',
          text: '现金流是否改善',
          status: '资料不足',
          note: '还需要下一报告期数据。',
        ),
      ],
    );
    final versions = saveStudyVersion(data, next, '更新假设与复查计划').studyVersions;
    for (final entry in {
      'desktop': const Size(1280, 1000),
      'android': const Size(390, 844),
    }.entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      for (final kind in ['history', 'financial']) {
        final key = GlobalKey();
        final dialog = kind == 'history'
            ? StudyHistoryDialog(study: next, versions: versions)
            : FinancialExtractionDialog(
                study: old,
                sources: data.sources,
                documents: data.documents,
                store: MemoryCredentialStore(
                  const AiSettings(key: 'preview-only'),
                ),
                service: DeepSeekService(
                  transport: FakeTransport(
                    (u, b) => {
                      'choices': [
                        {
                          'finish_reason': 'stop',
                          'message': {
                            'content': jsonEncode({
                              'candidates': [candidateJson()],
                              'missing': ['现金及有息负债未提供'],
                              'notes': [],
                            }),
                          },
                        },
                      ],
                    },
                  ),
                ),
                save: (f) async => true,
              );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'PreviewSans',
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF117D75),
                ),
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => dialog,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        if (kind == 'financial') {
          await tester.tap(find.text('发送选定资料并提取'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.widgetWithText(CheckboxListTile, '营业收入：100.00 万元'),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('../docs/preview-v0.3');
          await directory.create(recursive: true);
          await File('${directory.path}/${entry.key}-$kind.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    }
  });
}
