import 'simplified_navigation.dart';

// Real disk and production UI, with fictional evidence and no network/AI calls.
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/quant_engine.dart';
import 'package:lianghua_assistant/storage.dart';

import 'v07_fixture.dart';

const _export = String.fromEnvironment('V07_EXPORT_FIXTURE');
const _import = String.fromEnvironment('V07_IMPORT_FIXTURE');

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 250; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.text('正在读取…').evaluate().isEmpty &&
        !tester
            .widgetList<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .any((w) => w.value == null)) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('v07 isolated disk IO did not finish');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await _settle(tester);
  await revealSimplifiedAction(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _edit(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  await revealSimplifiedAction(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, text);
  await _settle(tester);
}

Future<WorkspaceData> _read(WidgetTester t, LocalWorkspaceStore s) async =>
    (await t.runAsync(s.load))!;

void registerV07Acceptance({bool native = false}) {
  testWidgets('v0.7 native rules funding provenance and cross-device backup', (
    tester,
  ) async {
    if (!native) {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('xigu-v07-acceptance-'),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        final temp = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await root.resolveSymbolicLinks();
        if (!resolved.startsWith('$temp${Platform.pathSeparator}') ||
            !root.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('xigu-v07-acceptance-')) {
          throw StateError('Cleanup escaped test directory');
        }
        await root.delete(recursive: true);
      });
    });
    final first = LocalWorkspaceStore(Directory('${root.path}/first'));
    final second = LocalWorkspaceStore(Directory('${root.path}/second'));
    final initial = v07Fixture(configured: false, ledger: false);
    await tester.runAsync(() async {
      await first.save(initial);
      await second.save(WorkspaceData.empty());
    });
    Future<void> reopen(LocalWorkspaceStore store) async {
      await tester.pumpWidget(const SizedBox());
      await _settle(tester);
      await tester.pumpWidget(
        LianghuaApp(
          store: store,
          brokerSettings: MemoryBrokerSettingsStore(),
          credentials: MemoryCredentialStore(),
        ),
      );
      await _settle(tester);
      expect(find.byTooltip('数据与设置'), findsOneWidget);
    }

    await reopen(first);
    await _tap(tester, find.text('量化研究').last);
    expect(find.text('尚未配置规则，未计算综合分'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('quant-example')));
    await _edit(tester, 'quant-config-date', '2026-10-05');
    await _tap(tester, find.byKey(const ValueKey('quant-config-save')));
    var data = await _read(tester, first);
    expect(data.quant.currentConfig!.confirmed, isFalse);
    expect(evaluateQuant(data).ranked, isEmpty);
    expect(data.studies.single.thesis, initial.studies.single.thesis);

    await _tap(tester, find.byKey(const ValueKey('quant-edit')));
    await _edit(tester, 'quant-rule-weight-0', '3');
    await _edit(tester, 'quant-rule-threshold-1', '3');
    await _tap(tester, find.byKey(const ValueKey('quant-config-confirm')));
    await _tap(tester, find.byKey(const ValueKey('quant-config-save')));
    data = await _read(tester, first);
    expect(data.quant.versions.length, 2);
    expect(evaluateQuant(data).ranked.single.score, 75);
    expect(data.cash, initial.cash);
    expect(data.holdings.single.price, initial.holdings.single.price);
    final confirmedBytes = data.encode();
    await _tap(tester, find.byKey(const ValueKey('quant-edit')));
    await _edit(tester, 'quant-rule-weight-0', '99');
    await _tap(tester, find.byKey(const ValueKey('quant-config-cancel')));
    expect((await _read(tester, first)).encode(), confirmedBytes);

    await _tap(tester, find.byKey(const ValueKey('quant-details-SH:600001')));
    expect(find.textContaining('2025-01-01'), findsWidgets);
    expect(find.textContaining('v07-source-2025'), findsWidgets);
    await _tap(tester, find.byKey(const ValueKey('quant-details-SH:600001')));
    await _tap(
      tester,
      find.byKey(const ValueKey('quant-open-research-SH:600001')),
    );
    expect(find.text('返回全部公司研究'), findsOneWidget);
    expect(find.textContaining(initial.studies.single.thesis), findsWidgets);
    await _tap(tester, find.text('量化研究').last);

    await _tap(tester, find.byKey(const ValueKey('history-import-json')));
    await _edit(
      tester,
      'history-json-input',
      initial.priceHistory.single.encode(),
    );
    await _tap(tester, find.text('校验并预览'));
    await _tap(tester, find.text('取消'));
    expect((await _read(tester, first)).encode(), confirmedBytes);

    await _tap(tester, find.byKey(const ValueKey('funding-enable')));
    await _edit(tester, 'funding-start-input', '2026-10-01');
    await _tap(tester, find.byKey(const ValueKey('funding-enable-confirm')));
    data = await _read(tester, first);
    expect(data.funding!.entries, isEmpty);
    expect(data.principal, 9500);
    await _tap(tester, find.byKey(const ValueKey('funding-add')));
    await _edit(tester, 'funding-date-input', '2026-10-02');
    await _edit(tester, 'funding-amount-input', '1000');
    await _edit(tester, 'funding-source-input', '虚构转入回单');
    await _tap(tester, find.byKey(const ValueKey('funding-flow-save')));
    data = await _read(tester, first);
    expect(data.principal, 10500);
    expect(data.cash, initial.cash);
    expect(data.funding!.entries.single.amount, 1000);

    await _tap(tester, find.byTooltip('数据与设置'));
    await _tap(tester, find.text('账户设置').last);
    final readonly = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.readOnly)
        .toList();
    expect(readonly.length, 2);
    await _tap(tester, find.text('取消'));
    await _tap(tester, find.byTooltip('数据与设置'));
    await _tap(tester, find.text('导出备份'));
    final backup = tester
        .widget<TextField>(find.byType(TextField))
        .controller!
        .text;
    expect(WorkspaceData.decode(backup).encode(), data.encode());
    if (_export == 'stdout') {
      // Android test teardown uninstalls its app. Capture fictional backup
      // through the test runner instead of writing outside its private root.
      debugPrint(
        'V07_BACKUP_BASE64=${base64Encode(utf8.encode(backup))}',
        wrapWidth: 20000,
      );
    } else if (_export.isNotEmpty) {
      await tester.runAsync(
        () => File(_export).writeAsString(backup, flush: true),
      );
    }
    await _tap(tester, find.text('关闭'));
    await reopen(LocalWorkspaceStore(first.directory));
    expect((await _read(tester, first)).encode(), data.encode());

    final incoming = _import.isEmpty
        ? backup
        : (await tester.runAsync(() => File(_import).readAsString()))!;
    final expected = WorkspaceData.decode(incoming);
    await reopen(second);
    await _tap(tester, find.byTooltip('数据与设置'));
    await _tap(tester, find.text('导入备份'));
    await tester.enterText(find.byType(TextField), incoming);
    await _tap(tester, find.text('检查并导入'));
    expect((await _read(tester, second)).quant.versions, isEmpty);
    await _tap(tester, find.text('确认'));
    await reopen(LocalWorkspaceStore(second.directory));
    final restored = await _read(tester, second);
    expect(restored.encode(), expected.encode());
    expect(evaluateQuant(restored).ranked.single.score, 75);
    expect(restored.funding!.entries.single.amount, 1000);
    expect(restored.studies.single.thesis, initial.studies.single.thesis);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
