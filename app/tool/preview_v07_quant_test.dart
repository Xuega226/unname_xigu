// Fictional company fixtures rendered by Flutter. No broker or model calls.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/quant_widgets.dart';

import '../test/quant_widgets_test.dart' show quantUiFixture, tapQuantControl;

void main() {
  testWidgets(
    'render rule results, actual contributions, comparisons and editing at three sizes',
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
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
                ).readAsBytes(),
              ),
            ),
          );
        await icons.load();
      });
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final entry in [
        ('desktop', const Size(1280, 1000), 1.0),
        ('phone', const Size(390, 844), 1.0),
        ('phone-large-text', const Size(390, 844), 2.0),
        ('phone-negative-cash', const Size(390, 844), 1.0),
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
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(entry.$3)),
                child: child!,
              ),
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
                      child: QuantResearchPanel(
                        data: quantUiFixture(
                          negativeCash: entry.$1.contains('negative'),
                        ),
                        onSave: (_) async => true,
                        onOpenResearch: (_) {},
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
        await capture(tester, key, '${entry.$1}-overview');
        await tapQuantControl(tester, 'quant-details-SH:600001');
        await tester.ensureVisible(find.textContaining('规则命中；贡献 75 分'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${entry.$1}-contributions');
        await tester.ensureVisible(find.text('公司间因子对照'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${entry.$1}-comparison');
        await tapQuantControl(tester, 'quant-edit');
        expect(tester.takeException(), isNull);
        await capture(tester, key, '${entry.$1}-editor');
        await tapQuantControl(tester, 'quant-config-cancel');
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
    final directory = Directory('../docs/preview-v0.7');
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
