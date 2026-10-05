import 'dart:convert';
import 'dart:io';

import 'package:lianghua_assistant/data_foundation.dart';

// Read-only source verification: no workspace file or account credentials.
Future<void> main(List<String> arguments) async {
  final results = <Map<String, dynamic>>[];
  final service = MarketHistoryService();
  for (final symbol in ['SH:600519', 'SZ:000001']) {
    try {
      final history = await service.history(symbol);
      results.add({
        'symbol': history.symbol,
        'source': history.source,
        'fetchedAt': history.fetchedAt,
        'count': history.bars.length,
        'first': history.bars.first.toJson(),
        'last': history.bars.last.toJson(),
        'adjustment': history.adjustment,
      });
    } catch (error) {
      results.add({'symbol': symbol, 'error': error.toString()});
      exitCode = 1;
    }
  }
  final output = const JsonEncoder.withIndent('  ').convert(results);
  stdout.writeln(output);
  if (arguments.length == 1) {
    await File(arguments.single).writeAsString(output);
  } else if (arguments.length > 1) {
    throw ArgumentError('只接受一个可选验证日志路径');
  }
}
