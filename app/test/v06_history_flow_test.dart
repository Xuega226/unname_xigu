import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';

import 'broker_import_test.dart' show snapshotBytes;
import 'portfolio_history_test.dart' show seed;

class _Files extends BrokerImportService {
  _Files(this.file);
  final File file;
  @override
  Future<SelectedPortfolioFile?> pick() async => SelectedPortfolioFile(
    bytes: await file.readAsBytes(),
    name: 'fictional.json',
    path: file.path,
  );
}

class _Store extends MemoryWorkspaceStore {
  _Store(super.data);
  bool failNextSave = false;
  @override
  Future<void> save(WorkspaceData value) async {
    if (failNextSave) {
      failNextSave = false;
      throw const FileSystemException('isolated save failure');
    }
    await super.save(value);
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _disk(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'reviewed import history, current research and funding edits, restore cancel/failure/success and stopped timer',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('v06_history_flow_'),
      ))!;
      addTearDown(() async {
        final boundary = await Directory.systemTemp.resolveSymbolicLinks();
        final target = await directory.resolveSymbolicLinks();
        if (!target.startsWith('$boundary${Platform.pathSeparator}') ||
            !directory.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('v06_history_flow_')) {
          throw StateError('Unexpected test directory');
        }
        await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/fictional.json');
      await tester.runAsync(
        () => file.writeAsBytes(snapshotBytes(), flush: true),
      );
      final initial = seed().copyWith(
        studies: const [
          Study(
            id: 'study',
            code: '600001',
            name: '虚构公司',
            business: '原有业务',
            thesis: '原有判断',
            counterEvidence: '',
            reviewCondition: '',
            source: '',
            updatedAt: '2026-10-01',
          ),
        ],
      );
      final store = _Store(initial);
      final settings = MemoryBrokerSettingsStore();
      await tester.pumpWidget(
        LianghuaApp(
          store: store,
          brokerSettings: settings,
          brokerImporter: _Files(file),
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('账户风控').last);
      await _tap(tester, find.text('导入券商持仓').last);
      await _tap(tester, find.text('选择持仓文件'));
      await _disk(tester);
      expect(store.data!.encode(), initial.encode());
      await _tap(tester, find.text('已核对账户、完整持仓、现金和估值日期'));
      await _tap(
        tester,
        find.byKey(const ValueKey('broker-source-confirmation')),
      );
      if (Platform.isWindows) {
        await _tap(tester, find.text('应用在前台时，每 15 秒自动读取同一文件'));
      }
      await _tap(tester, find.text('确认导入'));
      expect(store.data!.holdings.single.quantity, 100);
      expect(store.data!.portfolioHistory.length, 1);
      final entryId = store.data!.portfolioHistory.single.id;
      if (Platform.isWindows) expect(settings.value, isNotNull);

      // Edit through production UI after importing. Funding changes preserve the
      // source binding; they must never be rolled back by restoring a snapshot.
      await _tap(tester, find.text('账户设置'));
      await tester.enterText(find.byType(TextFormField).at(1), '9000');
      await tester.enterText(find.byType(TextFormField).at(2), '700');
      await tester.enterText(find.byType(TextFormField).at(3), '30');
      await _tap(tester, find.text('保存'));
      await _tap(tester, find.text('公司研究').last);
      await _tap(tester, find.byTooltip('编辑研究卡'));
      await tester.enterText(find.byType(TextFormField).at(2), '导入后更新的业务事实');
      await tester.enterText(find.byType(TextFormField).at(3), '导入后更新的判断');
      await _tap(tester, find.text('保存'));
      await _tap(tester, find.text('账户风控').last);
      final current = store.data!;
      expect(current.principal, 8300);
      expect(current.lossBudget, .3);
      expect(current.studyVersions.length, 1);
      expect(current.studies.single.business, '导入后更新的业务事实');
      if (Platform.isWindows) expect(settings.value, isNotNull);

      Future<void> openRestore() =>
          _tap(tester, find.byKey(ValueKey('history-restore-$entryId')));
      await openRestore();
      expect(find.text('恢复导入前的持仓？'), findsOneWidget);
      expect(find.textContaining('只恢复持仓、现金与估值日期'), findsOneWidget);
      await tester.runAsync(
        () => file.writeAsBytes(
          snapshotBytes(quantity: 200, capturedAt: '2026-10-01T10:00:00+08:00'),
          flush: true,
        ),
      );
      await tester.pump(const Duration(seconds: 16));
      await _disk(tester);
      expect(store.data!.encode(), current.encode());
      await _tap(tester, find.text('取消').last);
      expect(store.data!.encode(), current.encode());
      if (Platform.isWindows) expect(settings.value, isNotNull);

      await openRestore();
      await tester.pump(const Duration(seconds: 16));
      await _disk(tester);
      store.failNextSave = true;
      await _tap(tester, find.text('确认恢复'));
      expect(store.data!.encode(), current.encode());
      if (Platform.isWindows) expect(settings.value, isNotNull);

      await openRestore();
      await _tap(tester, find.text('确认恢复'));
      final restored = store.data!;
      expect(restored.cash, initial.cash);
      expect(restored.holdings.single.code, initial.holdings.single.code);
      expect(
        restored.holdings.single.quantity,
        initial.holdings.single.quantity,
      );
      expect(restored.priceDate, initial.priceDate);
      expect(restored.portfolioImport, isNull);
      expect(restored.principal, current.principal);
      expect(restored.lossBudget, current.lossBudget);
      expect(restored.studies.single.toJson(), current.studies.single.toJson());
      expect(
        restored.studyVersions.single.toJson(),
        current.studyVersions.single.toJson(),
      );
      expect(restored.portfolioHistory.length, 2);
      expect(restored.portfolioHistory.last.action, 'restore');
      expect(settings.value, isNull);
      await tester.runAsync(
        () => file.writeAsBytes(
          snapshotBytes(quantity: 300, capturedAt: '2026-10-01T11:00:00+08:00'),
          flush: true,
        ),
      );
      await tester.pump(const Duration(seconds: 31));
      await _disk(tester);
      expect(store.data!.encode(), restored.encode());
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
