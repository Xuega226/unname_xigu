// Uses fictional temporary files, isolated workspace and settings. The native
// chooser is injected; this verifies native IO/persistence, not the OS dialog.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';

import '../test/broker_import_test.dart' show snapshotBytes;

class NativeTestFile extends BrokerImportService {
  NativeTestFile(this.file);
  final File file;
  @override
  Future<SelectedPortfolioFile?> pick() async => SelectedPortfolioFile(
    bytes: await readPortfolioFile(file.path),
    name: '虚构测试.json',
    path: file.path,
  );
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native file import, foreground sync and isolated disk persistence',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp(
        'weiming_broker_native_',
      );
      final file = File('${dir.path}/snapshot.json');
      final store = LocalWorkspaceStore(Directory('${dir.path}/workspace'));
      final settings = MemoryBrokerSettingsStore();
      try {
        await file.writeAsBytes(snapshotBytes());
        await store.save(WorkspaceData.empty());
        await tester.pumpWidget(
          LianghuaApp(
            store: store,
            brokerSettings: settings,
            brokerImporter: NativeTestFile(file),
          ),
        );
        await tester.pumpAndSettle();
        await tapText(tester, '账户风控');
        await tapText(tester, '导入券商持仓');
        await tapText(tester, '选择持仓文件');
        if (Platform.isWindows) {
          await tapText(tester, '应用在前台时，每 15 秒自动读取同一文件');
        }
        await tapText(tester, '已核对账户、完整持仓、现金和估值日期');
        await tapText(tester, '确认导入');
        expect((await store.load())!.holdings.single.quantity, 100);
        if (Platform.isWindows) {
          await file.writeAsBytes(
            snapshotBytes(
              quantity: 200,
              capturedAt: '2026-10-01T10:00:00+08:00',
            ),
          );
          await tapText(tester, '检查文件更新');
          expect((await store.load())!.holdings.single.quantity, 200);
          await file.writeAsString('{incomplete');
          await tapText(tester, '检查文件更新');
          expect((await store.load())!.holdings.single.quantity, 200);
          await tapText(tester, '关闭自动读取');
          expect(settings.value, isNull);
        }
        final original = (await store.load())!.encode();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          LianghuaApp(
            store: LocalWorkspaceStore(store.directory),
            brokerSettings: MemoryBrokerSettingsStore(),
          ),
        );
        await tester.pumpAndSettle();
        expect((await store.load())!.encode(), original);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final temporaryRoot = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await dir.resolveSymbolicLinks();
        if (!resolved.startsWith('$temporaryRoot${Platform.pathSeparator}')) {
          throw StateError('Cleanup escaped temporary root');
        }
        await dir.delete(recursive: true);
      }
    },
  );
}
