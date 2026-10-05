import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';

const testSource = SourceExcerpt(
    id: 'source-1',
    studyId: 's0',
    title: '测试报告',
    url: 'https://example.com/report',
    period: '2025年度',
    disclosedAt: '2026-03-31',
    page: '第10页',
    unit: '万元',
    text: '本年度营业收入为100万元，经营活动现金流为负20万元。测试原文。');
WatchCompany testCompany(String code) => WatchCompany(
    id: 'SH:$code',
    code: code,
    exchange: 'SH',
    name: '测试公司',
    industry: '制造业',
    source: 'https://example.com/company',
    fetchedAt: '2026-09-30T10:00:00Z');
Map<String, dynamic> draftJson(
        {String sourceId = 'source-1', String quote = '本年度营业收入为100万元'}) =>
    {
      'facts': [
        {
          'text': '营收100万元',
          'refs': [
            {'sourceId': sourceId, 'quote': quote}
          ]
        }
      ],
      'support': [],
      'counter': [],
      'missing': [
        {'text': '债务资料不足', 'refs': []}
      ],
      'review': [
        {'text': '下次财报复查现金流', 'refs': []}
      ]
    };

class FakeTransport implements JsonTransport {
  FakeTransport(this.respond);
  final Map<String, dynamic> Function(Uri, Map<String, dynamic>?) respond;
  Uri? uri;
  Map<String, dynamic>? sent;
  @override
  Future<Map<String, dynamic>> request(Uri target,
      {Map<String, String> headers = const {},
      Map<String, dynamic>? body}) async {
    uri = target;
    sent = body;
    return respond(target, body);
  }
}

