import 'simplified_navigation.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

const _excerpt = '以下仅为虚构验收资料：营业收入为100万元，经营现金流为负20万元。';
const _review = '离线验收复查：现金流仍需关注，2026-11-04 补充新证据。';
const _sentinel = 'offline-acceptance-sentinel';
const _exportFixture = String.fromEnvironment('V02_EXPORT_FIXTURE');
const _importFixture = String.fromEnvironment('V02_IMPORT_FIXTURE');

class _AcceptanceTransport implements JsonTransport {
  bool failQuote = false;
  int generated = 0;
  Map<String, dynamic>? sentResearch;

  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    if (uri.host == 'push2.eastmoney.com') {
      expect(uri.queryParameters['secid'], '0.000001');
      return {
        'rc': 0,
        'data': {'f57': '000001', 'f58': '平安银行', 'f127': '银行', 'f107': 0},
      };
    }
    if (uri.host == 'push2his.eastmoney.com') {
      if (failQuote) throw ServiceFailure('离线验收模拟行情失败');
      return {
        'rc': 0,
        'data': {
          'code': '000001',
          'market': 0,
          'klines': ['2026-09-30,10.00,11.50'],
        },
      };
    }
    expect(uri.host, 'api.deepseek.com');
    expect(uri.path, '/chat/completions');
    expect(headers['Authorization'], 'Bearer $_sentinel');
    final messages = body!['messages'] as List;
    sentResearch = jsonDecode(
      (messages.last as Map)['content'] as String,
    ) as Map<String, dynamic>;
    final sources = sentResearch!['sources'] as List;
    expect(sources.length, 1);
    final source = sources.single as Map;
    expect(source['text'], _excerpt);
    generated++;
    return {
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {
            'content': jsonEncode({
              'facts': [
                {
                  'text': '虚构验收资料记录营收100万元、现金流负20万元。',
                  'refs': [
                    {'sourceId': source['id'], 'quote': _excerpt},
                  ],
                },
              ],
              'support': [],
              'counter': [],
              'missing': [
                {'text': '缺少有息负债资料。', 'refs': []},
              ],
              'review': [
                {'text': '下次报告复查经营现金流。', 'refs': []},
              ],
            }),
          },
        },
      ],
    };
  }
}

// Disk I/O must run outside the widget test's fake clock. Wait for the app's
// pending load/save to finish before settling animations or reading the disk.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    // Risk exposure bars are determinate values, whereas a determinate
    // progress bar inside a modal can still mean a PDF/save is in flight.
    final modalProgress = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(LinearProgressIndicator),
    );
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        modalProgress.evaluate().isEmpty &&
        !tester
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .any((indicator) => indicator.value == null)) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('Offline acceptance load/save did not complete');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
  await revealSimplifiedAction(tester, finder);
  await tester.ensureVisible(finder);
  // Navigation reuses its Scrollable; layout must complete after revealing
  // controls above a tall risk-chart page before computing a tap position.
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _fill(WidgetTester tester, List<String> values) async {
  final fields = find.byType(TextFormField);
  expect(fields, findsNWidgets(values.length));
  for (var i = 0; i < values.length; i++) {
    await tester.ensureVisible(fields.at(i));
    await tester.enterText(fields.at(i), values[i]);
  }
  await _tap(tester, find.text('保存'));
}

Future<WorkspaceData> _read(
  WidgetTester tester,
  LocalWorkspaceStore store,
) async => (await tester.runAsync(store.load))!;

