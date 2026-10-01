import 'dart:io';
import 'dart:convert';
import 'package:lianghua_assistant/services.dart';

Future<void> main() async {
  final service = MarketService();
  final records = <Map<String, dynamic>>[];
  for (final item in [('SH', '600000'), ('SZ', '000001')]) {
    final company = await service.lookup(item.$1, item.$2);
    final quoted = await service.quote(company);
    records.add(quoted.toJson());
    stdout.writeln(
        '${quoted.symbol} ${quoted.name} ${quoted.industry} close=${quoted.close} date=${quoted.tradeDate} fetched=${quoted.quoteFetchedAt}');
  }
  await File('../.tools/live-companies.json')
      .writeAsString(jsonEncode(records));
}
