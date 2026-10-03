// Public issuer/report smoke check only. No credentials or saved user data.
import 'dart:convert';
import 'dart:io';

import 'package:lianghua_assistant/report_fetch.dart';
import 'package:lianghua_assistant/services.dart';

class PublicReportProbeTransport implements ReportFetchTransport {
  final delegate = IoReportFetchTransport();
  @override
  Future<ReportFetchResponse> request(Uri uri, {Map<String, String>? form}) {
    if (form?['stock'] != null) {
      stdout.writeln(
        jsonEncode({'officialStock': form!['stock'], 'column': form['column']}),
      );
    }
    return delegate.request(uri, form: form);
  }
}

Future<void> main() async {
  final market = MarketService();
  final reports = ReportFetchService(transport: PublicReportProbeTransport());
  var failed = false;
  for (final issuer in [('SZ', '001246'), ('SH', '600660'), ('SZ', '000001')]) {
    try {
      final company = await market.lookup(issuer.$1, issuer.$2);
      final result = await reports.search(issuer.$1, issuer.$2);
      stdout.writeln(
        jsonEncode({
          'code': company.code,
          'exchange': company.exchange,
          'marketName': company.name,
          'officialName': result.companyName,
          'reports': result.reports
              .map((r) => {'id': r.id, 'year': r.year})
              .toList(),
          'missingYears': result.missingYears,
          'warnings': result.warnings,
        }),
      );
    } catch (e) {
      failed = true;
      stderr.writeln('${issuer.$1}:${issuer.$2} $e');
    }
  }
  if (failed) exitCode = 1;
}
