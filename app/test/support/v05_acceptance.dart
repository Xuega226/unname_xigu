// Fictional files and isolated directories only. The native chooser is injected;
// parsing, workspace persistence, foreground polling and backup UI are real.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/report_import.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/storage.dart';

const _exportFixture = String.fromEnvironment('V05_EXPORT_FIXTURE');
const _importFixture = String.fromEnvironment('V05_IMPORT_FIXTURE');
const _v06ExportFixture = String.fromEnvironment('V06_EXPORT_FIXTURE');
const _v06ImportFixture = String.fromEnvironment('V06_IMPORT_FIXTURE');
const _sentinel = 'v05-offline-test-only-sentinel';
const _autoLabel = '应用在前台时，每 15 秒自动读取同一文件';
const _reviewLabel = '已核对账户、完整持仓、现金和估值日期';

class _DiskPicker extends BrokerImportService {
  _DiskPicker(this.file);
  final File file;
  @override
  Future<SelectedPortfolioFile?> pick() async => SelectedPortfolioFile(
    bytes: await readPortfolioFile(file.path),
    name: file.uri.pathSegments.last,
    path: file.path,
  );
}

class _DiskSettings extends BrokerSettingsStore {
  _DiskSettings(this.file);
  final File file;
  @override
  Future<BrokerFileSettings?> read() async => await file.exists()
      ? BrokerFileSettings.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        )
      : null;
  @override
  Future<void> write(BrokerFileSettings? value) async {
    if (value == null) {
      if (await file.exists()) await file.delete();
    } else {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(value.toJson()), flush: true);
    }
  }
}

String _snapshot({int quantity = 100, int cash = 5000, int hour = 9}) =>
    jsonEncode({
      'snapshotVersion': 1,
      'complete': true,
      'currency': 'CNY',
      'accountType': 'cash_equity',
      'broker': '虚构验收券商',
      'accountAlias': '虚构主账户',
      'priceDate': '2026-10-01',
      'capturedAt': '2026-10-01T${hour.toString().padLeft(2, '0')}:00:00+08:00',
      'cash': cash,
      'holdings': [
        {'code': '600001', 'name': '虚构测试公司', 'quantity': quantity, 'price': 12},
        {'code': '000001', 'name': '虚构第二证券', 'quantity': 50, 'price': 8},
      ],
    });

WorkspaceData _seed(String hash) {
  const origin = ReportOrigin(
    announcementId: 'v05fictional',
    code: '600001',
    exchange: 'SH',
    companyName: '虚构测试公司',
    title: '2025年年度报告（修订版）',
    downloadUrl:
        'https://static.cninfo.com.cn/finalpage/2026-03-31/v05fictional.pdf',
    catalogueUrl: 'https://www.cninfo.com.cn/new/hisAnnouncement/query',
    start: '2025-01-01',
    end: '2025-12-31',
    disclosedAt: '2026-03-31',
    fetchedAt: '2026-10-01T00:00:00Z',
    isRevision: true,
  );
  final document = ReportDocument(
    id: 'v05-document',
    studyId: 'v05-study',
    fileName: 'fictional-report.pdf',
    sha256: hash,
    title: origin.title,
    url: origin.downloadUrl,
    period: '2025年度',
    start: origin.start,
    end: origin.end,
    disclosedAt: origin.disclosedAt,
    unit: '万元',
    importedAt: origin.fetchedAt,
    pageCount: 2,
    pages: const [ReportPage(number: 2, text: '虚构经营活动产生的现金流量净额为-20.00万元。')],
    origin: origin,
  );
  final source = document.excerpts().single;
  final study = Study(
    id: 'v05-study',
    code: '600001',
    name: '虚构测试公司',
    business: '虚构经营业务',
    thesis: '持续核对现金流',
    counterEvidence: '现金流为负',
    reviewCondition: '下一次年报核验',
    source: origin.downloadUrl,
    updatedAt: '2026-10-01',
    nextReviewAt: '2026-11-01',
    reviewTasks: [
      ReviewTask(
        id: 'v05-task',
        text: '经营现金流恢复了吗',
        note: '保持待验证',
        sourceIds: [source.id],
      ),
    ],
  );
  return WorkspaceData.empty().copyWith(
    cash: 1000,
    deposits: 10000,
    withdrawals: 500,
    lossBudget: .2,
    priceDate: '2026-09-30',
    holdings: const [
      Holding(
        id: 'v05-existing-holding',
        code: '600001',
        name: '虚构测试公司',
        industry: '虚构行业',
        quantity: 20,
        price: 11,
      ),
    ],
    studies: [study],
    documents: [document],
    sources: [source],
    financials: [
      FinancialRecord(
        id: 'v05-financial',
        studyId: study.id,
        sourceId: source.id,
        start: origin.start,
        end: origin.end,
        disclosedAt: origin.disclosedAt,
        unit: '万元',
        revenue: 100,
        operatingCash: -20,
        scope: '合并',
        basis: '原披露',
      ),
    ],
    studyVersions: [
      StudyVersion(
        id: 'v05-version',
        study: study.copyWith(thesis: '旧版虚构判断'),
        createdAt: '2026-09-30T00:00:00Z',
        reason: '虚构历史',
      ),
    ],
    reviews: const [
      ReviewEntry(
        id: 'v05-review',
        company: '虚构测试公司',
        text: '保留原始复查记录',
        createdAt: '2026-10-01T00:00:00Z',
      ),
    ],
    watchlist: [
      WatchCompany(
        id: 'v05-watch',
        code: '600001',
        exchange: 'SH',
        name: '虚构测试公司',
        industry: '虚构行业',
        source: 'https://www.cninfo.com.cn/',
        fetchedAt: origin.fetchedAt,
      ),
    ],
  );
}

