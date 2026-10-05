// Explicit opt-in, paid live call. Uses the saved Windows credential and an
// official public report supplied locally, never the user's research workspace.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/financial_extraction.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/services.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'official PDF native parsing and live financial candidate grounding',
    (tester) async {
      final output = <String, dynamic>{
        'workspaceModified': false,
        'sourceUrl': 'https://www.fuyaogroup.com/upfiles/investor/202603/1773747544359.pdf',
        'selectedPdfPage': 8,
      };
      try {
        final path = const String.fromEnvironment('PUBLIC_REPORT_PATH');
        if (!Platform.isWindows || path.isEmpty) {
          throw ServiceFailure('请在 Windows 显式指定公开测试财报路径');
        }
        final bytes = await File(path).readAsBytes();
        final importer = PdfImportService();
        final parsed = await importer.parse(bytes, '福耀玻璃2025年年度报告.pdf');
        expect(parsed.pages.length, 189);
        final page = parsed.pages[7];
        expect(page.text, contains('45,787,435,563'));
        final original = await importer.renderPage(bytes, 8);
        await File('../artifacts/fuyao-page8-native.png')
            .writeAsBytes(original);
        final doc = ReportDocument(
          id: 'public-doc',
          studyId: 'public-study',
          fileName: parsed.fileName,
          sha256: parsed.hash,
          title: '福耀玻璃2025年年度报告',
          url: output['sourceUrl'] as String,
          period: '2025年度',
          start: '2025-01-01',
          end: '2025-12-31',
          disclosedAt: '2026-03-18',
          unit: '元',
          importedAt: DateTime.now().toIso8601String(),
          pageCount: 189,
          pages: [page],
        );
        final sources = doc.excerpts();
        final settings = await SecureCredentialStore().read();
        if (settings.key.isEmpty) throw ServiceFailure('本机应用安全存储中尚无密钥');
        final timer = Stopwatch()..start();
        final batch = await DeepSeekService().extractFinancials(
          key: settings.key,
          model: settings.model,
          company: '福耀玻璃 600660',
          sources: sources,
          start: doc.start,
          end: doc.end,
          scope: '合并',
        );
        timer.stop();
        output['model'] = settings.model;
        output['milliseconds'] = timer.elapsedMilliseconds;
        output['candidates'] = batch.candidates
            .map(
              (c) => {
                'metric': c.metric,
                'value': c.value,
                'proof': c.proof.toJson(),
                'error': c.error(sources, doc.start, doc.end, '合并'),
              },
            )
            .toList();
        output['missing'] = batch.missing;
        output['notes'] = batch.notes;
        const expected = {
          'revenue': 45787435563.0,
          'adjustedProfit': 9164684348.0,
          'operatingCash': 12055090552.0,
        };
        final valid = batch.candidates
            .where(
              (c) =>
                  c.error(sources, doc.start, doc.end, '合并') == null &&
                  expected[c.metric] == c.value,
            )
            .toList();
        expect(valid.any((c) => c.metric == 'revenue'), true);
        expect(valid.any((c) => c.metric == 'operatingCash'), true);
        final record = confirmFinancialCandidates(
          studyId: 'public-study',
          candidates: valid,
          sources: sources,
          start: doc.start,
          end: doc.end,
          scope: '合并',
          basis: '原披露',
        );
        final study = Study(
          id: 'public-study',
          code: '600660',
          name: '福耀玻璃',
          business: '',
          thesis: '',
          counterEvidence: '',
          reviewCondition: '',
          source: doc.url,
          updatedAt: dateToday(),
        );
        final data = WorkspaceData.empty().copyWith(
          studies: [study],
          documents: [doc],
          sources: sources,
          financials: [record],
        );
        final restored = WorkspaceData.decode(data.encode());
        await File('../artifacts/public-research-v0.3.json')
            .writeAsString(restored.encode());
        expect(restored.financials.single.debt, isNull);
        expect(restored.financials.single.cash, isNull);
        output['acceptedMetrics'] = valid.map((c) => c.metric).toList();
        output['publicPdfPageCount'] = parsed.pages.length;
        output['backupRestored'] = true;
        output['status'] = 'passed';
      } on ServiceFailure catch (e) {
        output['status'] = 'failed';
        output['error'] = e.message;
      } catch (_) {
        output['status'] = 'failed';
        output['error'] = '公开财报提取或候选校验未通过，敏感细节未输出';
      }
      final dir = Directory('../artifacts');
      await dir.create(recursive: true);
      await File('${dir.path}/deepseek-financial-v0.3.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(output));
      // ignore: avoid_print
      print(
        'LIVE_FINANCIAL status=${output['status']} accepted=${output['acceptedMetrics']} latency=${output['milliseconds']}ms error=${output['error'] ?? 'none'}',
      );
      expect(output['status'], 'passed');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
