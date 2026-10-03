import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'services.dart';

/// Public disclosure website requests, separate from authenticated AI traffic.
abstract class ReportFetchTransport {
  Future<ReportFetchResponse> request(Uri uri, {Map<String, String>? form});
}

class ReportFetchResponse {
  const ReportFetchResponse(
    this.statusCode,
    this.body, {
    this.contentLength,
    this.contentType,
    this.close,
  });
  final int statusCode;
  final Stream<List<int>> body;
  final int? contentLength;
  final String? contentType;
  final void Function()? close;
}

/// Only these exact official hosts are used, including after redirects.
void validateReportUri(Uri uri) {
  if (uri.scheme != 'https' ||
      !{'www.cninfo.com.cn', 'static.cninfo.com.cn'}.contains(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    throw ServiceFailure('财报链接不是受支持的官方 HTTPS 地址');
  }
}

class IoReportFetchTransport implements ReportFetchTransport {
  IoReportFetchTransport({this.timeout = const Duration(seconds: 45)});
  final Duration timeout;
  @override
  Future<ReportFetchResponse> request(
    Uri uri, {
    Map<String, String>? form,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final deadline = Timer(timeout, () => client.close(force: true));
    try {
      // Match the application's existing Windows proxy handling. Read only the
      // non-secret OS proxy settings; no authentication or cookies are sent.
      if (Platform.isWindows) {
        const key =
            r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        try {
          final enabled = await Process.run('reg', [
            'query',
            key,
            '/v',
            'ProxyEnable',
          ]).timeout(const Duration(seconds: 3));
          if (RegExp(r'REG_DWORD\s+0x1\b').hasMatch('${enabled.stdout}')) {
            final server = await Process.run('reg', [
              'query',
              key,
              '/v',
              'ProxyServer',
            ]).timeout(const Duration(seconds: 3));
            final match = RegExp(r'REG_SZ\s+([A-Za-z0-9.-]+:\d+)\s*$')
                .firstMatch('${server.stdout}'.trim());
            if (match != null) {
              client.findProxy = (_) => 'PROXY ${match.group(1)}';
            }
          }
        } catch (_) {
          // Registry access is optional; direct HTTPS remains available.
        }
      }
      var current = uri;
      for (var redirects = 0; redirects <= 3; redirects++) {
        validateReportUri(current);
        final req = await client
            .openUrl(form == null ? 'GET' : 'POST', current)
            .timeout(timeout);
        req.followRedirects = false;
        req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        req.headers.set(
          HttpHeaders.userAgentHeader,
          'WeimingXigu/0.4 public-report-reader',
        );
        req.headers.set(
          HttpHeaders.acceptHeader,
          form == null ? 'application/pdf' : 'application/json',
        );
        req.headers.set(
          HttpHeaders.refererHeader,
          'https://www.cninfo.com.cn/',
        );
        if (form != null) {
          req.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
            charset: 'utf-8',
          );
          req.add(utf8.encode(Uri(queryParameters: form).query));
        }
        final response = await req.close().timeout(timeout);
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (form != null || location == null || redirects == 3) {
            throw ServiceFailure('官方服务重定向异常，请稍后重试');
          }
          final next = current.resolve(location);
          validateReportUri(next); // Validate before any follow-up request.
          await response.drain<void>().timeout(timeout);
          current = next;
          continue;
        }
        Stream<List<int>> stream() async* {
          try {
            yield* response;
          } finally {
            deadline.cancel();
            client.close(force: true);
          }
        }

        return ReportFetchResponse(
          response.statusCode,
          stream(),
          contentLength: response.contentLength < 0
              ? null
              : response.contentLength,
          contentType: response.headers.contentType?.mimeType,
          close: () {
            deadline.cancel();
            client.close(force: true);
          },
        );
      }
      throw ServiceFailure('官方服务重定向次数过多');
    } catch (_) {
      deadline.cancel();
      client.close(force: true);
      rethrow;
    }
  }
}

