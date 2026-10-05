// Fictional single-account values. This renders charts without broker access.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/risk_charts.dart';

import '../test/risk_charts_test.dart' show riskFixture;

void main() {
  testWidgets(
    'render native risk charts at desktop, phone and large text sizes',
    (tester) async {
      await tester.runAsync(() async {
        final loader = FontLoader('PreviewSans')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
              ),
            ),
          );
        await loader.load();
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in [
        ('desktop', const Size(1280, 1000), 1.0),
        ('phone', const Size(390, 844), 1.0),
        ('phone-large-text', const Size(390, 844), 2.0),
      ]) {
        tester.view.physicalSize = entry.$2;
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        final scroll = ScrollController();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'PreviewSans',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff157d72),
                ),
              ),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(entry.$3)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    controller: scroll,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: RiskCharts(
                        data: riskFixture(),
                        stress: .25,
                        onStressChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${entry.$1}-risk');
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${entry.$1}-scenario');
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
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
    final directory = Directory('../docs/preview-v0.6');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
