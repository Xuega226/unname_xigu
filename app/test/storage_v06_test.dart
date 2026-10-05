import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/storage.dart';

import 'portfolio_history_test.dart' show info, seed;

void main() {
  late Directory directory;
  late LocalWorkspaceStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xigu_v06_schema_');
    store = LocalWorkspaceStore(directory);
  });
  tearDown(() async {
    final path = directory.absolute.path;
    final boundary = Directory.systemTemp.absolute.path;
    if (!path.startsWith('$boundary${Platform.pathSeparator}') ||
        !directory.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last
            .startsWith('xigu_v06_schema_')) {
      throw StateError('测试目录超出预定范围');
    }
    await directory.delete(recursive: true);
  });
  WorkspaceData fixture() => seed().copyWith(
    portfolioImport: info(),
    studies: const [
      Study(
        id: 'study',
        code: '600001',
        name: '虚构公司',
        business: '业务',
        thesis: '判断',
        counterEvidence: '',
        reviewCondition: '',
        source: '',
        updatedAt: '2026-10-01',
      ),
    ],
    sources: const [
      SourceExcerpt(
        id: 'source',
        studyId: 'study',
        title: '虚构报告',
        url: 'https://example.com/fictional',
        period: '2025年度',
        disclosedAt: '2026-03-31',
        page: '10',
        unit: '万元',
        text: '经营现金流负20万元',
      ),
    ],
    financials: const [
      FinancialRecord(
        id: 'financial',
        studyId: 'study',
        sourceId: 'source',
        start: '2025-01-01',
        end: '2025-12-31',
        disclosedAt: '2026-03-31',
        unit: '万元',
        revenue: 100,
        operatingCash: -20,
      ),
    ],
  );
  List<int> oldBytes(WorkspaceData data) {
    final json = data.toJson()
      ..['schemaVersion'] = 4
      ..remove('portfolioHistory');
    return utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert(json).replaceAll('\n', '\r\n')}\r\n',
    );
  }

  for (final backupOnly in [false, true]) {
    test(
      'schema4 primary/backup=$backupOnly migration keeps exact immutable archive and all fields',
      () async {
        final original = fixture();
        final bytes = oldBytes(original);
        await (backupOnly ? store.backup : store.file).writeAsBytes(
          bytes,
          flush: true,
        );
        final migrated = (await store.load())!;
        expect(migrated.encode(), original.encode());
        expect(migrated.portfolioHistory, isEmpty);
        expect(
          migrated.portfolioImport!.toJson(),
          original.portfolioImport!.toJson(),
        );
        expect(migrated.financials.single.operatingCash, -20);
        expect(migrated.financials.single.cash, isNull);
        expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 6);
        final archive = File('${store.file.path}.v4.bak');
        expect(await archive.readAsBytes(), bytes);
        expect(await store.backup.readAsBytes(), bytes);
        await store.save(migrated.copyWith(cash: 333));
        expect(await archive.readAsBytes(), bytes);
        expect((await LocalWorkspaceStore(directory).load())!.cash, 333);
      },
    );
    test(
      'schema4 primary/backup=$backupOnly migration never replaces existing v4 archive',
      () async {
        final archive = File('${store.file.path}.v4.bak');
        final original = oldBytes(fixture().copyWith(cash: 11));
        await archive.writeAsBytes(original);
        await (backupOnly ? store.backup : store.file).writeAsBytes(
          oldBytes(fixture().copyWith(cash: 22)),
        );
        expect((await store.load())!.cash, 22);
        expect(await archive.readAsBytes(), original);
      },
    );
    test(
      'schema5 primary/backup=$backupOnly is rejected without migration write',
      () async {
        final unsupported = utf8.encode(
          jsonEncode(fixture().toJson()..['schemaVersion'] = 5),
        );
        final selected = backupOnly ? store.backup : store.file;
        await selected.writeAsBytes(unsupported);
        await expectLater(store.load(), throwsFormatException);
        expect(await selected.readAsBytes(), unsupported);
        expect(await File('${store.file.path}.v5.bak').exists(), isFalse);
        expect(await File('${store.file.path}.tmp').exists(), isFalse);
        if (backupOnly) expect(await store.file.exists(), isFalse);
      },
    );
  }
}
