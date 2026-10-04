import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/report_fetch.dart';
import 'package:lianghua_assistant/services.dart';

class QueueReportTransport implements ReportFetchTransport {
  QueueReportTransport(this.responses);
  final List<ReportFetchResponse> responses;
  final List<Uri> uris = [];
  final List<Map<String, String>?> forms = [];
  @override
  Future<ReportFetchResponse> request(
    Uri uri, {
    Map<String, String>? form,
  }) async {
    uris.add(uri);
    forms.add(form);
    if (responses.isEmpty) throw StateError('Unexpected network request');
    return responses.removeAt(0);
  }
}

class PendingReportTransport implements ReportFetchTransport {
  final response = Completer<ReportFetchResponse>();
  @override
  Future<ReportFetchResponse> request(Uri uri, {Map<String, String>? form}) =>
      response.future;
}

ReportFetchResponse jsonResponse(Object json) {
  final bytes = utf8.encode(jsonEncode(json));
  return ReportFetchResponse(
    200,
    Stream.value(bytes),
    contentLength: bytes.length,
  );
}

ReportFetchResponse companyResponse({
  String code = '600660',
  String orgId = 'gssh0600660',
  String category = 'A股',
}) => jsonResponse([
  {
    'code': code,
    'orgId': orgId,
    'zwjc': '测试公司',
    'category': category,
    'type': 'shj',
  },
]);

Map<String, Object> announcement({
  String id = '1001',
  int year = 2025,
  String? title,
  String code = '600660',
  String orgId = 'gssh0600660',
  String? path,
  DateTime? disclosed,
}) {
  final date = disclosed ?? DateTime.utc(year + 1, 3, 18);
  final day =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return {
    'secCode': code,
    'secName': '测试公司',
    'orgId': orgId,
    'announcementId': id,
    'announcementTitle': title ?? '测试公司$year年年度报告',
    'announcementTime': date.millisecondsSinceEpoch,
    'adjunctType': 'PDF',
    'adjunctUrl': path ?? 'finalpage/$day/$id.PDF',
  };
}

ReportFetchResponse announcementResponse(
  List<Object> rows, {
  bool more = false,
  int? total,
}) => jsonResponse({
  'announcements': rows,
  'hasMore': more,
  'totalAnnouncement': total ?? rows.length,
});

ReportFetchService service(
  QueueReportTransport transport, {
  int maxPages = 10,
}) => ReportFetchService(
  transport: transport,
  clock: () => DateTime(2026, 10, 3),
  maxPages: maxPages,
);

ReportAnnouncement report({Uri? url}) => ReportAnnouncement(
  id: '1001',
  code: '600660',
  exchange: 'SH',
  companyName: '测试公司',
  title: '2025年年度报告',
  url:
      url ??
      Uri.parse('https://static.cninfo.com.cn/finalpage/2026-03-18/1001.PDF'),
  start: DateTime(2025, 1, 1),
  end: DateTime(2025, 12, 31),
  disclosedAt: DateTime(2026, 3, 18),
  isRevision: false,
  year: 2025,
);

Matcher failureContaining(String text) =>
    isA<ServiceFailure>().having((e) => e.message, 'message', contains(text));

