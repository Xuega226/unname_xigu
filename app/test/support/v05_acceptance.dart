// Fictional files and isolated directories only. The native chooser is injected;
// parsing, workspace persistence, foreground polling and backup UI are real.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
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
    initial.reviews.single.toJson(),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    final awaitingCsvDetails = find.text('核对 CSV 的账户信息').evaluate().isNotEmpty;
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        (awaitingCsvDetails || find.text('正在读取…').evaluate().isEmpty)) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('v0.5 isolated disk operation did not finish');
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
  fail('v0.5 $operation did not reach its observable result');
}

void registerV05Acceptance({bool native = false}) {
  testWidgets(
    'v0.5 isolated disk portfolio review, foreground sync and portable backup',
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
        () => Directory.systemTemp.createTemp('xigu-v05-acceptance-'),
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
        await csv.writeAsString(
          '证券代码,证券名称,持仓数量,市价\n000001,虚构第二证券,30,8\n600001,虚构测试公司,60,12',
          flush: true,
        );
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
        expect(failed.encode(), imported.encode());
        _preserved(failed, initial);
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

      await _tap(tester, find.byTooltip('数据与设置'));
      await _tap(tester, find.text('导出备份'));
      final backup = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      final exported = WorkspaceData.decode(backup);
      expect(exported.toJson()['schemaVersion'], 4);
      expect(backup, isNot(contains(file.path)));
      expect(backup, isNot(contains(_sentinel)));
      expect(backup, isNot(contains(base64Encode(pdf))));
      expect(backup, isNot(contains('originalBase64')));
      if (_exportFixture.isNotEmpty) {
        await tester.runAsync(
          () => File(_exportFixture).writeAsString(backup, flush: true),
        );
      }
      await _tap(tester, find.text('关闭'));
      await reopen(
        LocalWorkspaceStore(first.directory),
        file,
        _DiskSettings(settings.file),
      );
      expect((await _read(tester, first)).encode(), exported.encode());
      final incoming = _importFixture.isEmpty
          ? backup
          : (await tester.runAsync(() => File(_importFixture).readAsString()))!;
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
      _preserved(restored, initial);
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
      expect((await _read(tester, csvStore)).holdings, isEmpty);
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
      await reopen(
        LocalWorkspaceStore(csvStore.directory),
        csv,
        _DiskSettings(File('${root.path}/csv-binding.json')),
      );
      expect((await _read(tester, csvStore)).encode(), csvResult.encode());
      // ignore: avoid_print
      print(
        'V05_ACCEPTANCE platform=${Platform.operatingSystem} native=$native schema=4 json=true csv=true cancelNoWrite=true protectedResearch=true origin=true negativeCashFlow=-20 portableRestore=true bindingPathAbsent=true stoppedNoWrite=true windowsSync=${Platform.isWindows} crossPlatform=${_importFixture.isNotEmpty} assets=${restored.assets} principal=${restored.principal}',
      );
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
