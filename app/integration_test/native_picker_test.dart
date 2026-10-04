// Manual opt-in: select integration_test/fixtures/fictional-report.pdf in the
// system chooser (Android: push this fixture to the emulator Downloads first).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/report_import.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('system PDF chooser returns bytes for native extraction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('选择虚构测试财报 PDF；不修改研究工作区'))),
    );
    final parsed = await PdfImportService().pick().timeout(
      const Duration(minutes: 5),
    );
    expect(parsed, isNotNull);
    expect(parsed!.pages.length, 2);
    expect(
      parsed.pages.first.text.replaceAll(RegExp(r'\s+'), ''),
      contains('营业收入为100.00万元'),
    );
    // ignore: avoid_print
    print(
      'NATIVE_PICKER platform=${Platform.operatingSystem} bytes=true parsed=true',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));
}
