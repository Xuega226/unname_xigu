import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';

import 'broker_import.dart';
import 'domain.dart';
import 'storage.dart';
import 'portfolio_import_info.dart';

class SelectedPortfolioFile {
  const SelectedPortfolioFile({
    required this.bytes,
    required this.name,
    required this.path,
  });
  final List<int> bytes;
  final String name, path;
}

class BrokerImportService {
  Future<SelectedPortfolioFile?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: '券商持仓 CSV / JSON',
          extensions: ['csv', 'json'],
          mimeTypes: ['text/csv', 'application/json', 'text/plain'],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > maxPortfolioBytes) {
      throw const FormatException('文件超过 2 MB');
    }
    return SelectedPortfolioFile(
      bytes: await file.readAsBytes(),
      name: file.name,
      path: file.path,
    );
  }
}

class BrokerFileSettings {
  const BrokerFileSettings({required this.path, required this.identity});
  final String path, identity;
  Map<String, dynamic> toJson() => {'path': path, 'identity': identity};
  factory BrokerFileSettings.fromJson(Map<String, dynamic> j) {
    if (j['path'] is! String ||
        (j['path'] as String).isEmpty ||
        j['identity'] is! String ||
        (j['identity'] as String).isEmpty) {
      throw const FormatException('自动读取设置无效');
    }
    return BrokerFileSettings(path: j['path'], identity: j['identity']);
  }
}

abstract class BrokerSettingsStore {
  Future<BrokerFileSettings?> read();
  Future<void> write(BrokerFileSettings? value);
}

class LocalBrokerSettingsStore implements BrokerSettingsStore {
  Future<File> _file() async => File(
    '${(await LocalWorkspaceStore.create()).directory.path}/broker-file-settings.json',
  );
  @override
  Future<BrokerFileSettings?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final j = jsonDecode(await file.readAsString());
    if (j is! Map<String, dynamic>) throw const FormatException('自动读取设置无效');
    return BrokerFileSettings.fromJson(j);
  }

  @override
  Future<void> write(BrokerFileSettings? value) async {
    final file = await _file();
    if (value == null) {
      if (await file.exists()) await file.delete();
    } else {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(value.toJson()), flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    }
  }
}

class MemoryBrokerSettingsStore implements BrokerSettingsStore {
  BrokerFileSettings? value;
  @override
  Future<BrokerFileSettings?> read() async => value;
  @override
  Future<void> write(BrokerFileSettings? settings) async {
    value = settings;
  }
}

Future<List<int>> readPortfolioFile(String path) async {
  final file = File(path);
  final before = await file.stat();
  if (before.type != FileSystemEntityType.file ||
      before.size > maxPortfolioBytes) {
    throw const FormatException('持仓文件不存在或超过 2 MB');
  }
  // Enforce a limit while reading too: a concurrently growing file is untrusted.
  final bytes = <int>[];
  await for (final chunk in file.openRead()) {
    bytes.addAll(chunk);
    if (bytes.length > maxPortfolioBytes) {
      throw const FormatException('持仓文件超过 2 MB');
    }
  }
  final after = await file.stat();
  if (before.size != after.size ||
      before.modified != after.modified ||
      bytes.length != after.size) {
    throw const FormatException('文件正在更新，将在下次检查重试');
  }
  return bytes;
}

/// Foreground polling only. A source is bound after a reviewed first import.
class BrokerFileSync extends ChangeNotifier {
  BrokerFileSync({
    required this.settingsStore,
    required this.currentData,
    required this.canApply,
    required this.save,
    this.interval = const Duration(seconds: 15),
  });
  final BrokerSettingsStore settingsStore;
  final WorkspaceData? Function() currentData;
  final bool Function() canApply;
  final Future<bool> Function(WorkspaceData) save;
  final Duration interval;
  BrokerFileSettings? settings;
  String status = '尚未启用文件自动读取';
  Timer? _timer;
  bool _busy = false, _disposed = false;
  int _generation = 0;
  Future<void> _settingsWrites = Future.value();
  Future<void> _writeSettings(BrokerFileSettings? value) {
    final next = _settingsWrites.then((_) => settingsStore.write(value));
    _settingsWrites = next.catchError((_) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    final generation = _generation;
    try {
      final stored = await settingsStore.read();
      if (_disposed || generation != _generation) return;
      settings = stored;
      status = settings == null ? '尚未启用文件自动读取' : '等待检查已绑定的账户快照';
      _start();
    } catch (_) {
      status = '自动读取设置无法恢复，请重新选择文件';
    }
    _notify();
  }

  void _start() {
    _timer?.cancel();
    if (settings != null && !_disposed) {
      _timer = Timer.periodic(interval, (_) => check());
    }
  }

  Future<void> bind(String path, BrokerSnapshot snapshot) async {
    if (snapshot.info.format != 'json') {
      throw const FormatException('只有标准 JSON 支持自动读取');
    }
    final next = BrokerFileSettings(
      path: path,
      identity: snapshot.info.identity,
    );
    final generation = ++_generation;
    await _writeSettings(next);
    if (_disposed || generation != _generation) return;
    settings = next;
    status = '已绑定 · 每 15 秒检查更新（应用在前台时）';
    _start();
    _notify();
  }

  Future<void> stop() async {
    _generation++;
    _timer?.cancel();
    settings = null;
    status = '文件自动读取已关闭';
    _notify();
    await _writeSettings(null);
  }

  Future<void> check() async {
    final bound = settings;
    if (_busy || bound == null || _disposed || !canApply()) return;
    _busy = true;
    final generation = _generation;
    try {
      final snapshot = parseBrokerFile(await readPortfolioFile(bound.path));
      if (_disposed || generation != _generation || !canApply()) return;
      final data = currentData();
      if (data == null) return;
      final previous = data.portfolioImport;
      if (previous == null ||
          previous.modified ||
          data.isDemo ||
          previous.identity != bound.identity ||
          snapshot.info.identity != bound.identity) {
        await stop();
        status = '已暂停：账户或持仓已改变，请重新预览导入并绑定';
        _notify();
        return;
      }
      if (snapshot.info.digest == previous.digest) {
        status = '文件未变化 · 上次导入 ${brokerTimeLabel(previous.importedAt)}';
        _notify();
        return;
      }
      final next = applyBrokerSnapshot(data, snapshot, automatic: true);
      if (await save(next)) {
        status =
            '已自动导入 ${snapshot.holdings.length} 项持仓 · ${brokerTimeLabel(snapshot.info.importedAt)}';
      } else {
        status = '自动保存失败，保留旧持仓，下次重试';
      }
    } catch (_) {
      // Do not expose arbitrary source text, paths, or credentials from errors.
      status = '自动导入未应用：请检查文件完整性、日期与账户；空持仓需手动确认。旧数据已保留';
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