void _preserved(WorkspaceData data, WorkspaceData initial) {
  final actual = data.toJson(), expected = initial.toJson();
  for (final key in [
    'isDemo',
    'deposits',
    'withdrawals',
    'lossBudget',
    'studies',
    'watchlist',
    'sources',
    'financials',
    'documents',
    'studyVersions',
  ]) {
    expect(
      actual[key],
      expected[key],
      reason: '$key survives a portfolio update',
    );
  }
  expect(
    data.reviews.firstWhere((r) => r.id == 'v05-review').toJson(),
    initial.reviews.firstWhere((r) => r.id == 'v05-review').toJson(),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final awaitingCsvDetails = find.text('核对 CSV 的账户信息').evaluate().isNotEmpty;
    final awaitingEncoding = find.text('核对文件编码').evaluate().isNotEmpty;
    final awaitingMapping = find.text('核对 CSV 列映射').evaluate().isNotEmpty;
    final indeterminateCircular = tester
        .widgetList<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .any((indicator) => indicator.value == null);
    final indeterminateLinear = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .any((indicator) => indicator.value == null);
    if (!indeterminateCircular &&
        !indeterminateLinear &&
        (awaitingCsvDetails ||
            awaitingEncoding ||
            awaitingMapping ||
            find.text('正在读取…').evaluate().isEmpty)) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('isolated disk operation did not finish');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await _settle(tester);
}

Future<WorkspaceData> _read(
  WidgetTester tester,
  LocalWorkspaceStore store,
) async => (await tester.runAsync(store.load))!;

Future<void> _waitUntil(
  WidgetTester tester,
  String operation,
  Future<bool> Function() ready,
) async {
  // Busy indicators cover workspace saves, but the subsequent binding write
  // and foreground file checks intentionally do not show a modal spinner.
  // Wait for their observable result while allowing real disk IO to progress.
  for (var i = 0; i < 250; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final complete = await tester.runAsync(() async {
      try {
        return await ready();
      } on FileSystemException {
        // A save may be replacing its temporary file at this polling instant.
        return false;
      } on FormatException {
        // The injected disk settings store can still be flushing its JSON.
        return false;
      }
    });
    if (complete == true) {
      await _settle(tester);
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('$operation did not reach its observable result');
}

void registerV05Acceptance({bool native = false, bool v06 = false}) {
  final version = v06 ? 'v0.6' : 'v0.5';
  final exportFixture = v06 ? _v06ExportFixture : _exportFixture;
  final importFixture = v06 ? _v06ImportFixture : _importFixture;
  testWidgets(
    '$version isolated disk portfolio review, foreground sync and portable backup',
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
        );
      }
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp(
          v06 ? 'xigu-v06-acceptance-' : 'xigu-v05-acceptance-',
        ),
      ))!;
      addTearDown(() async {
        await tester.runAsync(() async {
          final temp = await Directory.systemTemp.resolveSymbolicLinks();
          final resolved = await root.resolveSymbolicLinks();
          if (!resolved.startsWith('$temp${Platform.pathSeparator}')) {
            throw StateError('Cleanup escaped temporary root');
          }
          await root.delete(recursive: true);
        });
      });
      final first = LocalWorkspaceStore(Directory('${root.path}/first'));
      final second = LocalWorkspaceStore(Directory('${root.path}/second'));
      final csvStore = LocalWorkspaceStore(Directory('${root.path}/csv'));
      final settings = _DiskSettings(File('${root.path}/binding.json'));
      final file = File('${root.path}/fictional-snapshot.json');
      final csv = File('${root.path}/fictional.csv');
      final asset = (await tester.runAsync(
        () => rootBundle.load('integration_test/fixtures/fictional-report.pdf'),
      ))!;
      final pdf = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final initial = _seed(crypto.sha256.convert(pdf).toString());
      final reportFiles = LocalReportFileStore(
        Directory('${root.path}/first/reports'),
      );
      await tester.runAsync(() async {
        await first.save(initial);
        await second.save(WorkspaceData.empty());
        await csvStore.save(WorkspaceData.empty());
        await reportFiles.put(initial.documents.single.sha256, pdf);
        await file.writeAsString(_snapshot(), flush: true);
        if (v06) {
          await csv.writeAsBytes(
            const GbkCodec().encode(
              '编号;简称;总股数;现价\n000001;虚构第二证券;30;8\n600001;虚构测试公司;60;12',
            ),
            flush: true,
          );
        } else {
          await csv.writeAsString(
            '证券代码,证券名称,持仓数量,市价\n000001,虚构第二证券,30,8\n600001,虚构测试公司,60,12',
            flush: true,
          );
        }
      });
      Widget app(
        LocalWorkspaceStore store,
        File selected,
        BrokerSettingsStore binding,
      ) => LianghuaApp(
        store: store,
        brokerImporter: _DiskPicker(selected),
        brokerSettings: binding,
        reportFiles: LocalReportFileStore(
          Directory('${store.directory.path}/reports'),
        ),
        credentials: MemoryCredentialStore(const AiSettings(key: _sentinel)),
      );
      Future<void> reopen(
        LocalWorkspaceStore store,
        File selected,
        BrokerSettingsStore binding,
      ) async {
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
        await tester.pumpWidget(app(store, selected, binding));
        await _settle(tester);
        await _waitUntil(
          tester,
          'workspace reopen',
          () async => find.byTooltip('数据与设置').evaluate().isNotEmpty,
        );
      }

      Future<void> importFile() async {
        await _tap(tester, find.text('导入券商持仓').last);
        await _tap(tester, find.text('选择持仓文件'));
      }

      await reopen(first, file, settings);
      await _tap(tester, find.text('账户风控').last);
      await importFile();
      expect(
        find.textContaining('600001 虚构测试公司'),
        findsWidgets,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入'))
            .onPressed,
        isNull,
      );
      expect((await _read(tester, first)).encode(), initial.encode());
      expect(await tester.runAsync(settings.read), isNull);
      await _tap(tester, find.text('取消').last);
      expect((await _read(tester, first)).encode(), initial.encode());
      await importFile();
      if (Platform.isWindows) {
        await _tap(tester, find.text(_autoLabel));
      } else {
        expect(find.text(_autoLabel), findsNothing);
      }
      await _tap(tester, find.text(_reviewLabel));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入'))
            .onPressed,
        isNull,
        reason: 'Existing deposits and withdrawals require account ownership confirmation',
      );
      expect((await _read(tester, first)).encode(), initial.encode());
      await _tap(
        tester,
        find.byKey(const ValueKey('broker-source-confirmation')),
      );
      await _tap(tester, find.text('确认导入'));
      var imported = await _read(tester, first);
      expect(imported.cash, 5000);
      expect(imported.priceDate, '2026-10-01');
      expect(imported.holdings.length, 2);
      expect(
        imported.holdings.firstWhere((h) => h.code == '600001').quantity,
        100,
      );
      expect(imported.holdings.firstWhere((h) => h.code == '600001').price, 12);
      expect(imported.assets, 6600);
      expect(imported.principal, 9500);
      _preserved(imported, initial);
      expect(imported.portfolioImport!.format, 'json');
      if (Platform.isWindows) {
        await _waitUntil(tester, 'binding saved', () async {
          final saved = await settings.read();
          return saved?.path == file.path &&
              find.textContaining('已绑定 ·').evaluate().isNotEmpty;
        });
        expect((await tester.runAsync(settings.read))!.path, file.path);
        await reopen(
          LocalWorkspaceStore(first.directory),
          file,
          _DiskSettings(settings.file),
        );
        await _tap(tester, find.text('账户风控').last);
        await _waitUntil(
          tester,
          'binding restored after reopen',
          () async => find.text('检查文件更新').evaluate().isNotEmpty,
        );
        expect(find.text('检查文件更新'), findsOneWidget);
        final before = imported.encode();
        await _tap(tester, find.text('检查文件更新'));
        await _waitUntil(
          tester,
          'unchanged file checked',
          () async => find.textContaining('文件未变化').evaluate().isNotEmpty,
        );
        expect((await _read(tester, first)).encode(), before);
        await tester.runAsync(
          () => file.writeAsString(
            _snapshot(quantity: 200, cash: 4500, hour: 10),
            flush: true,
          ),
        );
        await tester.pump(const Duration(seconds: 16));
        await _waitUntil(tester, '15 second foreground import', () async {
          final saved = await first.load();
          return saved?.cash == 4500 &&
              saved?.holdings.firstWhere((h) => h.code == '600001').quantity ==
                  200 &&
              find.textContaining('已自动导入').evaluate().isNotEmpty;
        });
        imported = await _read(tester, first);
        expect(imported.cash, 4500);
        expect(
          imported.holdings.firstWhere((h) => h.code == '600001').quantity,
          200,
        );
        expect(imported.assets, 7300);
        _preserved(imported, initial);
        await tester.runAsync(
          () => file.writeAsString('{incomplete', flush: true),
        );
        await _tap(tester, find.text('检查文件更新'));
        await _waitUntil(
          tester,
          'incomplete file refused',
          () async => find.textContaining('自动导入未应用').evaluate().isNotEmpty,
        );
        final failed = await _read(tester, first);
        expect(
          failed.holdings.map((h) => h.toJson()).toList(),
          imported.holdings.map((h) => h.toJson()).toList(),
        );
        expect(failed.cash, imported.cash);
        expect(
          failed.toJson()..remove('portfolioHistory'),
          imported.toJson()..remove('portfolioHistory'),
        );
        expect(failed.portfolioHistory.last.errorCode, 'invalid_snapshot');
        _preserved(failed, initial);
        imported = failed;
        await tester.runAsync(
          () => file.writeAsString(
            _snapshot(quantity: 200, cash: 4500, hour: 10),
            flush: true,
          ),
        );
        await _tap(tester, find.text('检查文件更新'));
        await _waitUntil(
          tester,
          'unchanged file retry',
          () async => find.textContaining('文件未变化').evaluate().isNotEmpty,
        );
        expect((await _read(tester, first)).encode(), imported.encode());
        expect(find.textContaining('文件未变化'), findsOneWidget);
        await _tap(tester, find.text('关闭自动读取'));
        await _waitUntil(tester, 'binding removed', () async {
          return await settings.read() == null &&
              find.text('文件自动读取已关闭').evaluate().isNotEmpty;
        });
        expect(await tester.runAsync(settings.read), isNull);
        final stopped = (await _read(tester, first)).encode();
        await tester.runAsync(
          () => file.writeAsString(
            _snapshot(quantity: 300, cash: 4000, hour: 11),
            flush: true,
          ),
        );
        await tester.pump(const Duration(seconds: 16));
        await _settle(tester);
        expect((await _read(tester, first)).encode(), stopped);
      }

      if (v06) {
        final beforeCharts = await _read(tester, first);
        final stocks = Platform.isWindows ? 2800.0 : 1600.0;
        final assets = Platform.isWindows ? 7300.0 : 6600.0;
        expect(beforeCharts.stocks, stocks);
        expect(beforeCharts.assets, assets);
        await _tap(tester, find.byKey(const ValueKey('risk-asset-details')));
        expect(
          find.textContaining(
            '合计 ¥${assets.toStringAsFixed(2)}；估值日期 2026-10-01',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('现金 ¥${beforeCharts.cash.toStringAsFixed(2)}'),
          findsWidgets,
        );
        await _tap(tester, find.widgetWithText(TextButton, '关闭'));
        await _tap(
          tester,
          find.byKey(const ValueKey('risk-principal-details')),
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.textContaining(
              '盈亏金额 ¥${(assets - 9500).toStringAsFixed(2)}',
            ),
          ),
          findsOneWidget,
        );
        await _tap(tester, find.widgetWithText(TextButton, '关闭'));
        final slider = find.byKey(const ValueKey('risk-stress-slider'));
        await _tap(tester, slider); // Actual pointer tap at the track midpoint.
        expect(tester.widget<Slider>(slider).value, .5);
        expect(
          find.text('情景后资产 ¥${(assets - stocks / 2).toStringAsFixed(2)}'),
          findsOneWidget,
        );
        expect(
          find.text(
            '账户损失 ${(stocks / 2 / assets * 100).toStringAsFixed(1)}% · 损失金额 ¥${(stocks / 2).toStringAsFixed(2)}',
          ),
          findsOneWidget,
        );
        expect((await _read(tester, first)).encode(), beforeCharts.encode());

        // Funding and company research are edited through their production UI.
        await _tap(tester, find.byTooltip('数据与设置'));
        await _tap(tester, find.text('账户设置').last);
        final accountFields = find.byType(TextFormField);
        await tester.ensureVisible(accountFields.at(1));
        await tester.enterText(accountFields.at(1), '11000');
        await _tap(tester, find.widgetWithText(FilledButton, '保存'));
        await _waitUntil(
          tester,
          'updated capital flow',
          () async => (await first.load())?.deposits == 11000,
        );
        await _tap(tester, find.text('公司研究').last);
        await _tap(tester, find.byTooltip('编辑研究卡').first);
        final studyFields = find.byType(TextFormField);
        await tester.ensureVisible(studyFields.at(3));
        await tester.enterText(studyFields.at(3), 'v0.6 导入后保留的新研究判断');
        await _tap(tester, find.widgetWithText(FilledButton, '保存'));
        await _waitUntil(
          tester,
          'updated study',
          () async =>
              (await first.load())?.studies.single.thesis == 'v0.6 导入后保留的新研究判断',
        );
        final afterResearch = await _read(tester, first);
        expect(afterResearch.principal, 10500);
        expect(afterResearch.studyVersions.length, 2);
        expect(afterResearch.financials.single.operatingCash, -20);
        await _tap(tester, find.text('账户风控').last);

        if (Platform.isWindows) {
          // The file was changed after stopping earlier. A fresh preview binds
          // that current complete snapshot, then history undo must shut it off.
          await importFile();
          await _tap(tester, find.text(_autoLabel));
          await _tap(tester, find.text(_reviewLabel));
          await _tap(tester, find.widgetWithText(FilledButton, '确认导入'));
          await _waitUntil(
            tester,
            'v06 rebound before history restore',
            () async => await settings.read() != null,
          );
        }
        final beforeUndo = await _read(tester, first);
        _preserved(beforeUndo, afterResearch);
        final target = beforeUndo.portfolioHistory.lastWhere(
          (entry) => entry.canRestore,
        );
        await _tap(tester, find.byKey(ValueKey('history-diff-${target.id}')));
        expect(find.text('完整持仓差异'), findsOneWidget);
        expect(find.textContaining('证券并集 2 项'), findsOneWidget);
        expect(find.textContaining('股数：'), findsWidgets);
        expect(find.textContaining('价格：'), findsWidgets);
        expect(find.textContaining('现金：'), findsOneWidget);
        await _tap(tester, find.widgetWithText(TextButton, '关闭'));
        await _tap(
          tester,
          find.byKey(ValueKey('history-restore-${target.id}')),
        );
        expect(find.text('恢复导入前的持仓？'), findsOneWidget);
        await _tap(tester, find.widgetWithText(TextButton, '取消'));
        expect((await _read(tester, first)).encode(), beforeUndo.encode());
        if (Platform.isWindows) {
          expect(await tester.runAsync(settings.read), isNotNull);
        }
        await _tap(
          tester,
          find.byKey(ValueKey('history-restore-${target.id}')),
        );
        await _tap(tester, find.widgetWithText(FilledButton, '确认恢复'));
        await _waitUntil(
          tester,
          'history restored and binding removed',
          () async =>
              (await first.load())?.portfolioHistory.last.action == 'restore' &&
              await settings.read() == null,
        );
        final undone = await _read(tester, first);
        expect(undone.cash, target.before!.cash);
        expect(undone.priceDate, target.before!.priceDate);
        expect(
          undone.holdings.map((h) => h.toJson()).toList(),
          target.before!.holdings.map((h) => h.toJson()).toList(),
        );
        expect(undone.portfolioHistory.last.referenceId, target.id);
        expect(
          undone.portfolioHistory.length,
          beforeUndo.portfolioHistory.length + 1,
        );
        _preserved(undone, afterResearch);
        expect(
          undone.reviews.map((r) => r.toJson()).toList(),
          afterResearch.reviews.map((r) => r.toJson()).toList(),
        );
        expect(
          await tester.runAsync(
            () => reportFiles.read(initial.documents.single.sha256),
          ),
          pdf,
        );
        expect(find.text('检查文件更新'), findsNothing);
        if (Platform.isWindows) {
          await tester.runAsync(
            () => file.writeAsString(
              _snapshot(quantity: 400, cash: 3000, hour: 12),
              flush: true,
            ),
          );
          await tester.pump(const Duration(seconds: 16));
          await _settle(tester);
          expect((await _read(tester, first)).encode(), undone.encode());
        }
      }

      await _tap(tester, find.byTooltip('数据与设置'));
      await _tap(tester, find.text('导出备份'));
      final backup = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      final exported = WorkspaceData.decode(backup);
      expect(exported.toJson()['schemaVersion'], 6);
      expect(backup, isNot(contains(file.path)));
      expect(backup, isNot(contains(_sentinel)));
      expect(backup, isNot(contains(base64Encode(pdf))));
      expect(backup, isNot(contains('originalBase64')));
      if (exportFixture.isNotEmpty) {
        await tester.runAsync(
          () => File(exportFixture).writeAsString(backup, flush: true),
        );
      }
      await _tap(tester, find.text('关闭'));
      await reopen(
        LocalWorkspaceStore(first.directory),
        file,
        _DiskSettings(settings.file),
      );
      expect((await _read(tester, first)).encode(), exported.encode());
      final incoming = importFixture.isEmpty
          ? backup
          : (await tester.runAsync(() => File(importFixture).readAsString()))!;
      final expected = WorkspaceData.decode(incoming);
      await reopen(
        second,
        file,
        _DiskSettings(File('${root.path}/second-binding.json')),
      );
      await _tap(tester, find.byTooltip('数据与设置'));
      await _tap(tester, find.text('导入备份'));
      await tester.enterText(find.byType(TextField), incoming);
      await _tap(tester, find.text('检查并导入'));
      expect((await _read(tester, second)).studies, isEmpty);
      await _tap(tester, find.text('确认'));
      await reopen(
        LocalWorkspaceStore(second.directory),
        file,
        _DiskSettings(File('${root.path}/second-binding.json')),
      );
      final restored = await _read(tester, second);
      expect(restored.encode(), expected.encode());
      _preserved(restored, v06 ? expected : initial);
      if (v06) {
        expect(restored.deposits, 11000);
        expect(restored.studies.single.thesis, 'v0.6 导入后保留的新研究判断');
        expect(restored.portfolioHistory.last.action, 'restore');
      }
      expect(restored.financials.single.operatingCash, -20);
      expect(restored.financials.single.adjustedProfit, isNull);
      expect(restored.documents.single.origin!.isRevision, isTrue);
      expect(restored.studies.single.reviewTasks.single.sourceIds, [
        restored.sources.single.id,
      ]);
      expect(
        await tester.runAsync(
          () => LocalReportFileStore(
            Directory('${second.directory.path}/reports'),
          ).read(restored.documents.single.sha256),
        ),
        isNull,
      );
      await _tap(tester, find.text('账户风控').last);
      expect(find.text('检查文件更新'), findsNothing);
      expect(
        await tester.runAsync(
          () => File('${root.path}/second-binding.json').exists(),
        ),
        isFalse,
      );

      await reopen(
        csvStore,
        csv,
        _DiskSettings(File('${root.path}/csv-binding.json')),
      );
      await _tap(tester, find.text('账户风控').last);
      await importFile();
      if (v06) {
        expect(find.text('核对文件编码'), findsOneWidget);
        expect((await _read(tester, csvStore)).portfolioHistory, isEmpty);
        await _tap(tester, find.byKey(const ValueKey('broker-encoding-gbk')));
      }
      expect(find.text('核对 CSV 的账户信息'), findsOneWidget);
      final fields = find.byType(TextFormField);
      final values = ['虚构验收券商', '虚构 CSV 账户', '2026-10-01', '1234'];
      for (var i = 0; i < values.length; i++) {
        await tester.ensureVisible(fields.at(i));
        await tester.enterText(fields.at(i), values[i]);
        FocusManager.instance.primaryFocus?.unfocus();
        await _settle(tester);
      }
      await _tap(tester, find.text('保存'));
      if (v06) {
        expect(find.text('核对 CSV 列映射'), findsOneWidget);
        for (final field in const {
          'code': '1. 编号 · 000001',
          'name': '2. 简称 · 虚构第二证券',
          'quantity': '3. 总股数 · 30',
          'price': '4. 现价 · 8',
        }.entries) {
          await _tap(tester, find.byKey(ValueKey('broker-map-${field.key}')));
          await _tap(tester, find.text(field.value).last);
        }
        await _tap(tester, find.text('应用列映射'));
      }
      expect((await _read(tester, csvStore)).holdings, isEmpty);
      if (v06) {
        expect((await _read(tester, csvStore)).portfolioHistory, isEmpty);
      }
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入'))
            .onPressed,
        isNull,
      );
      await _tap(tester, find.text(_reviewLabel));
      await _tap(tester, find.text('确认导入'));
      final csvResult = await _read(tester, csvStore);
      expect(csvResult.cash, 1234);
      expect(csvResult.assets, 2194);
      expect(csvResult.holdings.length, 2);
      expect(csvResult.portfolioImport!.format, 'csv');
      if (v06) expect(csvResult.portfolioHistory.single.action, 'import');
      await reopen(
        LocalWorkspaceStore(csvStore.directory),
        csv,
        _DiskSettings(File('${root.path}/csv-binding.json')),
      );
      expect((await _read(tester, csvStore)).encode(), csvResult.encode());
      // ignore: avoid_print
      print(
        '${v06 ? 'V06' : 'V05'}_ACCEPTANCE platform=${Platform.operatingSystem} native=$native schema=6 json=true csv=true gbkMapping=$v06 riskCharts=$v06 historyUndo=$v06 cancelNoWrite=true protectedResearch=true origin=true negativeCashFlow=-20 portableRestore=true bindingPathAbsent=true stoppedNoWrite=true windowsSync=${Platform.isWindows} crossPlatform=${importFixture.isNotEmpty} assets=${restored.assets} principal=${restored.principal}',
      );
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    },
    timeout: Timeout(Duration(minutes: v06 ? 8 : 5)),
  );
}
