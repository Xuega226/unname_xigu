// Visual QA with fictional holdings. No credentials or network requests.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_import.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';

import '../test/broker_import_test.dart' show snapshot;
import '../test/broker_flow_test.dart' show FakeBrokerFiles, tap;

void main() {
  testWidgets(
    'capture fifth round portfolio import at desktop and phone sizes',
    (tester) async {
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
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: LianghuaApp(
              store: MemoryWorkspaceStore(
                applyBrokerSnapshot(WorkspaceData.empty(), snapshot()),
              ),
              fontFamily: 'PreviewSans',
              brokerImporter: FakeBrokerFiles(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, '账户风控');
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${entry.key}-portfolio');
        await tap(tester, '导入券商持仓');
        await tap(tester, '选择持仓文件');
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${entry.key}-import');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../docs/preview-v0.5');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