class ReportAnnouncement {
  const ReportAnnouncement({
    required this.id,
    required this.code,
    required this.exchange,
    required this.companyName,
    required this.title,
    required this.url,
    required this.start,
    required this.end,
    required this.disclosedAt,
    required this.isRevision,
    required this.year,
  });
  final String id, code, exchange, companyName, title;
  final Uri url;
  final DateTime start, end, disclosedAt;
  final bool isRevision;
  final int year;
  String get fileName => '${code}_${year}_$id.pdf';
  String get sourceUrl =>
      Uri.https('www.cninfo.com.cn', '/new/disclosure/detail', {
        'stockCode': code,
        'announcementId': id,
        'announcementTime': _date(disclosedAt),
      }).toString();
}

class ReportSearchResult {
  const ReportSearchResult({
    required this.companyName,
    required this.code,
    required this.exchange,
    required this.reports,
    required this.missingYears,
    required this.warnings,
  });
  final String companyName, code, exchange;
  final List<ReportAnnouncement> reports;
  final List<int> missingYears;
  final List<String> warnings;
}

String _date(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class ReportFetchService {
  ReportFetchService({
    ReportFetchTransport? transport,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 45),
    this.maxPages = 10,
  }) : transport = transport ?? IoReportFetchTransport(timeout: timeout),
       clock = clock ?? DateTime.now;
  final ReportFetchTransport transport;
  final DateTime Function() clock;
  final Duration timeout;
  final int maxPages;
  static const maxBytes = 25 * 1024 * 1024;

  Future<Uint8List> _request(
    Uri uri, {
    Map<String, String>? form,
    required int limit,
    void Function(int, int?)? progress,
  }) async {
    validateReportUri(uri);
    ReportFetchResponse? activeResponse;
    try {
      return await (() async {
        final response = await transport.request(uri, form: form);
        activeResponse = response;
        if (response.statusCode != 200 ||
            (response.contentLength != null &&
                response.contentLength! > limit)) {
          // Consume through cancellation so the HTTP client is always closed.
          await response.body.listen((_) {}).cancel();
          if (response.contentLength != null &&
              response.contentLength! > limit) {
            throw ServiceFailure(
              form == null ? '单份 PDF 最多 25 MB' : '官方响应过大，请缩小查询范围',
            );
          }
          throw ServiceFailure(switch (response.statusCode) {
            429 => '巨潮请求过于频繁，请稍后重试',
            401 || 403 => '巨潮暂时拒绝访问，请稍后重试或手动导入',
            _ => '巨潮返回 HTTP ${response.statusCode}，请稍后重试',
          });
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.body.timeout(timeout)) {
          if (bytes.length + chunk.length > limit) {
            throw ServiceFailure(
              form == null ? '单份 PDF 最多 25 MB' : '官方响应过大，请缩小查询范围',
            );
          }
          bytes.add(chunk);
          progress?.call(bytes.length, response.contentLength);
        }
        if (response.contentLength != null &&
            bytes.length != response.contentLength) {
          throw ServiceFailure('官方文件传输不完整，请重试');
        }
        final data = bytes.takeBytes();
        if (form == null &&
            (response.contentType == 'text/html' ||
                data.length < 5 ||
                ascii.decode(data.sublist(0, 5), allowInvalid: true) !=
                    '%PDF-')) {
          throw ServiceFailure('下载结果不是 PDF，可能为错误页面；请重试或手动导入');
        }
        return data;
      })().timeout(timeout);
    } on ServiceFailure {
      rethrow;
    } on TimeoutException {
      throw ServiceFailure('巨潮请求超时，请重试或手动导入');
    } catch (_) {
      throw ServiceFailure('巨潮网络连接或响应解析失败，请重试或手动导入');
    } finally {
      activeResponse?.close?.call();
    }
  }

  Future<dynamic> _json(Uri uri, Map<String, String> form) async => jsonDecode(
    utf8.decode(await _request(uri, form: form, limit: 2 * 1024 * 1024)),
  );

  Future<ReportSearchResult> search(
    String exchange,
    String code, {
    int years = 3,
  }) async {
    if (exchange == 'BJ') throw ServiceFailure('本轮自动获取支持沪深 A 股；北交所财报请先手动导入');
    final prefixes = {'SH': RegExp(r'^6\d{5}$'), 'SZ': RegExp(r'^[03]\d{5}$')};
    if (!prefixes.containsKey(exchange) ||
        !prefixes[exchange]!.hasMatch(code)) {
      throw ServiceFailure('请输入六位沪深 A 股代码，并核对所选交易所');
    }
    if (years < 1 || years > 3 || maxPages < 1) {
      throw ServiceFailure('单次查询支持最近 1 至 3 年年报');
    }
    try {
      final found = await _json(
        Uri.https('www.cninfo.com.cn', '/new/information/topSearch/query'),
        {'keyWord': code, 'maxNum': '10'},
      );
      if (found is! List) throw ServiceFailure('巨潮公司查询响应格式异常');
      final matches = found
          .whereType<Map>()
          .where((row) => row['code'] == code && row['category'] == 'A股')
          .toList();
      if (matches.length != 1) throw ServiceFailure('未查到唯一匹配的 A 股公司，请核对代码');
      final company = matches.single;
      final orgId = company['orgId'], name = company['zwjc'];
      // Organization IDs are opaque across markets and listing changes:
      // 301190 uses gfbj0871838, while 001246 uses 9900057193. Validate their
      // known syntax only; the requested code prefix and unique official
      // A-share match determine the exchange. Every announcement below must
      // still match this exact code AND orgId.
      final validOrgId =
          orgId is String &&
          RegExp(r'^(?:(?:gssh|gssz|gfbj)[0-9]{6,16}|[1-9][0-9]{9})$')
              .hasMatch(orgId);
      if (!validOrgId || name is! String || name.trim().isEmpty) {
        throw ServiceFailure('巨潮返回的公司标识与所选证券不匹配，请手动核对');
      }
      final now = clock();
      final expected = List.generate(years, (i) => now.year - 1 - i);
      final reports = <ReportAnnouncement>[];
      final ids = <String>{}, warnings = <String>{};
      var page = 1, received = 0;
      while (true) {
        final json = await _json(
          Uri.https('www.cninfo.com.cn', '/new/hisAnnouncement/query'),
          {
            'pageNum': '$page',
            'pageSize': '30',
            'column': exchange == 'SH' ? 'sse' : 'szse',
            'tabName': 'fulltext',
            'stock': '$code,$orgId',
            'category': 'category_ndbg_szsh;',
            'seDate': '${expected.last + 1}-01-01~${_date(now)}',
            'searchkey': '',
            'isHLtitle': 'true',
            'sortName': 'time',
            'sortType': 'desc',
          },
        );
        if (json is! Map ||
            (json['announcements'] != null && json['announcements'] is! List) ||
            json['totalAnnouncement'] is! int ||
            (json['totalAnnouncement'] as int) < 0 ||
            json['hasMore'] is! bool) {
          throw ServiceFailure('巨潮公告查询响应格式异常，请重试');
        }
        final rows = (json['announcements'] as List?) ?? [];
        received += rows.length;
        for (final row in rows) {
          if (row is! Map) {
            warnings.add('部分公告信息不完整，已略过，请核对官方页面');
            continue;
          }
          if (row['secCode'] != code || row['orgId'] != orgId) {
            warnings.add('已排除证券代码或公司归属不匹配的公告');
            continue;
          }
          final title =
              (row['announcementTitle'] is String
                      ? row['announcementTitle'] as String
                      : '')
                  .replaceAll(RegExp(r'<[^>]*>'), '')
                  .replaceAll('&nbsp;', '')
                  .trim();
          // Notice words are evaluated independently of company-name keywords;
          // e.g. a company named "天源环境" still has a valid annual report.
          final normalizedTitle = title.replaceAll(RegExp(r'\s+'), '');
          final annualStart = RegExp(r'20\d{2}年?年度报告')
              .firstMatch(normalizedTitle);
          final reportSuffix = annualStart == null
              ? normalizedTitle
              : normalizedTitle.substring(annualStart.start);
          if (RegExp(r'关于|取消|撤销|作废').hasMatch(normalizedTitle) ||
              RegExp(
                r'摘要|英文|英语|English|审计|说明|公告|提示|意见|议案|董事会|监事会|社会责任|环境|ESG|承诺|确认|决议|核查|问询|回复',
                caseSensitive: false,
              ).hasMatch(reportSuffix)) {
            continue;
          }
          final yearMatch = RegExp(
            r'(20\d{2})年?年度报告(?:全文)?(?:[（(](?:修订版|修订稿|更新版|更正版|更正后|修订后|更新后|修订|更正|更新)[）)])?$',
          ).firstMatch(normalizedTitle);
          if (yearMatch == null) {
            if (annualStart != null &&
                RegExp(r'修订|更新|更正').hasMatch(reportSuffix)) {
              warnings.add('部分修订年报标题格式暂不支持，请核对官方页面是否有其他版本');
            }
            continue;
          }
          final year = int.parse(yearMatch.group(1)!);
          if (!expected.contains(year)) continue;
          final id = row['announcementId'],
              relative = row['adjunctUrl'],
              timestamp = row['announcementTime'];
          if (id is! String ||
              !RegExp(r'^\d+$').hasMatch(id) ||
              relative is! String ||
              !RegExp(
                r'^finalpage/\d{4}-\d{2}-\d{2}/\d+\.pdf$',
                caseSensitive: false,
              ).hasMatch(relative) ||
              relative.split('/').last.split('.').first != id ||
              timestamp is! int ||
              timestamp <= 0 ||
              timestamp > 4102444800000 ||
              row['adjunctType'].toString().toUpperCase() != 'PDF') {
            warnings.add('部分年报缺少有效附件或日期，已略过，请核对官方页面');
            continue;
          }
          final china = DateTime.fromMillisecondsSinceEpoch(
            timestamp.toInt(),
            isUtc: true,
          ).add(const Duration(hours: 8));
          final disclosed = DateTime(china.year, china.month, china.day);
          final pathDate = relative.split('/')[1];
          if (_date(disclosed) != pathDate ||
              disclosed.isAfter(DateTime(now.year, now.month, now.day)) ||
              disclosed.year <= year) {
            warnings.add('部分年报披露日期异常，已略过，请核对官方页面');
            continue;
          }
          if (!ids.add(id)) continue;
          reports.add(
            ReportAnnouncement(
              id: id,
              code: code,
              exchange: exchange,
              companyName: name,
              title: title,
              url: Uri.https('static.cninfo.com.cn', '/$relative'),
              start: DateTime(year, 1, 1),
              end: DateTime(year, 12, 31),
              disclosedAt: disclosed,
              isRevision: RegExp(r'修订|更新|更正').hasMatch(title),
              year: year,
            ),
          );
        }
        final total = json['totalAnnouncement'] as int;
        final more = json['hasMore'] == true || received < total;
        if (!more) break;
        if (page >= maxPages || rows.isEmpty) {
          warnings.add('官方结果分页未全部读取，请缩小范围后重试或核对官方页面');
          break;
        }
        page++;
      }
      reports.sort((a, b) {
        final byYear = b.year.compareTo(a.year);
        return byYear != 0 ? byYear : b.disclosedAt.compareTo(a.disclosedAt);
      });
      final missing = expected
          .where((year) => !reports.any((r) => r.year == year))
          .toList();
      if (missing.isNotEmpty) {
        warnings.add(
          '本次查询未找到 ${missing.join('、')} 年完整年报；不代表公司未披露。请核对官方公告，新上市公司可手动补充招股说明书和上市公告书。',
        );
      }
      if (reports.any((r) => r.isRevision) ||
          expected.any(
            (year) => reports.where((r) => r.year == year).length > 1,
          )) {
        warnings.add('存在修订版或同年度多份年报，请核对版本后选择；列表顺序不代表推荐版本');
      }
      return ReportSearchResult(
        companyName: name,
        code: code,
        exchange: exchange,
        reports: List.unmodifiable(reports),
        missingYears: List.unmodifiable(missing),
        warnings: List.unmodifiable(warnings),
      );
    } on ServiceFailure {
      rethrow;
    } catch (_) {
      throw ServiceFailure('巨潮返回的财报信息无法读取，请重试或手动导入');
    }
  }

  Future<Uint8List> download(
    ReportAnnouncement announcement, {
    void Function(int, int?)? progress,
  }) => _request(announcement.url, limit: maxBytes, progress: progress);
}
