// Render the shared UI without opening native app windows.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';

void main() {
  testWidgets('capture desktop and phone UI for visual inspection',
      (tester) async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    await tester.runAsync(() async {
      final loader = FontLoader('PreviewSans');
      loader.addFont(
          Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(Future.value(ByteData.sublistView(await File(
              '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytes())));
      await icons.load();
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final entry in {
      'desktop': const Size(1280, 900),
      'android': const Size(390, 844)
    }.entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: LianghuaApp(
              store: MemoryWorkspaceStore(WorkspaceData.demo()),
              fontFamily: 'PreviewSans')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('../docs/preview');
        await directory.create(recursive: true);
        await File('${directory.path}/${entry.key}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
