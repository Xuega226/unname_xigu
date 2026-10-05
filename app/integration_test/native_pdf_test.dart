import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/services.dart';

import '../test/third_round_flow_test.dart' as flows;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  flows.registerThirdRoundFlows(native: true);
  testWidgets(
    'native PDF text, page rendering, rejected files and portable backup',
    (tester) async {
      final importer = PdfImportService();
      Future<Uint8List> fixture(String name) async =>
          (await rootBundle.load('integration_test/fixtures/$name.pdf')).buffer
              .asUint8List();
      final bytes = await fixture('fictional-report');
      final parsed = await importer.parse(bytes, 'fictional-report.pdf');
      expect(parsed.pages.length, 2);
      expect(
        parsed.pages.first.text.replaceAll(RegExp(r'\s+'), ''),
        contains('营业收入为100.00万元'),
      );
      final preview = await importer.renderPage(bytes, 1);
      expect(preview.take(4), [137, 80, 78, 71]);
      await expectLater(
        importer.parse(await fixture('scanned-report'), 'scan.pdf'),
        throwsA(isA<ServiceFailure>()),
      );
      await expectLater(
        importer.parse(await fixture('encrypted-report'), 'encrypted.pdf'),
        throwsA(isA<ServiceFailure>()),
      );
      await expectLater(
        importer.parse(Uint8List.fromList([1, 2, 3]), 'bad.pdf'),
        throwsA(isA<ServiceFailure>()),
      );
      final document = ReportDocument(
        id: 'native-doc',
        studyId: 's0',
        fileName: parsed.fileName,
        sha256: parsed.hash,
        title: '虚构测试公司财报',
        url: '',
        period: '2025 年度',
        start: '2025-01-01',
        end: '2025-12-31',
        disclosedAt: '2026-03-31',
        unit: '万元',
        importedAt: DateTime.now().toIso8601String(),
        pageCount: 2,
        pages: parsed.pages,
      );
      final original = WorkspaceData.empty().copyWith(
        studies: [WorkspaceData.demo().studies.first],
        documents: [document],
        sources: document.excerpts(),
      );
      final restored = WorkspaceData.decode(original.encode());
      expect(restored.documents.single.sha256, parsed.hash);
      expect(restored.sources.last.pageNumber, 2);
      expect(restored.encode(), isNot(contains('originalBase64')));
      final directory = await Directory.systemTemp.createTemp(
        'xigu-pdf-native-',
      );
      final files = LocalReportFileStore(directory);
      try {
        await files.put(parsed.hash, bytes);
        expect(await files.read(parsed.hash), bytes);
        expect(() => files.file('../escape'), throwsFormatException);
      } finally {
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await directory.resolveSymbolicLinks();
        if (!resolved.startsWith('$root${Platform.pathSeparator}')) {
          throw StateError('Temporary cleanup escaped its root');
        }
        await directory.delete(recursive: true);
      }
      // Only test-owned temporary files and fictional data; no user workspace.
      // ignore: avoid_print
      print(
        'NATIVE_PDF platform=${Platform.operatingSystem} pages=2 rendered=true rejectedScan=true rejectedEncrypted=true backup=true',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
