import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'services.dart';

class AiSettings {
  const AiSettings({this.key = '', this.model = DeepSeekService.defaultModel});
  final String key, model;
}

abstract class CredentialStore {
  Future<AiSettings> read();
  Future<void> write(AiSettings settings);
  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  final storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true));
  static const entry = 'weiming_xigu.deepseek.v1';
  @override
  Future<AiSettings> read() async {
    final raw = await storage.read(key: entry);
    if (raw == null) return const AiSettings();
    final j = jsonDecode(raw) as Map;
    return AiSettings(key: j['key'] as String, model: j['model'] as String);
  }

  @override
  Future<void> write(AiSettings value) => storage.write(
      key: entry, value: jsonEncode({'key': value.key, 'model': value.model}));
  @override
  Future<void> clear() => storage.delete(key: entry);
}

class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore([this.settings = const AiSettings()]);
  AiSettings settings;
  @override
  Future<AiSettings> read() async => settings;
  @override
  Future<void> write(AiSettings value) async {
    settings = value;
  }

  @override
  Future<void> clear() async {
    settings = const AiSettings();
  }
}
