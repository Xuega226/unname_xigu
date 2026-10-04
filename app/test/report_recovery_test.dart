import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/report_widgets.dart';

import 'v03_test.dart' show document, originalText;

class _UnreadableOriginal extends MemoryReportFileStore {
  @override
  Future<Uint8List?> read(String hash) async =>
      throw const FormatException('原 PDF 校验失败');
}

void main() {
  testWidgets(
    'corrupt original is distinct from missing and text stays readable',
    (tester) async {
      final files = _UnreadableOriginal();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    readReport(context, document(), files, PdfImportService()),
                child: const Text('查看'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('查看'));
      await tester.pumpAndSettle();
      expect(find.textContaining('读取或校验失败'), findsOneWidget);
      expect(find.textContaining('本机尚无原 PDF'), findsNothing);
      expect(find.text(originalText), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '原页'))
            .onPressed,
        isNull,
      );
      expect(files.files, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