void main() {
  test(
      'v1 migrates all existing records and keeps an untouched original on disk',
      () async {
    final old = WorkspaceData.demo().toJson()
      ..['schemaVersion'] = 1
      ..remove('watchlist')
      ..remove('sources')
      ..remove('financials');
    final dir = await Directory.systemTemp.createTemp('xigu-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final store = LocalWorkspaceStore(dir), raw = jsonEncode(old);
    await store.file.writeAsString(raw);
    final migrated = await store.load();
    expect(migrated!.studies.first.thesis,
        WorkspaceData.demo().studies.first.thesis);
    expect(migrated.isDemo, true);
    expect(migrated.watchlist, isEmpty);
    expect(await File('${store.file.path}.v1.bak').readAsString(), raw);
    expect(jsonDecode(await store.file.readAsString())['schemaVersion'], 7);
    expect(WorkspaceData.decode(migrated.encode()).holdings.length, 3);
  });
  test(
      'v2 backup rejects a mismatched exchange and preserves valid leading zeroes',
      () {
    final raw = WorkspaceData.empty().toJson();
    final company = testCompany('600000').toJson()
      ..['code'] = '000001'
      ..['id'] = 'SH:000001';
    raw['watchlist'] = [company];
    expect(() => WorkspaceData.decode(jsonEncode(raw)), throwsFormatException);
    company['exchange'] = 'SZ';
    company['id'] = 'SZ:000001';
    final restored = WorkspaceData.decode(jsonEncode(raw));
    expect(restored.watchlist.single.symbol, 'SZ:000001');
    expect(WorkspaceData.decode(restored.encode()).watchlist.single.code,
        '000001');
    for (final invalid in ['00001', '000001 ', 'abcdef']) {
      expect(validAShareSymbol('SZ', invalid), false);
    }
    expect(validAShareSymbol('UNKNOWN', '000001'), false);
    expect(validAShareSymbol('BJ', '920001'), true);
  });
  test(
      'missing money stays null, negative profit/cashflow roundtrips, and mismatched periods cannot compare',
      () {
    final record = FinancialRecord.fromJson({
      'id': 'f1',
      'studyId': 's0',
      'sourceId': 'source-1',
      'start': '2025-01-01',
      'end': '2025-12-31',
      'disclosedAt': '2026-03-31',
      'unit': '万元',
      'revenue': 100,
      'adjustedProfit': -5,
      'operatingCash': -20,
      'cash': null,
      'debt': null
    });
    final data = WorkspaceData.demo()
        .copyWith(sources: [testSource], financials: [record]);
    final restored = WorkspaceData.decode(data.encode()).financials.single;
    expect(restored.cash, isNull);
    expect(restored.debt, isNull);
    expect(restored.operatingCash, -20);
    expect(
        record.comparableWith(FinancialRecord.fromJson(
            {...record.toJson(), 'end': '2025-06-30'})),
        false);
    expect(
        () => WorkspaceData.decode(data.copyWith(financials: [
              FinancialRecord.fromJson(
                  {...record.toJson(), 'sourceId': 'unknown'})
            ]).encode()),
        throwsFormatException);
  });
  test('unknown citations, invented quotes and uncited facts block acceptance',
      () {
    expect(ResearchDraft.fromJson(draftJson()).validate([testSource]), isEmpty);
    expect(
        ResearchDraft.fromJson(draftJson(sourceId: 'fake'))
            .validate([testSource]),
        isNotEmpty);
    expect(
        ResearchDraft.fromJson(draftJson(quote: '不存在的经营利润为300万元'))
            .validate([testSource]),
        isNotEmpty);
    final noRefs = draftJson()
      ..['facts'] = [
        {'text': '无法核验', 'refs': []}
      ];
    expect(ResearchDraft.fromJson(noRefs).validate([testSource]), isNotEmpty);
  });
  test('partial, failed and mixed-date quotes never change portfolio valuation',
      () {
    final h = [
      for (final code in ['600000', '600001'])
        Holding(
            id: code,
            code: code,
            name: '测试',
            industry: '制造',
            quantity: 100,
            price: 10)
    ];
    final c1 = testCompany('600000').quoted(
        11, '2026-09-30', 'https://example.com/quote', '2026-10-01T00:00:00Z');
    final c2 = testCompany('600001').quoted(
        12, '2026-09-29', 'https://example.com/quote', '2026-10-01T00:00:00Z');
    final data = WorkspaceData.empty().copyWith(
        priceDate: '2026-09-28',
        cash: 1000,
        deposits: 3000,
        holdings: h,
        watchlist: [c1, c2]);
    expect(() => applyPortfolioQuotes(data), throwsFormatException);
    expect(() => applyPortfolioQuotes(data.copyWith(watchlist: [c1])),
        throwsFormatException);
    expect(
        () => applyPortfolioQuotes(
            data.copyWith(watchlist: [c1, c2.failed('timeout')])),
        throwsFormatException);
    expect(data.assets, 3000);
    expect(data.priceDate, '2026-09-28');
    final same = c2.quoted(
        12, '2026-09-30', 'https://example.com/quote', '2026-10-01T00:00:00Z');
    final updated = applyPortfolioQuotes(data.copyWith(watchlist: [c1, same]));
    expect(updated.assets, 3300);
    expect(updated.priceDate, '2026-09-30');
    final transferred = WorkspaceData.decode(updated.encode());
    expect(transferred.stressLoss(.3), updated.stressLoss(.3));
    expect(
        () => applyPortfolioQuotes(updated.copyWith(priceDate: '2026-10-01')),
        throwsFormatException);
  });
  test(
      'market discards intraday and future bars, checks identity and preserves leading zeroes',
      () async {
    final transport = FakeTransport((uri, body) => {
          'rc': 0,
          'data': {
            'code': '000001',
            'market': 0,
            'klines': [
              '2026-09-29,10,11',
              '2026-09-30,11,12',
              '2026-10-01,12,999'
            ]
          }
        });
    final market = MarketService(
        transport: transport, clock: () => DateTime.utc(2026, 10, 1, 2));
    final company = WatchCompany(
        id: 'SZ:000001',
        code: '000001',
        exchange: 'SZ',
        name: '测试',
        industry: '银行',
        source: 'https://example.com',
        fetchedAt: '2026-10-01T00:00:00Z');
    final result = await market.quote(company);
    expect(result.close, 12);
    expect(result.tradeDate, '2026-09-30');
    expect(transport.uri!.queryParameters['secid'], '0.000001');
    expect(transport.uri!.queryParameters['fqt'], '0');
    expect(() => market.lookup('SH', '000001'), throwsA(isA<ServiceFailure>()));
    final bad = MarketService(
        transport: FakeTransport((u, b) => {
              'rc': 0,
              'data': {
                'code': '999999',
                'market': 0,
                'klines': ['2026-09-30,11,12']
              }
            }));
    expect(() => bad.quote(company), throwsA(isA<ServiceFailure>()));
  });
  test(
      'company lookup verifies market identity even when returned code matches',
      () async {
    final transport = FakeTransport((uri, body) => {
          'rc': 0,
          'data': {'f107': 0, 'f57': '600000', 'f58': '错误市场的公司', 'f127': '银行'}
        });
    final market = MarketService(transport: transport);
    await expectLater(
        market.lookup('SH', '600000'), throwsA(isA<ServiceFailure>()));
    expect(
        transport.uri!.queryParameters['fields']!.split(','), contains('f107'));
    for (final entry
        in {'SH': '600000', 'SZ': '000001', 'BJ': '920001'}.entries) {
      final matching = MarketService(
          transport: FakeTransport((uri, body) => {
                'rc': 0,
                'data': {
                  'f107': entry.key == 'SH' ? 1 : 0,
                  'f57': entry.value,
                  'f58': '正确市场的公司',
                  'f127': '银行'
                }
              }));
      final company = await matching.lookup(entry.key, entry.value);
      expect(company.symbol, '${entry.key}:${entry.value}');
    }
    final missing = MarketService(
        transport: FakeTransport((uri, body) => {
              'rc': 0,
              'data': {'f57': '000001', 'f58': '未确认市场的公司'}
            }));
    await expectLater(
        missing.lookup('SZ', '000001'), throwsA(isA<ServiceFailure>()));
  });
  test(
      'DeepSeek sends only chosen excerpts with JSON mode and rejects truncated responses',
      () async {
    final t = FakeTransport((u, b) => {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': jsonEncode(draftJson())}
            }
          ]
        });
    final result = await DeepSeekService(transport: t).draft(
        key: 'test-sentinel',
        model: 'deepseek-flash',
        company: '测试',
        sources: [testSource]);
    expect(result.validate([testSource]), isEmpty);
    expect(t.uri!.toString(), 'https://api.deepseek.com/chat/completions');
    expect(t.sent!['response_format'], {'type': 'json_object'});
    expect(jsonEncode(t.sent), isNot(contains('test-sentinel')));
    expect(jsonEncode(t.sent), isNot(contains('holdings')));
    final broken = DeepSeekService(
        transport: FakeTransport((u, b) => {
              'choices': [
                {
                  'finish_reason': 'length',
                  'message': {'content': jsonEncode(draftJson())}
                }
              ]
            }));
    expect(
        () => broken.draft(
            key: 'test',
            model: 'deepseek-flash',
            company: '测试',
            sources: [testSource]),
        throwsA(isA<ServiceFailure>()));
  });
  test(
      'HTTP client does not forward credentials across redirects or expose response bodies',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((r) async {
      requests++;
      r.response.statusCode = 302;
      r.response.headers.set('location', '/secret-destination');
      r.response.write('test-secret-private-body');
      await r.response.close();
    });
    try {
      await IoJsonTransport(useWindowsProxy: false).request(
          Uri.parse('http://127.0.0.1:${server.port}/start'),
          headers: {'Authorization': 'Bearer test-secret'});
      fail('Redirect must fail');
    } catch (e) {
      expect('$e', contains('302'));
      expect('$e', isNot(contains('test-secret')));
    }
    expect(requests, 1);
  });
}
