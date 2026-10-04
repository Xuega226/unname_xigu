import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/storage.dart';

void main() {
  late Directory directory;
  late LocalWorkspaceStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lianghua_test_');
    store = LocalWorkspaceStore(directory);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  List<int> legacyBytes({double cash = 40000}) {
    final legacy = WorkspaceData.demo().copyWith(cash: cash).toJson()
      ..['schemaVersion'] = 1
      ..remove('watchlist')
      ..remove('sources')
      ..remove('financials')
      ..remove('documents')
      ..remove('studyVersions');
    return utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(legacy).replaceAll('\n', '\r\n')}\r\n',
    );
  }

  List<int> v2Bytes({double cash = 12345}) {
    final old =
        WorkspaceData.demo()
            .copyWith(
              cash: cash,
              sources: [
                const SourceExcerpt(
                  id: 'legacy-source',
                  studyId: 's0',
                  title: '旧版虚构财务资料',
                  url: 'https://example.com/legacy-report',
                  period: '2025年度',
                  disclosedAt: '2026-03-31',
                  page: '第10页',
                  unit: '万元',
                  text: '虚构资料：营业收入为100万元，经营现金流为负20万元。',
                ),
              ],
              financials: [
                const FinancialRecord(
                  id: 'legacy-financial',
                  studyId: 's0',
                  sourceId: 'legacy-source',
                  start: '2025-01-01',
                  end: '2025-12-31',
                  disclosedAt: '2026-03-31',
                  unit: '万元',
                  revenue: 100,
                  operatingCash: -20,
                ),
              ],
            )
            .toJson()
          ..['schemaVersion'] = 2
          ..remove('documents')
          ..remove('studyVersions');
    for (final study in old['studies'] as List) {
      (study as Map)
        ..remove('nextReviewAt')
        ..remove('reviewTasks');
    }
    for (final financial in old['financials'] as List) {
      (financial as Map)
        ..remove('scope')
        ..remove('basis')
        ..remove('origin')
        ..remove('evidence');
    }
    return utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(old).replaceAll('\n', '\r\n')}\r\n',
    );
  }

  test('records survive reopening and previous save is backed up', () async {
    expect(await store.load(), isNull);
    await store.save(WorkspaceData.demo());
    await store.save(WorkspaceData.demo().copyWith(cash: 12345));
    final reopened = LocalWorkspaceStore(directory);
    expect((await reopened.load())!.cash, 12345);
    expect(WorkspaceData.decode(await store.backup.readAsString()).cash, 40000);
  });
  test(
    'interrupted replacement recovers backup when primary file is absent',
    () async {
      await store.save(WorkspaceData.demo());
      await store.save(WorkspaceData.empty());
      await store.file.delete();
      expect((await store.load())!.isDemo, isTrue);
    },
  );
  test(
    'malformed primary is preserved and reported rather than replaced',
    () async {
      await directory.create(recursive: true);
      await store.file.writeAsString('{broken');
      await expectLater(store.load(), throwsFormatException);
      expect(await store.file.readAsString(), '{broken');
    },
  );
  test(
    'backup-only v1 migration archives exact original and restores primary',
    () async {
      final original = legacyBytes(cash: 12345);
      await store.backup.writeAsBytes(original, flush: true);

      final restored = await store.load();

      expect(restored!.cash, 12345);
      expect(restored.holdings.length, 3);
      expect(restored.studies.length, 5);
      expect(restored.watchlist, isEmpty);
      final archive = File('${store.file.path}.v1.bak');
      expect(await archive.readAsBytes(), original);
      expect(await store.backup.readAsBytes(), original);
      expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 3);
      expect((await LocalWorkspaceStore(directory).load())!.cash, 12345);

      await store.save(restored.copyWith(cash: 23456));
      expect(await archive.readAsBytes(), original);
      expect(
        WorkspaceData.decode(await store.backup.readAsString()).cash,
        12345,
      );
    },
  );
  test(
    'backup-only migration does not overwrite an existing v1 archive',
    () async {
      final archived = legacyBytes(cash: 11111);
      final original = legacyBytes(cash: 22222);
      final archive = File('${store.file.path}.v1.bak');
      await archive.writeAsBytes(archived, flush: true);
      await store.backup.writeAsBytes(original, flush: true);

      expect((await store.load())!.cash, 22222);

      expect(await archive.readAsBytes(), archived);
      expect(await store.backup.readAsBytes(), original);
      expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 3);
    },
  );
  test(
    'malformed backup-only input stays untouched without creating files',
    () async {
      final original = utf8.encode('{broken\r\n');
      await store.backup.writeAsBytes(original, flush: true);

      await expectLater(store.load(), throwsFormatException);

      expect(await store.backup.readAsBytes(), original);
      expect(await store.file.exists(), isFalse);
      expect(await File('${store.file.path}.v1.bak').exists(), isFalse);
      expect(await File('${store.file.path}.v2.bak').exists(), isFalse);
      expect(await File('${store.file.path}.tmp').exists(), isFalse);
    },
  );
  for (final backupOnly in [false, true]) {
    test(
      'v2 migration backupOnly=$backupOnly keeps financials and exact archive',
      () async {
        final original = v2Bytes();
        await (backupOnly ? store.backup : store.file).writeAsBytes(
          original,
          flush: true,
        );

        final restored = (await store.load())!;

        expect(restored.cash, 12345);
        expect(restored.holdings.length, 3);
        expect(restored.studies.length, 5);
        expect(restored.documents, isEmpty);
        expect(restored.studyVersions, isEmpty);
        expect(restored.sources.single.id, 'legacy-source');
        expect(restored.financials.single.sourceId, restored.sources.single.id);
        expect(restored.financials.single.revenue, 100);
        expect(restored.financials.single.operatingCash, -20);
        expect(restored.financials.single.cash, isNull);
        expect(restored.financials.single.debt, isNull);
        expect(restored.financials.single.scope, '未注明');
        expect(restored.financials.single.basis, '未注明');
        final archive = File('${store.file.path}.v2.bak');
        expect(await archive.readAsBytes(), original);
        expect(await store.backup.readAsBytes(), original);
        expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 3);
        expect(
          (await LocalWorkspaceStore(directory).load())!.encode(),
          restored.encode(),
        );

        await store.save(restored.copyWith(cash: 23456));
        expect(await archive.readAsBytes(), original);
        expect(
          WorkspaceData.decode(await store.backup.readAsString()).cash,
          12345,
        );
      },
    );
  }
  test(
    'backup-only v2 migration keeps an existing immutable archive',
    () async {
      final archived = v2Bytes(cash: 11111);
      final incoming = v2Bytes(cash: 22222);
      final archive = File('${store.file.path}.v2.bak');
      await archive.writeAsBytes(archived, flush: true);
      await store.backup.writeAsBytes(incoming, flush: true);

      expect((await store.load())!.cash, 22222);

      expect(await archive.readAsBytes(), archived);
      expect(await store.backup.readAsBytes(), incoming);
      expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 3);
    },
  );
  test(
    'invalid v2 backup remains untouched before any migration writes',
    () async {
      final invalid =
          jsonDecode(utf8.decode(v2Bytes())) as Map<String, dynamic>;
      (invalid['financials'] as List).single['sourceId'] = 'missing-source';
      final original = utf8.encode(jsonEncode(invalid));
      await store.backup.writeAsBytes(original, flush: true);

      await expectLater(store.load(), throwsFormatException);

      expect(await store.backup.readAsBytes(), original);
      expect(await store.file.exists(), isFalse);
      expect(await File('${store.file.path}.v2.bak').exists(), isFalse);
      expect(await File('${store.file.path}.tmp').exists(), isFalse);
    },
  );
}
