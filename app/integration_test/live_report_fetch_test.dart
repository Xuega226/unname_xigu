// Explicit public-network probe; no AI credentials or user workspace access.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/report_fetch.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/reports.dart';

String day(DateTime date) => date.toIso8601String().substring(0, 10);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('official annual catalogue and downloaded PDF native parsing', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('RUN_PUBLIC_REPORT_PROBE')) return;
    final service = ReportFetchService();
    final importer = PdfImportService();
    final output = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'userWorkspaceModified': false,
      'aiCalled': false,
      'companies': <Map<String, dynamic>>[],
      'downloads': <Map<String, dynamic>>[],
    };
    for (final security in [('SH', '600660'), ('SZ', '000001')]) {
      final result = await service.search(security.$1, security.$2);
      expect(result.code, security.$2);
      expect(result.exchange, security.$1);
      expect(result.reports, isNotEmpty);
      expect(result.missingYears, isEmpty);
      (output['companies'] as List).add({
        'name': result.companyName,
        'code': result.code,
        'exchange': result.exchange,
        'missingYears': result.missingYears,
        'warnings': result.warnings,
        'reports': result.reports
            .map(
              (r) => {
                'id': r.id,
                'title': r.title,
                'year': r.year,
                'disclosedAt': day(r.disclosedAt),
                'url': r.url.toString(),
                'sourceUrl': r.sourceUrl,
                'isRevision': r.isRevision,
              },
            )
            .toList(),
      });
      if (security.$1 != 'SH') continue;
      final toRead = Platform.isWindows
          ? result.reports.where((r) => !r.isRevision).toList()
          : [result.reports.first];
      for (final announcement in toRead) {
        final bytes = await service.download(announcement);
        final parsed = await importer.parse(bytes, announcement.fileName);
        expect(parsed.pages, isNotEmpty);
        final page = parsed.pages.firstWhere((p) => p.text.trim().isNotEmpty);
        final image = await importer.renderPage(bytes, page.number);
        expect(image.take(4), [137, 80, 78, 71]);
        final document = ReportDocument.fromJson({
          'id': 'public-${announcement.id}',
          'studyId': 'public-study',
          'fileName': parsed.fileName,
          'sha256': parsed.hash,
          'title': announcement.title,
          'url': announcement.url.toString(),
          'period': '${announcement.year} 年度',
          'start': day(announcement.start),
          'end': day(announcement.end),
          'disclosedAt': day(announcement.disclosedAt),
          'unit': '不适用',
          'importedAt': DateTime.now().toIso8601String(),
          'pageCount': parsed.pages.length,
          'pages': [page.toJson()],
          'origin': ReportOrigin(
            announcementId: announcement.id,
            code: announcement.code,
            exchange: announcement.exchange,
            companyName: announcement.companyName,
            title: announcement.title,
            downloadUrl: announcement.url.toString(),
            catalogueUrl: announcement.sourceUrl,
            start: day(announcement.start),
            end: day(announcement.end),
            disclosedAt: day(announcement.disclosedAt),
            fetchedAt: DateTime.now().toIso8601String(),
            isRevision: announcement.isRevision,
          ).toJson(),
        });
        final study = Study(
          id: 'public-study',
          code: announcement.code,
          name: announcement.companyName,
          business: '',
          thesis: '',
          counterEvidence: '',
          reviewCondition: '',
          source: '',
          updatedAt: DateTime.now().toIso8601String(),
        );
        final workspace = WorkspaceData.empty().copyWith(
          studies: [study],
          documents: [document],
          sources: document.excerpts(),
        );
        expect(
          WorkspaceData.decode(workspace.encode())
              .documents
              .single
              .origin!
              .announcementId,
          announcement.id,
        );
        (output['downloads'] as List).add({
          'id': announcement.id,
          'year': announcement.year,
          'bytes': bytes.length,
          'pages': parsed.pages.length,
          'sha256': parsed.hash,
          'nativeRaster': true,
          'backup': true,
        });
        if (Platform.isWindows) {
          final directory = Directory('../artifacts');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/public-report-${announcement.year}-v0.4.pdf',
          ).writeAsBytes(bytes);
          if (announcement == toRead.first) {
            await File('${directory.path}/public-report-native-v0.4.png')
                .writeAsBytes(image);
          }
        }
      }
    }
    if (Platform.isWindows) {
      await File('../artifacts/report-fetch-live-v0.4-windows.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(output));
    }
    // ignore: avoid_print
    print('PUBLIC_REPORT_PROBE ${jsonEncode(output)}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