void main() {
  test('A response opened after timeout is closed without reading its body or reporting progress', () async {
    final transport = PendingReportTransport();
    var closes = 0;
    var listened = false;
    var progressCalls = 0;
    final body = StreamController<List<int>>(onListen: () => listened = true);
    final pending = ReportFetchService(
      transport: transport,
      timeout: const Duration(milliseconds: 15),
    ).download(report(), progress: (_, _) => progressCalls++);
    await expectLater(pending, throwsA(failureContaining('超时')));
    transport.response.complete(
      ReportFetchResponse(200, body.stream, close: () => closes++),
    );
    await Future<void>.delayed(Duration.zero);
    expect(closes, 1);
    expect(listened, isFalse);
    expect(progressCalls, 0);
    unawaited(body.close());
  });
  test('Company-name environment keyword is not mistaken for an environmental report, notices without 公告 suffix excluded', () async {
    final t = QueueReportTransport([
      companyResponse(),
      announcementResponse([
        announcement(title: '天源环境2025年年度报告'),
        announcement(id: '1002', title: '天源环境：2025 年年度报告'),
        announcement(id: '2002', title: '关于2025年年度报告'),
        announcement(id: '2003', title: '2025年年度报告（2026年4月修订）'),
      ]),
    ]);
    final result = await service(t).search('SH', '600660');
    expect(result.reports.map((r) => r.id), ['1001', '1002']);
    expect(result.reports.last.title, '天源环境：2025 年年度报告');
    expect(result.warnings.join(), contains('修订年报标题格式暂不支持'));
  });
  test('Six-digit code and exchange validated before any network, BJ explicit fallback', () async {
    final t = QueueReportTransport([]);
    for (final value in [
      ('SH', '000001'),
      ('SZ', '600660'),
      ('SH', '60066'),
      ('SZ', '200001'),
      ('sh', '600660'),
    ]) {
      await expectLater(
        service(t).search(value.$1, value.$2),
        throwsA(failureContaining('六位')),
      );
    }
    await expectLater(
      service(t).search('BJ', '920001'),
      throwsA(failureContaining('北交所')),
    );
    expect(t.uris, isEmpty);
  });

  test('Official company must be a unique A-share with exact code and valid organization ID', () async {
    for (final response in [
      companyResponse(orgId: 'invalid'),
      companyResponse(category: '债券'),
      companyResponse(code: '600661'),
      jsonResponse([]),
      jsonResponse([
        {'code': '600660', 'category': 'A股'},
        {'code': '600660', 'category': 'A股'},
      ]),
    ]) {
      final t = QueueReportTransport([response]);
      await expectLater(
        service(t).search('SH', '600660'),
        throwsA(isA<ServiceFailure>()),
      );
      expect(t.uris.length, 1);
    }
  });

  test('Returns three complete annual reports, preserves original date and official PDF links', () async {
    final t = QueueReportTransport([
      companyResponse(),
      announcementResponse([
        announcement(year: 2024, id: '1002'),
        announcement(year: 2025),
        announcement(year: 2023, id: '1003'),
      ]),
    ]);
    final result = await service(t).search('SH', '600660');
    expect(result.reports.map((r) => r.year), [2025, 2024, 2023]);
    expect(result.missingYears, isEmpty);
    expect(result.warnings, isEmpty);
    expect(result.companyName, '测试公司');
    expect(result.reports.first.disclosedAt, DateTime(2026, 3, 18));
    expect(result.reports.first.start, DateTime(2025, 1, 1));
    expect(result.reports.first.end, DateTime(2025, 12, 31));
    expect(result.reports.first.fileName, '600660_2025_1001.pdf');
    expect(result.reports.first.sourceUrl, contains('announcementId=1001'));
    expect(t.forms[1]!['stock'], '600660,gssh0600660');
    expect(t.forms[1]!['column'], 'sse');
    expect(t.forms[1]!['seDate'], '2024-01-01~2026-10-03');
    expect(t.uris.every((uri) => uri.scheme == 'https'), isTrue);
  });

  test(
    'SZ top-search type can also be shj, code prefix determines market',
    () async {
      final t = QueueReportTransport([
        companyResponse(code: '000001', orgId: 'gssz0000001'),
        announcementResponse([
          announcement(code: '000001', orgId: 'gssz0000001'),
        ]),
      ]);
      final result = await service(t).search('SZ', '000001');
      expect(result.reports.single.code, '000001');
      expect(t.forms.last!['column'], 'szse');
    },
  );

  test('Numeric issuer IDs support new listings and both exchanges, preserve exact announcement ownership', () async {
    for (final issuer in [
      ('SZ', '001246', '9900057193'),
      ('SH', '603001', '9900042959'),
    ]) {
      final t = QueueReportTransport([
        companyResponse(code: issuer.$2, orgId: issuer.$3),
        announcementResponse([
          announcement(code: issuer.$2, orgId: issuer.$3),
          announcement(id: '2001', code: '000001', orgId: issuer.$3),
          announcement(id: '2002', code: issuer.$2, orgId: '9900000001'),
        ]),
      ]);
      final result = await service(t).search(issuer.$1, issuer.$2);
      expect(result.code, issuer.$2);
      expect(result.reports.single.id, '1001');
      expect(result.warnings.join(), contains('归属不匹配'));
      expect(t.forms.last!['stock'], '${issuer.$2},${issuer.$3}');
      expect(t.forms.last!['column'], issuer.$1 == 'SH' ? 'sse' : 'szse');
    }
  });

  test('New listing without annual reports returns missing years instead of rejecting identity', () async {
    final t = QueueReportTransport([
      companyResponse(code: '001246', orgId: '9900057193'),
      announcementResponse([]),
    ]);
    final result = await service(t).search('SZ', '001246');
    expect(result.code, '001246');
    expect(result.reports, isEmpty);
    expect(result.missingYears, [2025, 2024, 2023]);
    expect(result.warnings.join(), contains('不代表公司未披露'));
    expect(result.warnings.join(), contains('招股说明书'));
    expect(t.forms.last!['stock'], '001246,9900057193');
  });

  test('Shanshui 301190 accepts official gfbj ID and retrieves three years without mixing issuers', () async {
    final t = QueueReportTransport([
      companyResponse(code: '301190', orgId: 'gfbj0871838'),
      announcementResponse([
        for (final year in [2025, 2024, 2023])
          announcement(
            id: '$year',
            year: year,
            code: '301190',
            orgId: 'gfbj0871838',
          ),
        announcement(id: '9001', code: '871838', orgId: 'gfbj0871838'),
        announcement(id: '9002', code: '301190', orgId: 'gssz0301190'),
      ]),
    ]);
    final result = await service(t).search('SZ', '301190');
    expect(result.reports.map((r) => r.year), [2025, 2024, 2023]);
    expect(result.missingYears, isEmpty);
    expect(result.warnings.join(), contains('归属不匹配'));
    expect(t.forms.last!['stock'], '301190,gfbj0871838');
    expect(t.forms.last!['column'], 'szse');
  });

  test('Legacy organization prefixes and suffixes do not determine security identity', () async {
    for (final orgId in ['gssh0001246', 'gssz0001247']) {
      final t = QueueReportTransport([
        companyResponse(code: '001246', orgId: orgId),
        announcementResponse([
          announcement(code: '001246', orgId: orgId),
          announcement(id: '9001', code: '001247', orgId: orgId),
        ]),
      ]);
      final result = await service(t).search('SZ', '001246');
      expect(result.reports.single.code, '001246');
      expect(t.forms.last!['column'], 'szse');
    }
  });

  test('Issuer IDs do not relax unique A-share, exact code, or malformed ID checks', () async {
    for (final response in [
      companyResponse(code: '001246', orgId: '9900057193', category: '港股'),
      companyResponse(code: '001247', orgId: '9900057193'),
      ...[
        '',
        '990005719',
        '99000571931',
        '0000000000',
        ' 9900057193',
        '9900057193 ',
        '9900057193,other',
        '990005719x',
        '-9900057193',
        'gfbj',
        'gfbj0871838,other',
        'gfbj087183x',
        'gfbj0871838 ',
        'gfbj${'0' * 17}',
      ].map((id) => companyResponse(code: '001246', orgId: id)),
      jsonResponse([
        {
          'code': '001246',
          'category': 'A股',
          'orgId': 9900057193,
          'zwjc': '力勤资源',
        },
      ]),
      jsonResponse([
        {
          'code': '001246',
          'category': 'A股',
          'orgId': '9900057193',
          'zwjc': '力勤资源',
        },
        {
          'code': '001246',
          'category': 'A股',
          'orgId': '9900000001',
          'zwjc': '其他公司',
        },
      ]),
    ]) {
      final t = QueueReportTransport([response]);
      await expectLater(
        service(t).search('SZ', '001246'),
        throwsA(isA<ServiceFailure>()),
      );
      expect(t.uris.length, 1);
    }
  });

  test('Excludes summaries, English versions, audit/proposal notices, obsolete years and other securities', () async {
    final excludedTitles = [
      '2025年年度报告摘要',
      '2025年年度报告（英文版）',
      '2025年年度报告审计报告',
      '关于取消2025年年度报告的公告',
      '关于2025年年度报告的议案',
      '2025年年度报告更正公告',
      '2025年年度报告董事会说明',
      '2025年第三季度报告',
      '2025年半年度报告',
    ];
    final rows = <Object>[
      announcement(),
      ...excludedTitles.indexed.map(
        (v) => announcement(id: '${2000 + v.$1}', title: v.$2),
      ),
      announcement(id: '3001', year: 2022),
      announcement(id: '3002', code: '600661'),
      announcement(id: '3003', orgId: 'gssh0600661'),
    ];
    final result = await service(
      QueueReportTransport([companyResponse(), announcementResponse(rows)]),
    ).search('SH', '600660');
    expect(result.reports.map((r) => r.id), ['1001']);
    expect(result.missingYears, [2024, 2023]);
    expect(result.warnings.join(), contains('归属不匹配'));
  });

  test('Revision and same-year variants retained, duplicate announcement IDs removed, no preferred version', () async {
    final revised = announcement(
      id: '1002',
      title: '测试公司2025年年度报告（修订版）',
      disclosed: DateTime.utc(2026, 4, 18),
    );
    final t = QueueReportTransport([
      companyResponse(),
      announcementResponse([announcement(), revised, revised]),
    ]);
    final result = await service(t).search('SH', '600660');
    expect(result.reports.length, 2);
    expect(result.reports.where((r) => r.isRevision).length, 1);
    expect(result.warnings.join(), contains('列表顺序不代表推荐版本'));
  });

  test('Reads all pages even totalpages is zero, warns if cap or empty page leaves incomplete results', () async {
    final t = QueueReportTransport([
      companyResponse(),
      announcementResponse([announcement()], more: true, total: 3),
      announcementResponse([
        announcement(id: '1002', year: 2024),
        announcement(id: '1003', year: 2023),
      ], total: 3),
    ]);
    expect((await service(t).search('SH', '600660')).reports.length, 3);
    expect(t.forms.last!['pageNum'], '2');
    final capped = QueueReportTransport([
      companyResponse(),
      announcementResponse([announcement()], more: true, total: 3),
    ]);
    expect(
      (await service(
        capped,
        maxPages: 1,
      ).search('SH', '600660')).warnings.join(),
      contains('分页未全部读取'),
    );
    final empty = QueueReportTransport([
      companyResponse(),
      announcementResponse([], more: true, total: 3),
    ]);
    expect(
      (await service(empty).search('SH', '600660')).warnings.join(),
      contains('分页未全部读取'),
    );
  });

  test('Skips mismatched path IDs, timestamps, future dates and external attachment paths with warnings', () async {
    final wrongDate = announcement(id: '2001')
      ..['announcementTime'] = DateTime.utc(2026, 3, 19).millisecondsSinceEpoch;
    final rows = <Object>[
      wrongDate,
      announcement(id: '2002', path: 'finalpage/2026-03-18/9999.PDF'),
      announcement(id: '2003', path: 'https://evil.example/2003.PDF'),
      announcement(id: '2004', disclosed: DateTime.utc(2027, 3, 18)),
      announcement(id: '2005', disclosed: DateTime.utc(2025, 3, 18)),
      announcement(id: '2006', path: 'finalpage/2026-02-31/2006.PDF'),
    ];
    final result = await service(
      QueueReportTransport([companyResponse(), announcementResponse(rows)]),
    ).search('SH', '600660');
    expect(result.reports, isEmpty);
    expect(result.missingYears, [2025, 2024, 2023]);
    expect(result.warnings.join(), contains('已略过'));
  });

  test('Malformed JSON/announcement schema fails rather than silently presenting no reports', () async {
    for (final response in [
      jsonResponse({'announcements': [], 'hasMore': false}),
      jsonResponse({
        'announcements': 'bad',
        'totalAnnouncement': 0,
        'hasMore': false,
      }),
      ReportFetchResponse(
        200,
        Stream.value(utf8.encode('<html>blocked</html>')),
      ),
    ]) {
      await expectLater(
        service(QueueReportTransport([companyResponse(), response]))
            .search('SH', '600660'),
        throwsA(isA<ServiceFailure>()),
      );
    }
  });

  test(
    'Download bounded bytes and progress, closes response after success',
    () async {
      var closed = false;
      final bytes = utf8.encode('%PDF-1.7\nfixture');
      final t = QueueReportTransport([
        ReportFetchResponse(
          200,
          Stream.fromIterable([bytes.sublist(0, 6), bytes.sublist(6)]),
          contentLength: bytes.length,
          contentType: 'application/pdf',
          close: () => closed = true,
        ),
      ]);
      final progress = <int>[];
      final result = await service(t).download(
        report(),
        progress: (received, total) {
          expect(total, bytes.length);
          progress.add(received);
        },
      );
      expect(result, bytes);
      expect(progress.last, bytes.length);
      expect(closed, isTrue);
    },
  );

  test('Rejects HTTP error statuses and HTML masquerading as PDF without writing anything', () async {
    for (final status in [403, 404, 429, 500]) {
      var closed = false;
      final t = QueueReportTransport([
        ReportFetchResponse(
          status,
          Stream.value([]),
          close: () => closed = true,
        ),
      ]);
      await expectLater(
        service(t).download(report()),
        throwsA(
          failureContaining(
            status == 429
                ? '频繁'
                : status == 403
                ? '拒绝'
                : '$status',
          ),
        ),
      );
      expect(closed, isTrue);
    }
    for (final response in [
      ReportFetchResponse(
        200,
        Stream.value(utf8.encode('<html>error</html>')),
        contentType: 'application/pdf',
      ),
      ReportFetchResponse(
        200,
        Stream.value(utf8.encode('%PDF-fake')),
        contentType: 'text/html',
      ),
      ReportFetchResponse(200, Stream.value([1, 2])),
    ]) {
      await expectLater(
        service(QueueReportTransport([response])).download(report()),
        throwsA(failureContaining('不是 PDF')),
      );
    }
  });

  test('Rejects known oversize and growing chunk stream exceeding 25MB, closes/cancels', () async {
    var closed = 0, consumed = 0;
    final known = QueueReportTransport([
      ReportFetchResponse(
        200,
        Stream.value([]),
        contentLength: ReportFetchService.maxBytes + 1,
        close: () => closed++,
      ),
    ]);
    await expectLater(
      service(known).download(report()),
      throwsA(failureContaining('25 MB')),
    );
    Stream<List<int>> growing() async* {
      for (var i = 0; i < 27; i++) {
        consumed++;
        yield List.filled(1024 * 1024, 32);
      }
    }

    final streamed = QueueReportTransport([
      ReportFetchResponse(200, growing(), close: () => closed++),
    ]);
    await expectLater(
      service(streamed).download(report()),
      throwsA(failureContaining('25 MB')),
    );
    expect(consumed, 26);
    expect(closed, 2);
  });

  test('Truncated downloads and stalled stream produce retryable errors and close transport', () async {
    final truncated = QueueReportTransport([
      ReportFetchResponse(
        200,
        Stream.value(utf8.encode('%PDF-')),
        contentLength: 100,
      ),
    ]);
    await expectLater(
      service(truncated).download(report()),
      throwsA(failureContaining('传输不完整')),
    );
    var closed = false;
    final controller = StreamController<List<int>>();
    final stalled = QueueReportTransport([
      ReportFetchResponse(200, controller.stream, close: () => closed = true),
    ]);
    await expectLater(
      ReportFetchService(
        transport: stalled,
        timeout: const Duration(milliseconds: 15),
      ).download(report()),
      throwsA(failureContaining('超时')),
    );
    expect(closed, isTrue);
    await controller.close();
  });

  test('Exact official HTTPS allowlist rejects downgrade, lookalike hosts, credentials and nonstandard ports', () async {
    final t = QueueReportTransport([]);
    for (final url in [
      'http://static.cninfo.com.cn/a.pdf',
      'https://static.cninfo.com.cn.evil.test/a.pdf',
      'https://evil.test/a.pdf',
      'https://u:p@static.cninfo.com.cn/a.pdf',
      'https://static.cninfo.com.cn:444/a.pdf',
    ]) {
      await expectLater(
        service(t).download(report(url: Uri.parse(url))),
        throwsA(failureContaining('官方 HTTPS')),
      );
    }
    expect(t.uris, isEmpty);
    validateReportUri(Uri.parse('https://www.cninfo.com.cn/new/index'));
  });
}
