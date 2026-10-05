import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_import.dart';
import 'package:lianghua_assistant/broker_sync.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/storage.dart';

Map<String, dynamic> snapshotJson({
  String alias = '测试主账户',
  String capturedAt = '2026-10-01T09:00:00+08:00',
  int quantity = 100,
}) => {
  'snapshotVersion': 1,
  'complete': true,
  'currency': 'CNY',
  'accountType': 'cash_equity',
  'broker': '虚构测试券商',
  'accountAlias': alias,
  'priceDate': '2026-10-01',
  'capturedAt': capturedAt,
  'cash': 5000,
  'holdings': <Map<String, dynamic>>[
    {'code': '000001', 'name': '测试证券', 'quantity': quantity, 'price': 10},
  ],
};
List<int> snapshotBytes({
  String alias = '测试主账户',
  String capturedAt = '2026-10-01T09:00:00+08:00',
  int quantity = 100,
}) => utf8.encode(
  jsonEncode(
    snapshotJson(alias: alias, capturedAt: capturedAt, quantity: quantity),
  ),
);
BrokerSnapshot snapshot({int quantity = 100}) =>
    parseBrokerFile(snapshotBytes(quantity: quantity));

class DelayedBrokerSettings extends MemoryBrokerSettingsStore {
  final entered = Completer<void>(), release = Completer<void>();
  var writes = 0;
  @override
  Future<void> write(BrokerFileSettings? settings) async {
    if (writes++ == 0) {
      entered.complete();
      await release.future;
    }
    value = settings;
  }
}

