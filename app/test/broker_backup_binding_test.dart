import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_import.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';

import 'broker_import_test.dart' show snapshotBytes;

class _FailingStore extends MemoryWorkspaceStore {
  _FailingStore(super.data);
  bool failNextSave = false;

  @override
  Future<void> save(WorkspaceData value) async {
    if (failNextSave) {
      failNextSave = false;
      throw const FileSystemException('isolated test save failure');
    }
    await super.save(value);
  }
}

class _LockedBindingStore extends MemoryBrokerSettingsStore {
  @override
  Future<void> write(BrokerFileSettings? settings) async {
    if (settings == null) {
      throw const FileSystemException('isolated binding delete failure');
    }
    await super.write(settings);
  }
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _openRestore(WidgetTester tester, WorkspaceData backup) async {
  await _tap(tester, find.byTooltip('数据与设置'));
  await _tap(tester, find.text('导入备份'));
  await tester.enterText(find.byType(TextField), backup.encode());
}

Future<void> _allowDiskRead(WidgetTester tester) async {
  // Timer ticks use the widget clock; production file reads use actual IO.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<(File, WorkspaceData, WorkspaceData, MemoryBrokerSettingsStore)>
_fixture(WidgetTester tester) async {
  final root = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('v05_backup_binding_'),
  ))!;
  addTearDown(() async {
    final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
    final resolved = await root.resolveSymbolicLinks();
    if (!resolved.startsWith('$temporaryRoot${Platform.pathSeparator}') ||
        !root.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('v05_backup_binding_')) {
      throw StateError('Refusing to remove an unexpected test directory');
    }
    await root.delete(recursive: true);
  });
  final file = File('${root.path}/complete-account.json');
  final old = applyBrokerSnapshot(
    WorkspaceData.empty().copyWith(deposits: 7000, withdrawals: 500),
    parseBrokerFile(snapshotBytes()),
    sourceChangeConfirmed: true,
  );
  final bytes = snapshotBytes(
    quantity: 200,
    capturedAt: '2026-10-01T10:00:00+08:00',
  );
  await tester.runAsync(() => file.writeAsBytes(bytes, flush: true));
  final current = applyBrokerSnapshot(old, parseBrokerFile(bytes));
  final settings = MemoryBrokerSettingsStore()
    ..value = BrokerFileSettings(
      path: file.path,
      identity: current.portfolioImport!.identity,
    );
  return (file, old, current, settings);
}

void main() {
  testWidgets(
    'same-account backup restore clears binding and cannot be overwritten by a timer',
    (tester) async {
      final (file, backup, current, settings) = await _fixture(tester);
      final recovered = backup.copyWith(
        portfolioImport: backup.portfolioImport!.markModified(),
      );
      final store = _FailingStore(current);
      await tester.pumpWidget(
        LianghuaApp(store: store, brokerSettings: settings),
      );
      await tester.pumpAndSettle();
      await _openRestore(tester, backup);
      await tester.pump(const Duration(seconds: 16));
      await _allowDiskRead(tester);
      expect(store.data!.encode(), current.encode());
      expect(settings.value, isNotNull);

      await _tap(tester, find.text('检查并导入'));
      await _tap(tester, find.text('确认'));
      expect(store.data!.encode(), recovered.encode());
      expect(settings.value, isNull);

      await tester.runAsync(
        () => file.writeAsBytes(
          snapshotBytes(quantity: 300, capturedAt: '2026-10-01T11:00:00+08:00'),
          flush: true,
        ),
      );
      await tester.pump(const Duration(seconds: 31));
      await _allowDiskRead(tester);
      expect(store.data!.encode(), recovered.encode());
      expect(store.data!.principal, current.principal);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'failed binding deletion cannot resume overwriting restored backup after reopening',
    (tester) async {
      final (file, backup, current, oldSettings) = await _fixture(tester);
      final settings = _LockedBindingStore()..value = oldSettings.value;
      final originalBinding = settings.value;
      final store = _FailingStore(current);
      await tester.pumpWidget(
        LianghuaApp(store: store, brokerSettings: settings),
      );
      await tester.pumpAndSettle();
      await _openRestore(tester, backup);
      await _tap(tester, find.text('检查并导入'));
      await _tap(tester, find.text('确认'));
      expect(settings.value, same(originalBinding));
      expect(store.data!.portfolioImport!.modified, isTrue);
      expect(store.data!.cash, backup.cash);
      expect(
        store.data!.holdings.single.quantity,
        backup.holdings.single.quantity,
      );
      final restoredFingerprint = portfolioFingerprint(store.data!);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => file.writeAsBytes(
          snapshotBytes(quantity: 300, capturedAt: '2026-10-01T11:00:00+08:00'),
          flush: true,
        ),
      );
      // This settings object represents the old on-disk binding whose deletion
      // failed. A new app instance reads that binding again after restart.
      await tester.pumpWidget(
        LianghuaApp(store: store, brokerSettings: settings),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 31));
      await _allowDiskRead(tester);
      expect(portfolioFingerprint(store.data!), restoredFingerprint);
      expect(store.data!.portfolioImport!.modified, isTrue);
      expect(store.data!.principal, backup.principal);
      expect(
        store.data!.portfolioHistory.where((event) => event.action == 'import'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'cancelled or failed backup restore preserves the original working binding',
    (tester) async {
      final (file, backup, current, settings) = await _fixture(tester);
      final store = _FailingStore(current);
      final originalBinding = settings.value;
      await tester.pumpWidget(
        LianghuaApp(store: store, brokerSettings: settings),
      );
      await tester.pumpAndSettle();

      await _openRestore(tester, backup);
      await _tap(tester, find.text('关闭'));
      expect(store.data!.encode(), current.encode());
      expect(settings.value, same(originalBinding));

      await _openRestore(tester, backup);
      await _tap(tester, find.text('检查并导入'));
      store.failNextSave = true;
      await _tap(tester, find.text('确认'));
      expect(store.data!.encode(), current.encode());
      expect(settings.value, same(originalBinding));

      await tester.runAsync(
        () => file.writeAsBytes(
          snapshotBytes(quantity: 300, capturedAt: '2026-10-01T11:00:00+08:00'),
          flush: true,
        ),
      );
      await tester.pump(const Duration(seconds: 16));
      await _allowDiskRead(tester);
      expect(store.data!.holdings.single.quantity, 300);
      expect(store.data!.principal, current.principal);
      expect(settings.value, same(originalBinding));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
