import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/portfolio_import_info.dart';

Map<String, dynamic> _info() => {
  'broker': '虚构券商',
  'accountAlias': '测试主账户',
  'capturedAt': '2026-10-01T09:00:00+08:00',
  'importedAt': '2026-10-01T01:00:00.123456Z',
  'digest': List.filled(64, 'a').join(),
  'format': 'json',
  'modified': false,
};

void main() {
  test('backup round trip preserves explicit offsets and UTC fractions', () {
    final info = PortfolioImportInfo.fromJson(_info());
    final data = WorkspaceData.empty().copyWith(portfolioImport: info);
    final restored = WorkspaceData.decode(data.encode());
    expect(restored.portfolioImport!.toJson(), info.toJson());
    expect(brokerTimeLabel(info.importedAt), '2026-10-01 09:00:00（北京时间）');
    expect(
      brokerTimestamp('2024-02-29T23:59:59.999999-05:30', '测试'),
      '2024-02-29T23:59:59.999999-05:30',
    );
  });

  test('workspace backup refuses normalized or timezone-free broker times', () {
    for (final field in ['capturedAt', 'importedAt']) {
      for (final invalid in <dynamic>[
        '2026-10-01T25:00:00+08:00',
        '2026-10-01T12:99:00+08:00',
        '2026-10-01T12:00:60+08:00',
        '2026-10-01T12:00:00+24:00',
        '2026-10-01T12:00:00-08:99',
        '2026-10-01T12:00:00',
        '2026-02-29T12:00:00Z',
        '2026-02-31T12:00:00Z',
        '2026-10-01T12:00:00Z\n',
        null,
        123,
      ]) {
        final j = WorkspaceData.empty().toJson()
          ..['portfolioImport'] = (_info()..[field] = invalid);
        expect(
          () => WorkspaceData.decode(jsonEncode(j)),
          throwsFormatException,
          reason: '$field must reject $invalid',
        );
      }
    }
  });

  test('workspace backup refuses invalid source identity and audit fields', () {
    final invalidFields = <String, List<dynamic>>{
      'broker': ['', '   ', '\n券商', '券商\u007f', '券商\u0085', null, 123],
      'accountAlias': ['', ' ', '账户\u0000混入身份', List.filled(121, 'a').join()],
      'digest': [
        '',
        List.filled(63, 'a').join(),
        List.filled(64, 'A').join(),
        List.filled(64, 'g').join(),
        null,
        123,
      ],
      'format': ['JSON', 'xml', '', null, 1],
      'modified': [null, 0, 'false'],
    };
    for (final entry in invalidFields.entries) {
      for (final invalid in entry.value) {
        final j = WorkspaceData.empty().toJson()
          ..['portfolioImport'] = (_info()..[entry.key] = invalid);
        expect(
          () => WorkspaceData.decode(jsonEncode(j)),
          throwsFormatException,
          reason: '${entry.key} must reject $invalid',
        );
      }
    }
  });
}