void main() {
  test(
    'snapshot rejects clock overflow and validates future instants in UTC',
    () {
      final clock = DateTime.utc(2026, 10, 1, 1);
      for (final invalid in [
        '2026-10-01T25:00:00+08:00',
        '2026-10-01T12:99:00+08:00',
        '2026-10-01T12:00:60+08:00',
        '2026-10-01T12:00:00+24:00',
        '2026-10-01T12:00:00-08:99',
        '2026-10-01T09:00:00',
        '2026-02-31T09:00:00+08:00',
        '2026-10-01T01:05:01Z',
        '2026-10-01T09:05:01+08:00',
      ]) {
        expect(
          () => parseBrokerFile(snapshotBytes(capturedAt: invalid), now: clock),
          throwsFormatException,
          reason: 'invalid snapshot instant: $invalid',
        );
      }
      for (final valid in [
        '2026-10-01T09:00:00+08:00',
        '2026-10-01T01:00:00.123456Z',
        '2026-10-01T01:05:00Z',
      ]) {
        final result = parseBrokerFile(
          snapshotBytes(capturedAt: valid),
          now: clock,
        );
        expect(result.info.capturedAt, valid);
        expect(result.info.importedAt, clock.toIso8601String());
      }
    },
  );
  test('snapshot rejects control characters in broker identity', () {
    for (final field in ['broker', 'accountAlias']) {
      for (final invalid in ['a\u0000b', 'a\u007fb', 'a\u0085b']) {
        final j = snapshotJson()..[field] = invalid;
        expect(
          () => parseBrokerFile(utf8.encode(jsonEncode(j))),
          throwsFormatException,
        );
      }
    }
  });
  test('changed source needs explicit funding review and never changes capital flows', () {
    final data = applyBrokerSnapshot(
      WorkspaceData.empty().copyWith(
        deposits: 6000,
        withdrawals: 1000,
        lossBudget: 0.25,
      ),
      snapshot(),
    );
    final original = data.encode();
    final replacement = parseBrokerFile(snapshotBytes(alias: '另一个来源账户'));
    expect(brokerSourceChangeNeedsConfirmation(data, replacement), isTrue);
    expect(brokerSourceChangeNeedsConfirmation(data, snapshot()), isFalse);
    expect(
      brokerSourceChangeNeedsConfirmation(
        WorkspaceData.empty().copyWith(deposits: 1),
        snapshot(),
      ),
      isTrue,
    );
    expect(
      brokerSourceChangeNeedsConfirmation(
        WorkspaceData.empty().copyWith(withdrawals: 1),
        snapshot(),
      ),
      isTrue,
    );
    expect(
      brokerSourceChangeNeedsConfirmation(WorkspaceData.empty(), snapshot()),
      isFalse,
    );
    expect(() => applyBrokerSnapshot(data, replacement), throwsFormatException);
    expect(data.encode(), original);
    expect(
      () => applyBrokerSnapshot(
        data,
        replacement,
        automatic: true,
        sourceChangeConfirmed: true,
      ),
      throwsFormatException,
    );
    final reviewed = applyBrokerSnapshot(
      data,
      replacement,
      sourceChangeConfirmed: true,
    );
    expect(reviewed.portfolioImport!.accountAlias, '另一个来源账户');
    expect(reviewed.deposits, data.deposits);
    expect(reviewed.withdrawals, data.withdrawals);
    expect(reviewed.lossBudget, data.lossBudget);
    expect(reviewed.studies, data.studies);
  });
  test(
    'stop during binding is serialized and never restores a stopped source',
    () async {
      final settings = DelayedBrokerSettings();
      final sync = BrokerFileSync(
        settingsStore: settings,
        currentData: () => null,
        canApply: () => false,
        save: (_) async => false,
      );
      try {
        final binding = sync.bind('test-only.json', snapshot());
        await settings.entered.future;
        final stopping = sync.stop();
        settings.release.complete();
        await binding;
        await stopping;
        expect(sync.settings, isNull);
        expect(settings.value, isNull);
      } finally {
        sync.dispose();
      }
    },
  );
  test(
    'a changed source account disables persisted automatic binding',
    () async {
      final dir = await Directory.systemTemp.createTemp('broker_identity_');
      final file = File('${dir.path}/snapshot.json');
      final settings = MemoryBrokerSettingsStore();
      var data = applyBrokerSnapshot(WorkspaceData.empty(), snapshot());
      var saves = 0;
      final sync = BrokerFileSync(
        settingsStore: settings,
        currentData: () => data,
        canApply: () => true,
        save: (next) async {
          saves++;
          data = next;
          return true;
        },
      );
      try {
        await file.writeAsBytes(snapshotBytes(alias: '另一个账户'));
        await sync.bind(file.path, snapshot());
        await sync.check();
        expect(saves, 1);
        expect(data.holdings.single.quantity, 100);
        expect(data.portfolioHistory.single.errorCode, 'source_changed');
        expect(settings.value, isNull);
        expect(sync.settings, isNull);
        expect(sync.status, contains('重新预览'));
      } finally {
        sync.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('complete JSON replaces portfolio atomically but retains capital flows and research', () {
    final original = WorkspaceData.demo().copyWith(
      isDemo: false,
      priceDate: '2026-10-01',
    );
    final result = applyBrokerSnapshot(original, snapshot());
    expect(result.cash, 5000);
    expect(result.holdings.single.code, '000001');
    expect(result.assets, 6000);
    expect(result.deposits, original.deposits);
    expect(result.withdrawals, original.withdrawals);
    expect(result.studies.length, original.studies.length);
    expect(result.portfolioImport!.accountAlias, '测试主账户');
    expect(WorkspaceData.decode(result.encode()).encode(), result.encode());
    expect(result.encode(), isNot(contains('path')));
  });
  test('Chinese CSV uses total holdings and current price, handles quoted numbers and UTF BOMs', () {
    const csv =
        '证券代码,证券名称,股票余额,可用余额,市价,成本价\r\n000001,"测试,公司","1,000",500,10,8\r\n';
    const details = CsvAccountDetails(
      broker: '测试',
      accountAlias: '主账户',
      priceDate: '2026-10-01',
      cash: 100,
    );
    for (final bytes in [
      utf8.encode('\uFEFF$csv'),
      [
        255,
        254,
        for (final c in csv.codeUnits) ...[c & 255, c >> 8],
      ],
    ]) {
      final result = parseBrokerFile(bytes, csv: details);
      expect(result.holdings.single.code, '000001');
      expect(result.holdings.single.quantity, 1000);
      expect(result.holdings.single.price, 10);
      expect(result.holdings.single.name, '测试,公司');
      expect(result.info.format, 'csv');
    }
  });
  test('CSV refuses available balance or cost price as substitutes and malformed rows', () {
    const details = CsvAccountDetails(
      broker: '测试',
      accountAlias: '主账户',
      priceDate: '2026-10-01',
      cash: 0,
    );
    for (final csv in [
      '证券代码,证券名称,可用余额,市价\n000001,公司,10,10',
      '证券代码,证券名称,股票余额,成本价\n000001,公司,10,10',
      '证券代码,证券名称,股票余额,持仓数量,市价\n000001,公司,10,10,10',
      '证券代码,证券名称,股票余额,市价\n000001,公司,10',
      '证券代码,证券名称,股票余额,市价\n000001,"公司,10,10',
    ]) {
      expect(
        () => parseBrokerFile(utf8.encode(csv), csv: details),
        throwsFormatException,
      );
    }
  });
  test('partial, unsupported, duplicate, wrong market, invalid quantity, dates and prices fail', () {
    for (final change in <void Function(Map<String, dynamic>)>[
      (j) => j['complete'] = false,
      (j) => j['currency'] = 'USD',
      (j) => j['accountType'] = 'margin',
      (j) => j['cash'] = -1,
      (j) => j['holdings'].add(<String, dynamic>{...j['holdings'][0]}),
      (j) => j['holdings'][0]['code'] = 1,
      (j) => j['holdings'][0]['code'] = '000001.SH',
      (j) => j['holdings'][0]['quantity'] = 1.5,
      (j) => j['holdings'][0]['quantity'] = -1,
      (j) => j['holdings'][0]['price'] = 0,
      (j) => j['holdings'][0]['price'] = 'NaN',
      (j) => j['priceDate'] = '2026-02-31',
      (j) => j['capturedAt'] = '2099-01-01T09:00:00+08:00',
      (j) => j['capturedAt'] = '2026-10-01T09:00:00',
      (j) => j['capturedAt'] = '2026-02-31T09:00:00+08:00',
    ]) {
      final j = snapshotJson();
      change(j);
      expect(
        () => parseBrokerFile(utf8.encode(jsonEncode(j))),
        throwsFormatException,
      );
    }
  });
  test('imports refuse demo and old dates; initial empty portfolio accepts prior trading day', () {
    expect(
      () => applyBrokerSnapshot(WorkspaceData.demo(), snapshot()),
      throwsFormatException,
    );
    final imported = applyBrokerSnapshot(WorkspaceData.empty(), snapshot());
    expect(imported.priceDate, '2026-10-01');
    expect(
      () => applyBrokerSnapshot(
        imported.copyWith(priceDate: '2026-10-02'),
        snapshot(),
      ),
      throwsFormatException,
    );
  });
  test('automatic snapshots bind account and refuse empty, modified and equal-time changed content', () {
    final data = applyBrokerSnapshot(WorkspaceData.empty(), snapshot());
    for (final bytes in [
      snapshotBytes(alias: '其他账户'),
      snapshotBytes(quantity: 0, capturedAt: '2026-10-01T10:00:00+08:00'),
      snapshotBytes(quantity: 200),
      snapshotBytes(capturedAt: '2026-10-01T08:00:00+08:00'),
    ]) {
      expect(
        () =>
            applyBrokerSnapshot(data, parseBrokerFile(bytes), automatic: true),
        throwsFormatException,
      );
    }
    expect(
      () => applyBrokerSnapshot(
        data.copyWith(portfolioImport: data.portfolioImport!.markModified()),
        snapshot(),
        automatic: true,
      ),
      throwsFormatException,
    );
    final next = parseBrokerFile(
      snapshotBytes(quantity: 200, capturedAt: '2026-10-01T10:00:00+08:00'),
    );
    expect(
      applyBrokerSnapshot(data, next, automatic: true).holdings.single.id,
      data.holdings.single.id,
    );
    expect(
      applyBrokerSnapshot(data, next, automatic: true).holdings.single.quantity,
      200,
    );
    expect(
      applyBrokerSnapshot(
        data,
        parseBrokerFile(snapshotBytes(quantity: 0)),
      ).holdings,
      isEmpty,
    );
  });
  test(
    'v3 disk migration keeps original bytes before writing current schema',
    () async {
      final dir = await Directory.systemTemp.createTemp('broker_migration_');
      try {
        final store = LocalWorkspaceStore(dir);
        final j = WorkspaceData.demo().toJson()
          ..['schemaVersion'] = 3
          ..remove('portfolioImport');
        final raw = jsonEncode(j);
        await store.file.writeAsString(raw);
        final result = await store.load();
        expect(result!.studies.length, 5);
        expect(await File('${store.file.path}.v3.bak').readAsString(), raw);
        expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 8);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('foreground sync deduplicates, preserves data on errors, retries failed saves and restores binding', () async {
    final dir = await Directory.systemTemp.createTemp('broker_sync_');
    final file = File('${dir.path}/snapshot.json');
    final settings = MemoryBrokerSettingsStore();
    var data = applyBrokerSnapshot(WorkspaceData.empty(), snapshot());
    var saves = 0, active = true, fail = false;
    final sync = BrokerFileSync(
      settingsStore: settings,
      currentData: () => data,
      canApply: () => active,
      save: (next) async {
        saves++;
        if (fail) return false;
        data = next;
        return true;
      },
    );
    try {
      await file.writeAsBytes(snapshotBytes());
      await sync.bind(file.path, snapshot());
      await sync.check();
      expect(saves, 0);
      await file.writeAsBytes(
        snapshotBytes(quantity: 200, capturedAt: '2026-10-01T10:00:00+08:00'),
      );
      active = false;
      await sync.check();
      expect(saves, 0);
      active = true;
      fail = true;
      await sync.check();
      expect(saves, 2); // Portfolio save and best-effort safe failure record.
      expect(data.holdings.single.quantity, 100);
      fail = false;
      await sync.check();
      expect(saves, 3);
      expect(data.holdings.single.quantity, 200);
      expect(data.portfolioHistory.single.action, 'import');
      await sync.check();
      expect(saves, 3);
      await file.writeAsString('{incomplete');
      await sync.check();
      expect(saves, 4);
      expect(data.holdings.single.quantity, 200);
      expect(data.portfolioHistory.last.errorCode, 'invalid_snapshot');
      await sync.check();
      expect(saves, 4); // The same failure is not written repeatedly.
      expect(sync.status, contains('旧数据已保留'));
      final restored = BrokerFileSync(
        settingsStore: settings,
        currentData: () => data,
        canApply: () => true,
        save: (_) async => true,
      );
      await restored.initialize();
      expect(restored.settings!.path, file.path);
      restored.dispose();
      await sync.stop();
      expect(settings.value, isNull);
    } finally {
      sync.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('pending file reads cannot save after stop', () async {
    final dir = await Directory.systemTemp.createTemp('broker_stop_');
    final file = File('${dir.path}/snapshot.json');
    final data = applyBrokerSnapshot(WorkspaceData.empty(), snapshot());
    var saves = 0;
    final sync = BrokerFileSync(
      settingsStore: MemoryBrokerSettingsStore(),
      currentData: () => data,
      canApply: () => true,
      save: (_) async {
        saves++;
        return true;
      },
    );
    try {
      await file.writeAsBytes(
        snapshotBytes(quantity: 200, capturedAt: '2026-10-01T10:00:00+08:00'),
      );
      await sync.bind(file.path, snapshot());
      final pending = sync.check();
      await sync.stop();
      await pending;
      expect(saves, 0);
    } finally {
      sync.dispose();
      await dir.delete(recursive: true);
    }
  });
}