void registerV02Acceptance({bool native = false}) {
  testWidgets('v0.2 offline final workflow persists and restores across stores', (
    tester,
  ) async {
    if (!native) {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    } else if (Platform.isAndroid) {
      expect(
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
        lessThan(760),
        reason: 'Native Android acceptance must use a phone layout',
      );
    }
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('xigu-v02-acceptance-'),
    ))!;
    addTearDown(() async {
      await tester.runAsync(() async {
        final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await root.resolveSymbolicLinks();
        if (!resolved.startsWith('$temporaryRoot${Platform.pathSeparator}')) {
          throw StateError('Acceptance cleanup escaped temporary root');
        }
        await root.delete(recursive: true);
      });
    });
    final first = LocalWorkspaceStore(Directory('${root.path}/first'));
    final second = LocalWorkspaceStore(Directory('${root.path}/second'));
    await tester.runAsync(() async {
      await first.save(WorkspaceData.empty());
      await second.save(WorkspaceData.empty());
    });
    final transport = _AcceptanceTransport();
    final market = MarketService(
      transport: transport,
      clock: () => DateTime.utc(2026, 10, 1, 10),
    );
    final ai = DeepSeekService(transport: transport);
    final credentials = MemoryCredentialStore(const AiSettings(key: _sentinel));
    Widget app(LocalWorkspaceStore store) => LianghuaApp(
      store: store,
      market: market,
      ai: ai,
      credentials: credentials,
    );

    await tester.pumpWidget(app(first));
    await _settle(tester);
    await _tap(tester, find.text('公司研究').last);
    await _tap(tester, find.text('添加真实公司'));
    await _tap(tester, find.byType(DropdownButtonFormField<String>));
    await _tap(tester, find.text('深圳 SZ').last);
    await tester.enterText(find.byType(TextField), '000001');
    await _tap(tester, find.text('核验公司'));
    await _tap(tester, find.text('加入自选'));
    expect((await _read(tester, first)).watchlist.single.symbol, 'SZ:000001');
    await _tap(tester, find.text('更新自选日线'));
    final quoted = (await _read(tester, first)).watchlist.single;
    expect(quoted.close, 11.5);
    expect(quoted.tradeDate, '2026-09-30');

    await _tap(tester, find.text('资料与财务（0 段原文）'));
    await _tap(tester, find.text('添加原文片段'));
    await _fill(tester, [
      '离线验收虚构财报',
      'https://example.com/offline-acceptance-report',
      '2025 年度',
      '2026-03-31',
      '第10页',
      '万元',
      _excerpt,
    ]);
    final source = (await _read(tester, first)).sources.single;
    expect(source.text, _excerpt);
    expect(source.page, '第10页');
    await _tap(tester, find.text('核对财务字段'));
    await _tap(tester, find.byType(SimpleDialogOption));
    await _fill(tester, [
      '2025-01-01',
      '2025-12-31',
      '2026-03-31',
      '万元',
      '合并',
      '原披露',
      '100',
      '',
      '-20',
      '',
      '',
    ]);
    final financial = (await _read(tester, first)).financials.single;
    expect(financial.sourceId, source.id);
    expect(financial.revenue, 100);
    expect(financial.operatingCash, -20);
    expect(financial.adjustedProfit, isNull);
    expect(financial.cash, isNull);
    expect(financial.debt, isNull);
    await _tap(tester, find.text('关闭'));

    final beforeDraft = await _read(tester, first);
    await _tap(tester, find.text('生成 AI 草稿'));
    await _tap(tester, find.text('发送资料并生成'));
    expect((await _read(tester, first)).encode(), beforeDraft.encode());
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '接受为研究卡版本'))
          .onPressed,
      isNull,
    );
    await _tap(tester, find.byType(CheckboxListTile));
    await _tap(tester, find.text('接受为研究卡版本'));
    final accepted = await _read(tester, first);
    expect(accepted.studies.single.business, contains(source.id));
    expect(accepted.studies.single.counterEvidence, contains('缺少有息负债'));
    expect(accepted.reviews.single.text, contains('旧研究卡'));
    expect(accepted.reviews.single.text, contains('接受的新版本'));
    expect(transport.generated, 1);
    expect(
      transport.sentResearch!.keys,
      unorderedEquals(['company', 'sources']),
    );

    await _tap(tester, find.text('账户风控').last);
    await _tap(tester, find.text('账户设置'));
    await _fill(tester, ['1000', '2000', '0', '20', '2026-09-29']);
    await _tap(tester, find.text('新增持仓'));
    await _fill(tester, ['000001', '平安银行', '银行', '100', '10']);
    await _tap(tester, find.text('应用同日行情到持仓'));
    expect((await _read(tester, first)).holdings.single.price, 10);
    await _tap(tester, find.text('确认'));
    final portfolio = await _read(tester, first);
    expect(portfolio.priceDate, '2026-09-30');
    expect(portfolio.holdings.single.price, 11.5);
    expect(portfolio.assets, 2150);
    expect(portfolio.profitRate, closeTo(.075, 1e-12));
    expect(portfolio.stressLoss(.3), closeTo(1150 / 2150 * .3, 1e-12));

    await _tap(tester, find.text('公司研究').last);
    transport.failQuote = true;
    await _tap(tester, find.text('更新自选日线'));
    final failed = await _read(tester, first);
    expect(failed.watchlist.single.close, quoted.close);
    expect(failed.watchlist.single.tradeDate, quoted.tradeDate);
    expect(failed.watchlist.single.error, contains('离线验收模拟行情失败'));
    expect(failed.holdings.single.price, 11.5);
    expect(failed.assets, 2150);
    expect(find.textContaining('上次更新失败'), findsOneWidget);

    await _tap(tester, find.text('复查日志').last);
    await _tap(tester, find.text('记录一次复查'));
    await _fill(tester, ['平安银行', _review]);
    await _tap(tester, find.byTooltip('数据与设置'));
    await _tap(tester, find.text('导出备份'));
    final backup = tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .text;
    expect(backup, isNot(contains(_sentinel)));
    final exported = WorkspaceData.decode(backup);
    expect(exported.reviews.last.text, _review);
    expect(exported.reviews.length, 3);
    if (_exportFixture.isNotEmpty) {
      await tester.runAsync(
        () => File(_exportFixture).writeAsString(backup, flush: true),
      );
    }
    await _tap(tester, find.text('关闭'));

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    await tester.pumpWidget(app(second));
    await _settle(tester);
    await _tap(tester, find.byTooltip('数据与设置'));
    await _tap(tester, find.text('导入备份'));
    await tester.enterText(find.byType(TextField), backup);
    await _tap(tester, find.text('检查并导入'));
    expect((await _read(tester, second)).sources, isEmpty);
    await _tap(tester, find.text('确认'));
    expect((await _read(tester, second)).encode(), exported.encode());

    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
    final reopenedStore = LocalWorkspaceStore(second.directory);
    await tester.pumpWidget(app(reopenedStore));
    await _settle(tester);
    final reopened = await _read(tester, reopenedStore);
    expect(reopened.encode(), exported.encode());
    expect(reopened.sources.single.id, source.id);
    expect(reopened.financials.single.operatingCash, -20);
    expect(reopened.financials.single.debt, isNull);
    expect(reopened.assets, portfolio.assets);
    expect(reopened.profitRate, portfolio.profitRate);
    await _tap(tester, find.text('复查日志').last);
    expect(find.text(_review), findsOneWidget);
    await _tap(tester, find.text('公司研究').last);
    expect(find.textContaining('虚构验收资料记录营收'), findsOneWidget);

    var verified = reopened;
    if (_importFixture.isNotEmpty) {
      final incoming = (await tester.runAsync(
        () => File(_importFixture).readAsString(),
      ))!;
      expect(incoming, isNot(contains(_sentinel)));
      final imported = WorkspaceData.decode(incoming);
      await _tap(tester, find.byTooltip('数据与设置'));
      await _tap(tester, find.text('导入备份'));
      await tester.enterText(find.byType(TextField), incoming);
      await _tap(tester, find.text('检查并导入'));
      expect((await _read(tester, reopenedStore)).encode(), reopened.encode());
      await _tap(tester, find.text('确认'));
      expect((await _read(tester, reopenedStore)).encode(), imported.encode());
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      final exchangedStore = LocalWorkspaceStore(second.directory);
      await tester.pumpWidget(app(exchangedStore));
      await _settle(tester);
      verified = await _read(tester, exchangedStore);
      expect(verified.encode(), imported.encode());
      expect(verified.sources.single.text, _excerpt);
      expect(verified.sources.single.title, '离线验收虚构财报');
      expect(verified.sources.single.page, '第10页');
      expect(verified.sources.single.unit, '万元');
      expect(verified.sources.single.disclosedAt, '2026-03-31');
      expect(verified.financials.single.sourceId, verified.sources.single.id);
      expect(verified.sources.single.studyId, verified.studies.single.id);
      expect(verified.financials.single.operatingCash, -20);
      expect(verified.financials.single.debt, isNull);
      expect(
        verified.studies.single.source,
        contains(verified.sources.single.id),
      );
      expect(verified.reviews.first.text, contains(verified.sources.single.id));
      expect(verified.reviews.last.text, _review);
      expect(verified.reviews.length, 3);
      expect(verified.assets, 2150);
      expect(verified.profitRate, closeTo(.075, 1e-12));
      expect(verified.stressLoss(.3), closeTo(1150 / 2150 * .3, 1e-12));
      await _tap(tester, find.text('复查日志').last);
      expect(find.text(_review), findsOneWidget);
    }
    // Only fixture counts and deterministic risk values; no paths or credentials.
    // ignore: avoid_print
    print(
      'V02_ACCEPTANCE platform=${Platform.operatingSystem} '
      'schema=${verified.toJson()['schemaVersion']} '
      'companies=${verified.watchlist.length} sources=${verified.sources.length} '
      'financials=${verified.financials.length} reviews=${verified.reviews.length} '
      'assets=${verified.assets} profit=${verified.profitRate} '
      'stress=${verified.stressLoss(.3)} '
      'exchange=${_importFixture.isNotEmpty}',
    );
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);
  });
}
