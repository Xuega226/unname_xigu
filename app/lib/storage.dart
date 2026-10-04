import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import 'domain.dart';

abstract class WorkspaceStore {
  Future<WorkspaceData?> load();
  Future<void> save(WorkspaceData data);
}

class LocalWorkspaceStore implements WorkspaceStore {
  LocalWorkspaceStore(this.directory);
  final Directory directory;
  static Future<LocalWorkspaceStore> create() async {
    // ProductName changes in v0.2; retain the v0.1 storage identity explicitly.
    if (Platform.isWindows) {
      final root = Platform.environment['APPDATA'];
      if (root == null || root.isEmpty) {
        throw const FileSystemException('无法定位本地应用数据');
      }
      return LocalWorkspaceStore(
        Directory('$root/com.lianghua/lianghua_assistant'),
      );
    }
    return LocalWorkspaceStore(await getApplicationSupportDirectory());
  }

  File get file =>
      File('${directory.path}${Platform.pathSeparator}workspace.json');
  File get backup => File('${file.path}.bak');
  @override
  Future<WorkspaceData?> load() async {
    if (await file.exists()) {
      // Do not silently discard malformed user data or overwrite it with samples.
      final raw = await file.readAsString();
      final data = WorkspaceData.decode(raw);
      final schema = (jsonDecode(raw) as Map)['schemaVersion'];
      if (schema == 1 || schema == 2) {
        final legacy = File('${file.path}.v$schema.bak');
        if (!await legacy.exists()) await file.copy(legacy.path);
        await save(data);
      }
      return data;
    }
    if (await backup.exists()) {
      final raw = await backup.readAsString();
      final data = WorkspaceData.decode(raw);
      final schema = (jsonDecode(raw) as Map)['schemaVersion'];
      if (schema == 1 || schema == 2) {
        // An interrupted save can leave only an older-schema backup. Archive
        // its exact bytes before later saves replace the rolling backup.
        final legacy = File('${file.path}.v$schema.bak');
        if (!await legacy.exists()) await backup.copy(legacy.path);
        await save(data);
      }
      return data;
    }
    return null;
  }

  @override
  Future<void> save(WorkspaceData data) async {
    WorkspaceData.decode(data.encode());
    await directory.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(data.encode(), flush: true);
    if (await file.exists()) {
      await file.copy(backup.path);
      await file.delete();
    }
    await temporary.rename(file.path);
  }
}

class MemoryWorkspaceStore implements WorkspaceStore {
  MemoryWorkspaceStore([this.data]);
  WorkspaceData? data;
  @override
  Future<WorkspaceData?> load() async => data;
  @override
  Future<void> save(WorkspaceData value) async {
    data = value;
  }
}
