import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/quant_engine.dart';
import 'package:lianghua_assistant/quant_models.dart';
import 'package:lianghua_assistant/storage.dart';
import 'package:lianghua_assistant/portfolio_history.dart';
import 'package:lianghua_assistant/forms.dart';

import 'support/v07_fixture.dart';
import 'portfolio_history_test.dart' show info;

void main() {
  test('readonly legacy funds preserve valid large and fractional totals', () {
    const field = InputField(
      '累计入金',
      '1000000000001.001',
      numeric: true,
      readOnly: true,
      readOnlyMessage: '由流水维护',
    );
    expect(field.validate('1000000000001.001'), isNull);
    expect(field.validate('10'), '由流水维护');
  });
  late Directory directory;
  late LocalWorkspaceStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xigu-v07-schema-');
    store = LocalWorkspaceStore(directory);
  });
  tearDown(() async {
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    final path = await directory.resolveSymbolicLinks();
    if (!path.startsWith('$temp${Platform.pathSeparator}') ||
        !directory.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('xigu-v07-schema-')) {
      throw StateError('Unsafe test cleanup');
    }
    await directory.delete(recursive: true);
  });
  test(
    'schema7 complete backup and reopen preserve hand calculated result',
    () async {
      final original = v07Fixture();
      await store.save(original);
      final reopened = (await LocalWorkspaceStore(directory).load())!;
      expect(reopened.encode(), original.encode());
      expect(reopened.principal, 10500);
      expect(evaluateQuant(reopened).ranked.single.score, 75);
      expect(reopened.quant.shareFacts.single.totalShares, 100000);
      expect(reopened.priceHistory.single.bars.length, 3);
      expect(reopened.studies.single.thesis, original.studies.single.thesis);
    },
  );
  for (final backupOnly in [false, true]) {
    test('schema6 migration ($backupOnly backup) keeps exact bytes and history', () async {
      final initial = v07Fixture(
        configured: false,
        ledger: false,
      ).copyWith(quant: const QuantState(), priceHistory: []);
      final legacy = recordPortfolioImport(
        initial,
        initial.copyWith(cash: 4600, portfolioImport: info()),
      );
      final map = legacy.toJson()
        ..['schemaVersion'] = 6
        ..remove('quant')
        ..remove('priceHistory')
        ..remove('funding');
      final bytes = utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(map).replaceAll('\n', '\r\n')}\r\n',
      );
      await (backupOnly ? store.backup : store.file).writeAsBytes(
        bytes,
        flush: true,
      );
      final migrated = (await store.load())!;
      expect(migrated.encode(), legacy.encode());
      expect(migrated.quant.versions, isEmpty);
      expect(migrated.funding, isNull);
      expect(migrated.portfolioHistory.length, 1);
      final archive = File('${store.file.path}.v6.bak');
      expect(await archive.readAsBytes(), bytes);
      await store.save(migrated.copyWith(cash: 4700));
      expect(await archive.readAsBytes(), bytes);
      expect((await store.load())!.cash, 4700);
    });
  }
  test('malformed new state never overwrites prior disk workspace', () async {
    final original = v07Fixture();
    await store.save(original);
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (j) => j['deposits'] = 11000.01,
      (j) => j['quant']['shareFacts'][0]['sourceId'] = 'missing-source',
      (j) => j['quant']['shareFacts'][0]['symbol'] = 'SZ:000001',
      (j) => j['priceHistory'].add(j['priceHistory'][0]),
      (j) => j['quant']['versions'][0]['confirmedAt'] = '2026-10-05T00:00:00',
      (j) => j['funding']['entries'][0]['amount'] = -1,
    ]) {
      final map = jsonDecode(original.encode()) as Map<String, dynamic>;
      mutate(map);
      expect(
        () => WorkspaceData.decode(jsonEncode(map)),
        throwsFormatException,
      );
      expect((await store.load())!.encode(), original.encode());
    }
  });
  test(
    'portfolio restore keeps current parameters prices ledger and research',
    () {
      final original = v07Fixture();
      final imported = recordPortfolioImport(
        original,
        original.copyWith(cash: 6000, portfolioImport: info()),
      );
      final restored = restorePortfolioHistory(
        imported,
        imported.portfolioHistory.single.id,
      );
      expect(restored.cash, original.cash);
      expect(restored.quant.toJson(), original.quant.toJson());
      expect(
        restored.priceHistory.single.toJson(),
        original.priceHistory.single.toJson(),
      );
      expect(restored.funding!.toJson(), original.funding!.toJson());
      expect(restored.principal, 10500);
      expect(restored.studies.single.thesis, original.studies.single.thesis);
      expect(
        WorkspaceData.decode(restored.encode()).encode(),
        restored.encode(),
      );
    },
  );
}
