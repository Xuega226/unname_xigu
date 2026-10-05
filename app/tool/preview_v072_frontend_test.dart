// Offline visual QA: fictional workspace, memory stores and disabled transports.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/data_foundation.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/report_fetch.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

import '../test/support/v07_fixture.dart';

class _OfflineJson implements JsonTransport {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    calls++;
    throw StateError('Frontend preview must not make network requests');
  }
}

class _OfflineReports implements ReportFetchTransport {
  int calls = 0;
  @override
  Future<ReportFetchResponse> request(
    Uri uri, {
    Map<String, String>? form,
  }) async {
    calls++;
    throw StateError('Frontend preview must not fetch reports');
  }
}

void main() {
  testWidgets('preview simplified frontend on desktop and phone', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final font in [
        ('PreviewSans', 'C:/Windows/Fonts/msyh.ttc'),
        (
          'MaterialIcons',
          '../.tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ),
      ]) {
        await (FontLoader(font.$1)..addFont(
              Future.value(
                ByteData.sublistView(await File(font.$2).readAsBytes()),
              ),
            ))
            .load();
      }
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final entry in [
      ('desktop', const Size(1280, 1000), 1.0),
      ('phone', const Size(390, 844), 1.0),
      ('phone-large-text', const Size(390, 844), 2.0),
    ]) {
      tester.view.physicalSize = entry.$2;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = entry.$3;
      final key = GlobalKey();
      final json = _OfflineJson(), reports = _OfflineReports();
      final fixture = v07Fixture();
      final study = fixture.studies.first.copyWith(
        business:
            '虚构制造提供工业设备及配套维护服务。以下业务与金额均为虚构验收资料。'
            '实际研究需要核对年度报告中的产品构成、客户集中度及收入确认口径。',
        thesis:
            '等待原文核验后的人工判断。用下一次年报验证收入、扣非利润与经营现金流'
            '是否同向改善，并检查增长能否持续；规则命中只是研究线索。',
        counterEvidence:
            '下一年盈利是否持续仍需验证。客户需求下滑、回款周期延长与成本上升'
            '可能影响判断，缺失资料应持续补充。',
      );
      final document = ReportDocument(
        id: 'frontend-preview-report',
        studyId: study.id,
        fileName: '虚构制造2025年报.pdf',
        sha256: 'a' * 64,
        title: '虚构制造2025年报',
        url: '',
        period: '2025年度',
        start: '2025-01-01',
        end: '2025-12-31',
        disclosedAt: '2026-04-01',
        unit: '万元',
        importedAt: '2026-10-05T00:00:00+08:00',
        pageCount: 1,
        pages: const [ReportPage(number: 1, text: '虚构财报选页，仅用于界面验收；不代表真实公司公告。')],
      );
      final data = fixture.copyWith(
        studies: [study],
        documents: [document],
        sources: [...fixture.sources, ...document.excerpts()],
      );
      final store = MemoryWorkspaceStore(data);
      final credentials = MemoryCredentialStore();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: LianghuaApp(
            store: store,
            fontFamily: 'PreviewSans',
            credentials: credentials,
            brokerSettings: MemoryBrokerSettingsStore(),
            reportFiles: MemoryReportFileStore(),
            market: MarketService(transport: json),
            ai: DeepSeekService(transport: json),
            historyService: MarketHistoryService(transport: json),
            reportFetcher: ReportFetchService(transport: reports),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/branding/unnameko-stock-icon-v2.png'),
          tester.element(find.byType(WorkspaceScreen)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(WorkspaceScreen)))
            .scale(10),
        10 * entry.$3,
      );
      await _capture(tester, key, '${entry.$1}-overview');

      await _tap(tester, find.text('公司研究').last);
      await tester.ensureVisible(find.text('${study.name} · ${study.code}'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await _capture(tester, key, '${entry.$1}-research-summary');

      await _tap(tester, find.byKey(ValueKey('study-full-${study.id}')));
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(study.business),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _capture(tester, key, '${entry.$1}-research-full');
      await _tap(tester, find.text('关闭'));

      await _tap(tester, find.textContaining('资料与财务（').first);
      expect(find.text('资料原文'), findsOneWidget);
      expect(find.text('财务核验'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, key, '${entry.$1}-evidence');

      await _tap(tester, find.text('财务核验'));
      expect(find.text('核对财务字段'), findsOneWidget);
      expect(find.text('AI 提取财务候选值'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, key, '${entry.$1}-financial');
      await _tap(tester, find.text('关闭'));
      expect(store.data!.encode(), data.encode());
      expect(credentials.settings.key, isEmpty);
      expect(json.calls, 0);
      expect(reports.calls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../docs/preview-v0.7.2');
    await directory.create(recursive: true);
    await File('${directory.path}/frontend-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
