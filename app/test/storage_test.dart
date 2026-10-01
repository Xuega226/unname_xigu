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
}
