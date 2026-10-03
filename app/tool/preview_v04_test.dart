// Visual QA uses fictional announcements, no network or credentials.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/report_fetch_widgets.dart';

import '../test/report_fetch_flow_test.dart'
    show FakeReports, FakePdf, study, announcement, select, tap;

void main() {
  testWidgets('capture fourth round report fetching in Chinese', (
    tester,
  ) async {
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
    for (final entry in {
      'desktop': const Size(1280, 1000),
      'android': const Size(390, 844),
    }.entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      final source = FakeReports([
        announcement('a', 2025),
        announcement('b', 2025, revised: true),
        announcement('c', 2024),
      ])..failDownloads.add('c');
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
                    barrierDismissible: false,
                    builder: (_) => ReportFetchDialog(
                      study: study,
                      exchange: 'SH',
                      service: source,
                      importer: FakePdf(),
                      existingDocuments: const [],
                      save: (_, _) async => true,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tap(tester, find.text('open'));
      await tap(tester, find.text('查询近三年年报'));
      await select(tester, 'c');
      await tap(tester, find.text('下载并逐份核对'));
      await tester.ensureVisible(find.text('查询近三年年报'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${entry.key}-reports');
      await tester.ensureVisible(find.text('失败：测试下载失败'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await capture(tester, key, '${entry.key}-reports-results');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../docs/preview-v0.4');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
