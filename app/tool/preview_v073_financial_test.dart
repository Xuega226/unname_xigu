// Visual QA consumes the real production dialog; all amounts are fictional.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/v073_acceptance.dart';

void main() {
  testWidgets('v073 financial preparation and summary visual QA', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await (FontLoader('PreviewSans')..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
              ),
            ),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
                ).readAsBytes(),
              ),
            ),
          ))
          .load();
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final viewport in [
      ('desktop', const Size(1280, 1000), 1.0),
      ('phone', const Size(390, 844), 1.0),
      ('phone-large-text', const Size(390, 844), 2.0),
    ]) {
      tester.view.physicalSize = viewport.$2;
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await v073DialogHost(
        tester,
        transport: V073OfflineTransport(),
        save: (_) async => true,
        scale: viewport.$3,
        captureKey: key,
        fontFamily: 'PreviewSans',
      );
      await _capture(tester, key, '${viewport.$1}-range');
      await v073Tap(tester, find.byKey(const ValueKey('financial-start')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('financial-candidate-0')),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '${viewport.$1}-summary');
      await v073Tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('financial-candidate-0')),
          matching: find.byType(ExpansionTile),
        ),
      );
      await _capture(tester, key, '${viewport.$1}-evidence');
      await tester.ensureVisible(find.byKey(const ValueKey('financial-save')));
      await tester.pumpAndSettle();
      await _capture(tester, key, '${viewport.$1}-confirm');
      await v073Tap(tester, find.text('关闭'));
      await v073DialogHost(
        tester,
        transport: V073OfflineTransport(verdicts: {0: 'fail', 2: 'unknown'}),
        save: (_) async => true,
        scale: viewport.$3,
        captureKey: key,
        fontFamily: 'PreviewSans',
      );
      await v073Tap(tester, find.byKey(const ValueKey('financial-start')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('financial-candidate-0')),
      );
      await tester.pumpAndSettle();
      await _capture(tester, key, '${viewport.$1}-exceptions');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../docs/preview-v0.7.3');
    await directory.create(recursive: true);
    await File('${directory.path}/financial-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
