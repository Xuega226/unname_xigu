import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/report_widgets.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/review_widgets.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

const _sentinel = 'v03-offline-test-only-sentinel';
const _exportFixture = String.fromEnvironment('V03_EXPORT_FIXTURE');
const _importFixture = String.fromEnvironment('V03_IMPORT_FIXTURE');
const _task = '下期经营现金流是否恢复为正';
const _review = 'v0.3 离线复查：经营现金流为负，继续补证。';
const _fixtureText = '虚构测试公司2025年度合并报表，单位万元。营业收入为100.00万元，扣非净利润为8.00万元。';
const _fixtureCashText =
    '合并报表，单位：万元，数字为本期列。经营活动产生的现金流量净额为-20.00万元。期末货币资金为30.00万元，有息负债为50.00万元。';

// Only selection is deterministic on a device. Native parsing and rendering
// still call the production PDFium service with the bundled fictional PDF.
class _FixturePicker extends PdfImportService {
  _FixturePicker(this.bytes, {required this.native});
  final Uint8List bytes;
  final bool native;
  bool cancel = false, wrong = false;
  int parsed = 0, rendered = 0;

  @override
  Future<ParsedReport?> pick({void Function(int, int)? progress}) async {
    if (cancel) return null;
    final chosen = wrong
        ? Uint8List.fromList([
            ...bytes,
            ...utf8.encode('\n% different fixture'),
          ])
        : bytes;
    return parse(chosen, 'fictional-report.pdf', progress: progress);
  }

  @override
  Future<ParsedReport> parse(
    Uint8List bytes,
    String fileName, {
    void Function(int, int)? progress,
  }) async {
    parsed++;
    if (native) return super.parse(bytes, fileName, progress: progress);
    // Widget VMs have no path-provider/PDFium device plugins. Keep the disk
    // hash real and test UI behavior with the same known fictional values.
    progress?.call(2, 2);
    return ParsedReport(
      fileName: fileName,
      bytes: bytes,
      hash: crypto.sha256.convert(bytes).toString(),
      pages: const [
        ReportPage(number: 1, text: _fixtureText),
        ReportPage(number: 2, text: _fixtureCashText),
      ],
    );
  }

  @override
  Future<Uint8List> renderPage(Uint8List bytes, int number) async {
    rendered++;
    if (native) return super.renderPage(bytes, number);
    return raster.encodePng(raster.Image(width: 8, height: 8));
  }
}

class _OfflineFinancialTransport implements JsonTransport {
  int calls = 0;
  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    expect(uri, Uri.https('api.deepseek.com', '/chat/completions'));
    expect(headers['Authorization'], 'Bearer $_sentinel');
    final payload = jsonDecode(
      (body!['messages'] as List).last['content'] as String,
    ) as Map<String, dynamic>;
    expect(
      payload.keys,
      unorderedEquals(['company', 'start', 'end', 'scope', 'sources']),
    );
    final sources = (payload['sources'] as List).cast<Map>();
    expect(sources.length, 2);
    final source = sources.first, cashSource = sources.last;
    expect(source['pageNumber'], 1);
    expect(cashSource['pageNumber'], 2);
    expect(source['unit'], '万元');
    calls++;
    Map<String, dynamic> candidate(
      Map source,
      String metric,
      String label,
      String raw,
    ) => {
      'metric': metric,
      'label': label,
      'rawValue': raw,
      'unit': source['unit'],
      'start': payload['start'],
      'end': payload['end'],
      'scope': payload['scope'],
      'sourceId': source['id'],
      'quote': source['text'],
    };
    return {
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {
            'content': jsonEncode({
              'candidates': [
                candidate(source, 'revenue', '营业收入', '100.00'),
                candidate(
                  cashSource,
                  'operatingCash',
                  '经营活动产生的现金流量净额',
                  '-20.00',
                ),
              ],
              'missing': ['现金和有息负债尚未选入本次核验'],
              'notes': [],
            }),
          },
        },
      ],
    };
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('v0.3 local load/save/render did not finish');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, Finder finder, String text) async {
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
}

