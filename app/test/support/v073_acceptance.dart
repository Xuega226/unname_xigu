// Fictional evidence, memory credentials and offline model responses only.
// The same production dialog and disk-backed backup checks run on both devices.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/financial_widgets.dart';
import 'package:lianghua_assistant/reports.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

import 'v07_fixture.dart';

const v073Sentinel = 'v073-offline-test-only-sentinel';
const v073Text =
    '虚构制造 600001 2025年度合并财务报表。报告期间2025年1月1日至2025年12月31日，'
    '单位：万元。本期营业收入100.00，扣除非经常性损益后的净利润-8.00，'
    '经营活动产生的现金流量净额-20.00，现金及现金等价物余额30.00，有息负债50.00。'
    '比较期2024年度营业收入80.00。';

WorkspaceData v073Fixture() {
  final data = v07Fixture();
  final doc = ReportDocument(
    id: 'v073-report',
    studyId: data.studies.single.id,
    fileName: 'fictional-report-2025.pdf',
    sha256: 'a' * 64,
    title: '虚构制造2025年度报告',
    url: 'https://example.com/fictional-report-2025',
    period: '2025年度',
    start: '2025-01-01',
    end: '2025-12-31',
    disclosedAt: '2026-04-01',
    unit: '万元',
    importedAt: '2026-10-05T00:00:00+08:00',
    pageCount: 1,
    pages: const [ReportPage(number: 1, text: v073Text)],
  );
  return data.copyWith(
    sources: [...doc.excerpts(), ...data.sources],
    documents: [doc],
    financials: [],
  );
}

List<Map<String, dynamic>> v073Candidates(List<SourceExcerpt> sources) => [
  for (final field in [
    ('revenue', '营业收入', '100.00'),
    ('adjustedProfit', '扣除非经常性损益后的净利润', '-8.00'),
    ('operatingCash', '经营活动产生的现金流量净额', '-20.00'),
    ('cash', '现金及现金等价物余额', '30.00'),
    ('debt', '有息负债', '50.00'),
  ])
    {
      'metric': field.$1,
      'label': field.$2,
      'rawValue': field.$3,
      'unit': '万元',
      'start': '2025-01-01',
      'end': '2025-12-31',
      'scope': '合并',
      'sourceId': sources.first.id,
      'quote': sources.first.text,
    },
];

Map<String, dynamic> v073ModelResponse(Map<String, dynamic> content) => {
  'choices': [
    {
      'finish_reason': 'stop',
      'message': {'content': jsonEncode(content)},
    },
  ],
  'usage': {'prompt_tokens': 120, 'completion_tokens': 80, 'total_tokens': 200},
};

// Kept reusable by older flow fixtures as their protocol gains a second call.
Map<String, dynamic> v073PassingReview(Map<String, dynamic> payload) =>
    v073ModelResponse({
      'reviews': [
        for (final entry in (payload['candidates'] as List).indexed)
          {
            'index': entry.$1,
            'verdict': 'pass',
            'reason': '虚构离线复核：本期、指标、期间、单位和口径一致。',
            'sourceId': (entry.$2 as Map)['sourceId'],
            'quote': (entry.$2 as Map)['quote'],
          },
      ],
    });

Map<String, dynamic> v073ReviewOr(
  Map<String, dynamic>? body,
  Map<String, dynamic> extraction,
) {
  final payload = jsonDecode(
    (body!['messages'] as List).last['content'] as String,
  ) as Map<String, dynamic>;
  return payload.containsKey('candidates')
      ? v073PassingReview(payload)
      : extraction;
}

class V073OfflineTransport implements JsonTransport {
  V073OfflineTransport({this.candidates, this.verdicts = const {}});
  final List<Map<String, dynamic>>? candidates;
  final Map<int, String> verdicts;
  final requests = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  int? failAt;
  bool malformedReview = false;

  @override
  Future<Map<String, dynamic>> request(
    Uri uri, {
    Map<String, String> headers = const {},
    Map<String, dynamic>? body,
  }) async {
    expect(uri, Uri.https('api.deepseek.com', '/chat/completions'));
    expect(headers['Authorization'], 'Bearer $v073Sentinel');
    final payload = jsonDecode(
      (body!['messages'] as List).last['content'] as String,
    ) as Map<String, dynamic>;
    requests.add(payload);
    // Only public excerpts and necessary report metadata may be sent.
    expect(payload.containsKey('holdings'), isFalse);
    expect(payload.containsKey('deposits'), isFalse);
    expect(jsonEncode(payload), isNot(contains(v073Sentinel)));
    if (failAt == requests.length) throw ServiceFailure('离线夹具模拟模型超时');
    if (pending != null) return pending!.future;
    if (payload.containsKey('candidates')) {
      if (malformedReview) return v073ModelResponse({'reviews': []});
      final response = v073PassingReview(payload);
      final message = (response['choices'] as List).single['message'] as Map;
      final decoded = jsonDecode(message['content'] as String) as Map;
      for (final entry in (decoded['reviews'] as List).cast<Map>()) {
        final verdict = verdicts[entry['index']];
        if (verdict != null) {
          entry['verdict'] = verdict;
          entry['reason'] = '虚构复核：本期列或指标含义仍需处理。';
        }
      }
      message['content'] = jsonEncode(decoded);
      return response;
    }
    return v073ModelResponse({
      'candidates': candidates ?? v073Candidates(v073Fixture().sources),
      'missing': candidates?.isEmpty == true ? ['五项资料均不足'] : [],
      'notes': [],
    });
  }
}

