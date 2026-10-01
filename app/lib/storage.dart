import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'domain.dart';

abstract class WorkspaceStore {
  Future<WorkspaceData?> load();
  Future<void> save(WorkspaceData data);
}

class LocalWorkspaceStore implements WorkspaceStore {
  LocalWorkspaceStore(this.directory);
  final Directory directory;
  static Future<LocalWorkspaceStore> create() async =>
      LocalWorkspaceStore(await getApplicationSupportDirectory());
  File get file =>
      File('${directory.path}${Platform.pathSeparator}workspace.json');
  File get backup => File('${file.path}.bak');
  @override
  Future<WorkspaceData?> load() async {
    if (await file.exists()) {
      // Do not silently discard malformed user data or overwrite it with samples.
      return WorkspaceData.decode(await file.readAsString());
    }
    if (await backup.exists()) {
      return WorkspaceData.decode(await backup.readAsString());
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
