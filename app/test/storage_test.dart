import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
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
      ..remove('financials');
    return utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(legacy).replaceAll('\n', '\r\n')}\r\n');
  }

  test('records survive reopening and previous save is backed up', () async {
    expect(await store.load(), isNull);
    await store.save(WorkspaceData.demo());
    await store.save(WorkspaceData.demo().copyWith(cash: 12345));
    final reopened = LocalWorkspaceStore(directory);
    expect((await reopened.load())!.cash, 12345);
    expect(WorkspaceData.decode(await store.backup.readAsString()).cash, 40000);
  });
  test('interrupted replacement recovers backup when primary file is absent',
      () async {
    await store.save(WorkspaceData.demo());
    await store.save(WorkspaceData.empty());
    await store.file.delete();
    expect((await store.load())!.isDemo, isTrue);
  });
  test('malformed primary is preserved and reported rather than replaced',
      () async {
    await directory.create(recursive: true);
    await store.file.writeAsString('{broken');
    await expectLater(store.load(), throwsFormatException);
    expect(await store.file.readAsString(), '{broken');
  });
  test('backup-only v1 migration archives exact original and restores primary',
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
    expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 2);
    expect((await LocalWorkspaceStore(directory).load())!.cash, 12345);

    await store.save(restored.copyWith(cash: 23456));
    expect(await archive.readAsBytes(), original);
    expect(WorkspaceData.decode(await store.backup.readAsString()).cash, 12345);
  });
  test('backup-only migration does not overwrite an existing v1 archive',
      () async {
    final archived = legacyBytes(cash: 11111);
    final original = legacyBytes(cash: 22222);
    final archive = File('${store.file.path}.v1.bak');
    await archive.writeAsBytes(archived, flush: true);
    await store.backup.writeAsBytes(original, flush: true);

    expect((await store.load())!.cash, 22222);

    expect(await archive.readAsBytes(), archived);
    expect(await store.backup.readAsBytes(), original);
    expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 2);
  });
  test('malformed backup-only input stays untouched without creating files',
      () async {
    final original = utf8.encode('{broken\r\n');
    await store.backup.writeAsBytes(original, flush: true);

    await expectLater(store.load(), throwsFormatException);

    expect(await store.backup.readAsBytes(), original);
    expect(await store.file.exists(), isFalse);
    expect(await File('${store.file.path}.v1.bak').exists(), isFalse);
    expect(await File('${store.file.path}.tmp').exists(), isFalse);
  });
}