Future<void> v073Settle(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
        find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('v073 acceptance task did not finish');
}

Future<void> v073Tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(finder);
  await v073Settle(tester);
}

// Legacy excerpts lack explicit financial-statement headers. Tests must choose
// their fictional target scope rather than relying on an unverified default.
Future<void> v073SelectLegacyScope(WidgetTester tester) async {
  await v073Tap(
    tester,
    find.widgetWithText(DropdownButtonFormField<String>, '目标报表口径'),
  );
  await v073Tap(tester, find.text('合并').last);
}

Future<void> v073DialogHost(
  WidgetTester tester, {
  required V073OfflineTransport transport,
  required Future<bool> Function(FinancialRecord) save,
  double scale = 1,
  List<FinancialRecord> records = const [],
  bool specialIndustry = false,
  GlobalKey? captureKey,
  String? fontFamily,
}) async {
  final data = v073Fixture();
  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: MaterialApp(
        theme: ThemeData(fontFamily: fontFamily),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => FinancialExtractionDialog(
                  study: data.studies.single,
                  sources: data.sources,
                  documents: data.documents,
                  store: MemoryCredentialStore(
                    const AiSettings(key: v073Sentinel),
                  ),
                  service: DeepSeekService(transport: transport),
                  save: save,
                  records: records,
                  specialIndustry: specialIndustry,
                ),
              ),
              child: const Text('open-v073'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-v073'));
  await tester.pumpAndSettle();
}

Finder get _send => find.text('发送范围并预核验');
Finder get _save => find.text('确认并保存可采纳字段');

void registerV073Acceptance({bool native = false}) {
  testWidgets(
    'v073 five defaults one adoption disk reopen and backup preserve audit',
    (tester) async {
      if (!native) {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('xigu-v073-acceptance-'),
      ))!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          final temp = await Directory.systemTemp.resolveSymbolicLinks();
          final resolved = await root.resolveSymbolicLinks();
          if (!resolved.startsWith('$temp${Platform.pathSeparator}') ||
              !root.uri.pathSegments
                  .where((s) => s.isNotEmpty)
                  .last
                  .startsWith('xigu-v073-acceptance-')) {
            throw StateError('Cleanup escaped v073 test directory');
          }
          await root.delete(recursive: true);
        });
      });
      final store = LocalWorkspaceStore(Directory('${root.path}/first'));
      final initial = v073Fixture();
      await tester.runAsync(() => store.save(initial));
      var saves = 0;
      FinancialRecord? adopted;
      final transport = V073OfflineTransport();
      await v073DialogHost(
        tester,
        transport: transport,
        save: (record) async {
          saves++;
          adopted = record;
          await store.save(initial.copyWith(financials: [record]));
          return true;
        },
      );
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .map((f) => f.controller!.text),
        containsAll(['2025-01-01', '2025-12-31']),
      );
      await v073Tap(tester, _send);
      expect(transport.requests.length, 2);
      expect(saves, 0);
      expect((await tester.runAsync(store.load))!.encode(), initial.encode());
      for (var i = 0; i < 5; i++) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('financial-candidate-$i')),
            matching: find.text('已纳入本次确认'),
          ),
          findsOneWidget,
        );
      }
      await v073Tap(tester, _save);
      expect(saves, 1);
      expect(adopted!.revenue, 100);
      expect(adopted!.adjustedProfit, -8);
      expect(adopted!.operatingCash, -20);
      expect(adopted!.cash, 30);
      expect(adopted!.debt, 50);
      expect(adopted!.origin, 'aiConfirmed');
      expect(adopted!.evidence.length, 5);
      final audit = adopted!.toJson()['audit'] as Map;
      expect(audit['method'], 'reportConfirmed');
      expect(audit['selected'], [0, 1, 2, 3, 4]);
      expect(audit['reviews'], hasLength(5));
      expect(audit['fingerprint'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect((audit['usage'] as List).map((u) => u['total_tokens']), [
        200,
        200,
      ]);
      final first = (await tester.runAsync(store.load))!;
      expect(first.financials.single.toJson(), adopted!.toJson());
      expect(first.cash, initial.cash);
      expect(first.holdings.single.toJson(), initial.holdings.single.toJson());
      expect(first.quant.toJson(), initial.quant.toJson());
      final backup = first.encode();
      expect(backup, isNot(contains(v073Sentinel)));
      final second = LocalWorkspaceStore(Directory('${root.path}/second'));
      await tester.runAsync(() => second.save(WorkspaceData.decode(backup)));
      expect((await tester.runAsync(second.load))!.encode(), backup);
      final imported = const String.fromEnvironment('V073_IMPORT_FIXTURE');
      if (imported.isNotEmpty) {
        final foreignText = (await tester.runAsync(
          () => File(imported).readAsString(),
        ))!;
        final foreign = WorkspaceData.decode(foreignText);
        final restored = LocalWorkspaceStore(Directory('${root.path}/foreign'));
        await tester.runAsync(() => restored.save(foreign));
        expect(
          (await tester.runAsync(restored.load))!.encode(),
          foreign.encode(),
        );
        expect(foreign.financials.single.audit, isNotNull);
        expect(foreign.financials.single.revenue, 100);
        expect(foreign.financials.single.operatingCash, -20);
        debugPrint(
          'V073_CROSS_RESTORE platform=${Platform.operatingSystem} schema=8 exact=true fieldsEvidenceAuditRulesFunding=true',
        );
      }
      final output = const String.fromEnvironment('V073_EXPORT_FIXTURE');
      if (output == 'stdout') {
        debugPrint(
          'V073_BACKUP_BASE64=${base64Encode(utf8.encode(backup))}',
          wrapWidth: 30000,
        );
      } else if (output.isNotEmpty) {
        await tester.runAsync(
          () => File(output).writeAsString(backup, flush: true),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'v073 semantic exceptions and hard errors stay outside defaults',
    (tester) async {
      final candidates = v073Candidates(v073Fixture().sources);
      candidates[4] = {...candidates[4], 'rawValue': '999.00'};
      FinancialRecord? adopted;
      final transport = V073OfflineTransport(
        candidates: candidates,
        verdicts: {0: 'fail', 3: 'unknown'},
      );
      await v073DialogHost(
        tester,
        transport: transport,
        save: (record) async {
          adopted = record;
          return true;
        },
      );
      await v073Tap(tester, _send);
      for (final i in [0, 3, 4]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('financial-candidate-$i')),
            matching: find.text('未纳入本次确认'),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('financial-candidate-4')),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
      await v073Tap(tester, _save);
      expect(adopted!.revenue, isNull);
      expect(adopted!.cash, isNull);
      expect(adopted!.debt, isNull);
      expect(adopted!.adjustedProfit, -8);
      expect(adopted!.operatingCash, -20);
    },
  );

  testWidgets(
    'v073 insufficient report skips reviewer and never saves empty record',
    (tester) async {
      var saves = 0;
      final transport = V073OfflineTransport(candidates: []);
      await v073DialogHost(
        tester,
        transport: transport,
        save: (_) async {
          saves++;
          return true;
        },
      );
      await v073Tap(tester, _send);
      expect(transport.requests.length, 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '确认并保存可采纳字段'),
            )
            .onPressed,
        isNull,
      );
      expect(saves, 0);
    },
  );

  for (final mode in ['review-failure', 'malformed-review']) {
    testWidgets('v073 $mode cannot create adopted state', (tester) async {
      var saves = 0;
      final transport = V073OfflineTransport();
      if (mode == 'review-failure') {
        transport.failAt = 2;
      } else {
        transport.malformedReview = true;
      }
      await v073DialogHost(
        tester,
        transport: transport,
        save: (_) async {
          saves++;
          return true;
        },
      );
      await v073Tap(tester, _send);
      expect(transport.requests.length, 2);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '确认并保存可采纳字段'),
            )
            .onPressed,
        isNull,
      );
      expect(saves, 0);
    });
  }

  testWidgets(
    'v073 save failure keeps candidates and explicit retry adopts once',
    (tester) async {
      var attempts = 0;
      final adopted = <FinancialRecord>[];
      await v073DialogHost(
        tester,
        transport: V073OfflineTransport(),
        save: (record) async {
          attempts++;
          if (attempts == 1) return false;
          adopted.add(record);
          return true;
        },
      );
      await v073Tap(tester, _send);
      await v073Tap(tester, _save);
      expect(attempts, 1);
      expect(adopted, isEmpty);
      expect(find.byType(FinancialExtractionDialog), findsOneWidget);
      await v073Tap(tester, _save);
      expect(attempts, 2);
      expect(adopted.length, 1);
      expect(find.byType(FinancialExtractionDialog), findsNothing);
    },
  );

  testWidgets('v073 closing while extracting ignores late response', (
    tester,
  ) async {
    var saves = 0;
    final transport = V073OfflineTransport()..pending = Completer();
    await v073DialogHost(
      tester,
      transport: transport,
      save: (_) async {
        saves++;
        return true;
      },
    );
    await tester.ensureVisible(_send);
    await tester.tap(_send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(transport.requests.length, 1);
    final context = tester.element(find.byType(FinancialExtractionDialog));
    Navigator.of(context).pop();
    await tester.pump(const Duration(milliseconds: 300));
    transport.pending!.complete(
      v073ModelResponse({
        'candidates': v073Candidates(v073Fixture().sources),
        'missing': [],
        'notes': [],
      }),
    );
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(transport.requests.length, 1);
    expect(find.byType(FinancialExtractionDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'v073 period changes invalidate prior review without hidden requests',
    (tester) async {
      var saves = 0;
      final transport = V073OfflineTransport();
      await v073DialogHost(
        tester,
        transport: transport,
        save: (_) async {
          saves++;
          return true;
        },
      );
      await v073Tap(tester, _send);
      final input = find.widgetWithText(TextFormField, '报告结束日期');
      await tester.ensureVisible(input);
      await tester.enterText(input, '2024-12-31');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('financial-candidate-0')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('financial-save')))
            .onPressed,
        isNull,
      );
      expect(transport.requests.length, 2);
      expect(saves, 0);
    },
  );

  testWidgets(
    'v073 stopped extraction cannot replace the explicitly restarted result',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final transport = V073OfflineTransport()..pending = pending;
      FinancialRecord? adopted;
      await v073DialogHost(
        tester,
        transport: transport,
        save: (record) async {
          adopted = record;
          return true;
        },
      );
      await tester.ensureVisible(_send);
      await tester.tap(_send);
      await tester.pump(const Duration(milliseconds: 100));
      expect(transport.requests.length, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('financial-start')),
            )
            .onPressed,
        isNull,
      );
      await v073Tap(tester, find.byKey(const ValueKey('financial-stop')));
      transport.pending = null;
      await v073Tap(tester, _send);
      expect(transport.requests.length, 3);
      pending.complete(
        v073ModelResponse({
          'candidates': [],
          'missing': ['过期响应'],
          'notes': [],
        }),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('过期响应'), findsNothing);
      await v073Tap(tester, _save);
      expect(adopted!.evidence.length, 5);
      expect(transport.requests.length, 3);
    },
  );

  testWidgets(
    'v073 special industry isolates unsupported metrics from normal defaults',
    (tester) async {
      FinancialRecord? adopted;
      await v073DialogHost(
        tester,
        transport: V073OfflineTransport(),
        specialIndustry: true,
        save: (record) async {
          adopted = record;
          return true;
        },
      );
      await v073Tap(tester, _send);
      expect(find.text('排除此项'), findsNWidgets(2));
      for (final i in [2, 3, 4]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('financial-candidate-$i')),
            matching: find.textContaining('不适用'),
          ),
          findsOneWidget,
        );
      }
      await v073Tap(tester, _save);
      expect(adopted!.revenue, 100);
      expect(adopted!.adjustedProfit, -8);
      expect(adopted!.operatingCash, isNull);
      expect(adopted!.cash, isNull);
      expect(adopted!.debt, isNull);
    },
  );

  testWidgets('v073 identical fields and audit block duplicate adoption', (
    tester,
  ) async {
    FinancialRecord? first;
    await v073DialogHost(
      tester,
      transport: V073OfflineTransport(),
      save: (record) async {
        first = record;
        return true;
      },
    );
    await v073Tap(tester, _send);
    await v073Tap(tester, _save);
    var duplicateSaves = 0;
    await v073DialogHost(
      tester,
      transport: V073OfflineTransport(),
      records: [first!],
      save: (_) async {
        duplicateSaves++;
        return true;
      },
    );
    await v073Tap(tester, _send);
    await v073Tap(tester, _save);
    expect(duplicateSaves, 0);
    expect(find.text('相同字段与证据已保存，无需重复提交'), findsOneWidget);
  });

  if (!native) {
    testWidgets(
      'v073 390px 2x text summary evidence and final adoption stay reachable',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        FinancialRecord? adopted;
        await v073DialogHost(
          tester,
          transport: V073OfflineTransport(),
          scale: 2,
          save: (record) async {
            adopted = record;
            return true;
          },
        );
        await v073Tap(tester, _send);
        await v073Tap(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('financial-candidate-0')),
            matching: find.byType(ExpansionTile),
          ),
        );
        expect(find.textContaining('原文'), findsWidgets);
        await v073Tap(tester, _save);
        expect(adopted!.evidence.length, 5);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