Future<void> _waitForPage(WidgetTester tester) async {
  // readReport loads from disk before it opens a modal; that interval has no
  // progress widget. Wait for the actual route before checking its content.
  for (var i = 0; i < 250; i++) {
    if (find.byType(PdfPageDialog).evaluate().isNotEmpty) {
      await _settle(tester);
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  fail('Disk-backed report page modal did not open');
}

Future<WorkspaceData> _read(
  WidgetTester tester,
  LocalWorkspaceStore store,
) async => (await tester.runAsync(store.load))!;

void _disabled(WidgetTester tester, String text) => expect(
  tester
      .widget<FilledButton>(find.widgetWithText(FilledButton, text))
      .onPressed,
  isNull,
);

void registerV03Acceptance({bool native = false}) {
  testWidgets(
    'v0.3 disk-backed PDF confirmation, financial proof and portable restore',
    (tester) async {
      if (!native) {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      } else if (Platform.isAndroid) {
        expect(
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
          lessThan(760),
          reason: 'Native Android must exercise phone layout',
        );
      }
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('xigu-v03-acceptance-'),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          final temporaryRoot = await Directory.systemTemp
              .resolveSymbolicLinks();
          final resolved = await root.resolveSymbolicLinks();
          if (!resolved.startsWith('$temporaryRoot${Platform.pathSeparator}')) {
            throw StateError('Acceptance cleanup escaped temporary root');
          }
          await root.delete(recursive: true);
        });
      });
      final first = LocalWorkspaceStore(Directory('${root.path}/first'));
      final second = LocalWorkspaceStore(Directory('${root.path}/second'));
      final firstFiles = LocalReportFileStore(
        Directory('${root.path}/first/reports'),
      );
      final secondFiles = LocalReportFileStore(
        Directory('${root.path}/second/reports'),
      );
      const study = Study(
        id: 'v03-fixture-study',
        code: 'TEST:000001',
        name: '虚构测试公司',
        business: '虚构资料验收',
        thesis: '核对经营现金流',
        counterEvidence: '',
        reviewCondition: '需要持续补充现金流证据',
        source: '',
        updatedAt: '2026-10-04',
      );
      final initial = WorkspaceData.empty().copyWith(
        studies: [study],
        cash: 1000,
        deposits: 2000,
        lossBudget: .2,
        priceDate: '2026-09-30',
        holdings: const [
          Holding(
            id: 'v03-fixture-holding',
            code: 'TEST:000001',
            name: '虚构测试公司',
            industry: '虚构行业',
            quantity: 100,
            price: 11.5,
          ),
        ],
      );
      await tester.runAsync(() async {
        await first.save(initial);
        await second.save(WorkspaceData.empty());
      });
      final asset = (await tester.runAsync(
        () => rootBundle.load('integration_test/fixtures/fictional-report.pdf'),
      ))!;
      final bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final picker = _FixturePicker(bytes, native: native);
      final transport = _OfflineFinancialTransport();
      Widget app(LocalWorkspaceStore store, LocalReportFileStore files) =>
          LianghuaApp(
            store: store,
            reportFiles: files,
            pdfImporter: picker,
            ai: DeepSeekService(transport: transport),
            credentials: MemoryCredentialStore(
              const AiSettings(key: _sentinel),
            ),
          );
      Future<void> reopen(
        LocalWorkspaceStore store,
        LocalReportFileStore files,
      ) async {
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
        await tester.pumpWidget(app(store, files));
        await _settle(tester);
      }

      await reopen(first, firstFiles);
      await _tap(tester, find.text('公司研究').last);
      await _tap(tester, find.textContaining('资料与财务（').first);
      await _tap(tester, find.text('导入财报 PDF'));
      picker.cancel = true;
      await _tap(tester, find.text('选择 PDF 文件'));
      expect((await _read(tester, first)).encode(), initial.encode());
      _disabled(tester, '保存选页与原文件');
      picker.cancel = false;
      await _tap(tester, find.text('选择 PDF 文件'));
      expect((await _read(tester, first)).documents, isEmpty);
      expect(
        await tester.runAsync(
          () => firstFiles.read(crypto.sha256.convert(bytes).toString()),
        ),
        isNull,
      );
      final fields = find.byType(TextFormField);
      for (final field in [
        (2, '2025年度'),
        (3, '2025-01-01'),
        (4, '2025-12-31'),
        (5, '2026-03-31'),
      ]) {
        await _enter(tester, fields.at(field.$1), field.$2);
      }
      await _tap(tester, find.byType(DropdownButtonFormField<String>));
      await _tap(tester, find.text('万元').last);
      await _tap(tester, find.byType(Checkbox).first);
      await _tap(tester, find.byType(Checkbox).at(1));
      _disabled(tester, '保存选页与原文件');
      expect((await _read(tester, first)).sources, isEmpty);
      await _tap(tester, find.byType(CheckboxListTile));
      await _tap(tester, find.text('保存选页与原文件'));
      final imported = await _read(tester, first);
      final doc = imported.documents.single, source = imported.sources.first;
      expect(doc.pages.map((page) => page.number), [1, 2]);
      expect(doc.pageCount, 2);
      expect(source.documentId, doc.id);
      expect(source.studyId, study.id);
      expect(source.period, doc.period);
      expect(source.disclosedAt, doc.disclosedAt);
      expect(await tester.runAsync(() => firstFiles.read(doc.sha256)), bytes);
      await _tap(tester, find.text('AI 提取财务候选值'));
      await _tap(tester, find.byType(CheckboxListTile).last);
      await _tap(tester, find.text('发送选定资料并提取'));
      expect(transport.calls, 1);
      expect((await _read(tester, first)).encode(), imported.encode());
      _disabled(tester, '保存已核验财务记录');
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, '营业收入：100.00 万元'),
      );
      _disabled(tester, '保存已核验财务记录');
      await _tap(
        tester,
        find.widgetWithText(CheckboxListTile, '经营现金流：-20.00 万元'),
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, '经营现金流：-20.00 万元'),
            )
            .value,
        isTrue,
        reason: 'Cash-flow candidate must remain selected before confirmation',
      );
      await _tap(tester, find.byType(CheckboxListTile).last);
      await _tap(tester, find.text('保存已核验财务记录'));
      final accepted = await _read(tester, first),
          financial = accepted.financials.single;
      expect(financial.revenue, 100);
      expect(financial.operatingCash, -20);
      expect(financial.adjustedProfit, isNull);
      expect(financial.cash, isNull);
      expect(financial.debt, isNull);
      expect(
        financial.evidence.keys,
        unorderedEquals(['revenue', 'operatingCash']),
      );
      expect(financial.evidence['operatingCash']!.rawValue, '-20.00');
      expect(
        financial.evidence['operatingCash']!.sourceId,
        imported.sources.last.id,
      );
      expect(financial.evidence['revenue']!.sourceId, source.id);
      expect(financial.start, doc.start);
      expect(financial.end, doc.end);
      expect(transport.calls, 1);
      await _tap(tester, find.text('关闭'));
      await _tap(tester, find.text('复查计划与清单').first);
      await _enter(tester, find.byType(TextFormField), '2026-11-04');
      await _tap(tester, find.text('添加待验证条件'));
      final taskFields = find.descendant(
        of: find.byType(ReviewTaskDialog),
        matching: find.byType(TextFormField),
      );
      await _enter(tester, taskFields.first, _task);
      await _enter(tester, taskFields.last, '当前原文经营现金流为负20.00万元');
      await _tap(tester, find.byType(CheckboxListTile).first);
      await _tap(tester, find.text('保存此条件'));
      await _tap(tester, find.text('保存复查计划'));
      final planned = await _read(tester, first);
      expect(planned.studyVersions.single.study.nextReviewAt, '');
      expect(planned.studies.single.nextReviewAt, '2026-11-04');
      expect(planned.studies.single.reviewTasks.single.sourceIds, [source.id]);
      await _tap(tester, find.text('研究版本对照').first);
      expect(find.text('下次复查日期'), findsOneWidget);
      expect(find.text('待验证清单'), findsOneWidget);
      await _tap(tester, find.text('关闭'));
      await _tap(tester, find.text('复查日志').last);
      await _tap(tester, find.text('记录一次复查'));
      await _enter(tester, find.byType(TextFormField).last, _review);
      await _tap(tester, find.text('保存'));
      await _tap(tester, find.byTooltip('数据与设置'));
      await _tap(tester, find.text('导出备份'));
      final backup = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      final exported = WorkspaceData.decode(backup);
      expect(exported.toJson()['schemaVersion'], 3);
      expect(backup, isNot(contains(_sentinel)));
      expect(backup, isNot(contains('originalBase64')));
      expect(exported.reviews.last.text, _review);
      if (_exportFixture.isNotEmpty) {
        await tester.runAsync(
          () => File(_exportFixture).writeAsString(backup, flush: true),
        );
      }
      await _tap(tester, find.text('关闭'));
      await reopen(LocalWorkspaceStore(first.directory), firstFiles);
      expect((await _read(tester, first)).encode(), exported.encode());
      await _tap(tester, find.text('公司研究').last);
      await _tap(tester, find.text('研究版本对照').first);
      expect(find.text('待验证清单'), findsOneWidget);
      await _tap(tester, find.text('关闭'));

      final incoming = _importFixture.isEmpty
          ? backup
          : (await tester.runAsync(() => File(_importFixture).readAsString()))!;
      final expected = WorkspaceData.decode(incoming);
      await reopen(second, secondFiles);
      await _tap(tester, find.byTooltip('数据与设置'));
      await _tap(tester, find.text('导入备份'));
      await tester.enterText(find.byType(TextField), incoming);
      await _tap(tester, find.text('检查并导入'));
      expect((await _read(tester, second)).studies, isEmpty);
      await _tap(tester, find.text('确认'));
      await reopen(LocalWorkspaceStore(second.directory), secondFiles);
      final restored = await _read(tester, second);
      expect(restored.encode(), expected.encode());
      expect(restored.assets, 2150);
      expect(restored.profitRate, closeTo(.075, 1e-12));
      expect(restored.stressLoss(.3), closeTo(1150 / 2150 * .3, 1e-12));
      expect(restored.studyVersions.length, 1);
      expect(restored.studies.single.reviewTasks.single.text, _task);
      expect(restored.financials.single.operatingCash, -20);
      final restoredDoc = restored.documents.single;
      expect(
        await tester.runAsync(() => secondFiles.read(restoredDoc.sha256)),
        isNull,
      );
      await _tap(tester, find.text('公司研究').last);
      await _tap(tester, find.textContaining('资料与财务（').first);
      await _tap(tester, find.text('查看原页与选页原文'));
      await _waitForPage(tester);
      expect(find.textContaining('本机尚无原 PDF'), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText).last).data,
        restoredDoc.pages.first.text,
      );
      await _tap(tester, find.text('关闭').last);
      picker.wrong = true;
      await _tap(tester, find.text('重新关联原 PDF'));
      expect(find.textContaining('SHA-256 不一致'), findsOneWidget);
      expect(
        await tester.runAsync(() => secondFiles.read(restoredDoc.sha256)),
        isNull,
      );
      expect((await _read(tester, second)).encode(), restored.encode());
      picker.wrong = false;
      await _tap(tester, find.text('重新关联原 PDF'));
      expect(
        await tester.runAsync(() => secondFiles.read(restoredDoc.sha256)),
        bytes,
      );
      await _tap(tester, find.text('查看原页与选页原文'));
      await _waitForPage(tester);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.textContaining('原页显示失败'), findsNothing);
      expect(picker.rendered, greaterThan(0));
      await _tap(tester, find.text('提取文字'));
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText).last).data,
        restoredDoc.pages.first.text,
      );
      await _tap(tester, find.text('关闭').last);
      await _tap(tester, find.text('关闭'));
      expect((await _read(tester, second)).encode(), restored.encode());
      await _tap(tester, find.text('复查日志').last);
      expect(find.text(_review), findsOneWidget);
      // ignore: avoid_print
      print(
        'V03_ACCEPTANCE platform=${Platform.operatingSystem} nativePdf=$native '
        'schema=3 documents=1 sources=2 financials=1 history=1 '
        'reviewTasks=1 assets=${restored.assets} profit=${restored.profitRate} '
        'textWithoutPdf=true wrongRelinkRejected=true originalRendered=true '
        'exchange=${_importFixture.isNotEmpty}',
      );
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
