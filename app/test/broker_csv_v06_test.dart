import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/broker_import.dart';

CsvAccountDetails account({
  Map<String, int>? mapping,
  String? delimiter,
  PortfolioTextEncoding? encoding,
}) => CsvAccountDetails(
  broker: '虚构券商',
  accountAlias: '本机测试',
  priceDate: '2026-10-01',
  cash: 100,
  columnMapping: mapping,
  delimiter: delimiter,
  encoding: encoding,
);

void main() {
  const csv = '证券代码,证券名称,持仓数量,市价\r\n000001,"虚构,证券",100,12\r\n';
  test(
    'strict GBK requires explicit confirmation and preserves Chinese and code',
    () {
      final bytes = const GbkCodec().encode(csv);
      expect(
        () => decodePortfolioText(bytes),
        throwsA(isA<BrokerEncodingRequired>()),
      );
      expect(
        decodePortfolioText(bytes, encoding: PortfolioTextEncoding.gbk),
        csv,
      );
      final result = parseBrokerFile(
        bytes,
        csv: account(encoding: PortfolioTextEncoding.gbk),
      );
      expect(result.holdings.single.code, '000001');
      expect(result.holdings.single.name, '虚构,证券');
      expect(result.assets, 1300);
    },
  );
  test('declared UTF8 BOM errors never fall back to valid GBK', () {
    final bytes = [0xef, 0xbb, 0xbf, ...const GbkCodec().encode(csv)];
    expect(() => decodePortfolioText(bytes), throwsFormatException);
    expect(
      () => decodePortfolioText(bytes, encoding: PortfolioTextEncoding.gbk),
      throwsFormatException,
    );
    expect(
      () => decodePortfolioText(
        const GbkCodec().encode(csv),
        encoding: PortfolioTextEncoding.utf8,
      ),
      throwsFormatException,
    );
  });
  test(
    'GBK rejects invalid pairs unmapped codes truncated bytes and GB18030',
    () {
      for (final bytes in [
        [0x81],
        [0x81, 0x7f],
        [0x80],
        [0x81, 0x30, 0x81, 0x30],
        [256],
        [-1],
      ]) {
        expect(
          () => decodePortfolioText(bytes, encoding: PortfolioTextEncoding.gbk),
          throwsFormatException,
          reason: '$bytes',
        );
      }
    },
  );
  test('UTF16 both endian forms decode pairs but reject lone surrogates', () {
    final text = '$csv😀';
    for (final little in [true, false]) {
      final bytes = [
        if (little) ...[255, 254] else ...[254, 255],
        for (final c in text.codeUnits) ...[
          if (little) c & 255 else c >> 8,
          if (little) c >> 8 else c & 255,
        ],
      ];
      expect(decodePortfolioText(bytes), text);
    }
    for (final bytes in [
      [255, 254, 0],
      [255, 254, 0, 0xd8],
      [255, 254, 0, 0xdc],
      [254, 255, 0xd8, 0, 0, 65],
    ]) {
      expect(() => decodePortfolioText(bytes), throwsFormatException);
    }
  });
  for (final delimiter in [',', '\t', ';']) {
    test(
      'detects delimiter $delimiter with quoted cells and Excel text marker',
      () {
        final headers = ['证券代码', '证券名称', '持仓数量', '市价'].join(delimiter);
        final row = ["'000001", '"虚构;证券,公司"', '100', '12'].join(delimiter);
        final text = '$headers\r\n$row';
        final bytes = utf8.encode(text);
        final table = inspectBrokerCsv(bytes);
        expect(table.delimiter, delimiter);
        expect(table.needsMapping, false);
        final holding = parseBrokerFile(bytes, csv: account()).holdings.single;
        expect(holding.code, '000001');
        expect(holding.name, '虚构;证券,公司');
      },
    );
  }
  test('delimiter ties and irregular rows are rejected without guessing', () {
    expect(
      () => inspectBrokerCsv(utf8.encode('代码,名称;数量\n000001,a;100')),
      throwsFormatException,
    );
    expect(
      () => inspectBrokerCsv(utf8.encode('${csv}000002,a,3')),
      throwsFormatException,
    );
    expect(() => parseCsv('a,b', delimiter: '|'), throwsFormatException);
    expect(parseCsv('"a\n";"b""c"', delimiter: ';'), [
      ['a\n', 'b"c'],
    ]);
  });
  test(
    'unknown and ambiguous headers need complete explicit distinct mapping',
    () {
      final bytes = utf8.encode('ID;Label;Total;Now\n000001;虚构;100;12');
      expect(inspectBrokerCsv(bytes).needsMapping, true);
      expect(
        () => parseBrokerFile(bytes, csv: account()),
        throwsFormatException,
      );
      final mapping = {'code': 0, 'name': 1, 'quantity': 2, 'price': 3};
      expect(
        parseBrokerFile(bytes, csv: account(mapping: mapping)).assets,
        1300,
      );
      for (final bad in [
        {'code': 0, 'name': 1, 'quantity': 2},
        {'code': 0, 'name': 1, 'quantity': 2, 'price': 2},
        {'code': 0, 'name': 1, 'quantity': 2, 'price': 99},
        {...mapping, 'other': 3},
      ]) {
        expect(
          () => parseBrokerFile(bytes, csv: account(mapping: bad)),
          throwsFormatException,
        );
      }
      final ambiguous = utf8.encode('代码,名称,持仓数量,证券数量,市价\n000001,虚构,100,100,12');
      expect(inspectBrokerCsv(ambiguous).needsMapping, true);
      expect(
        () => parseBrokerFile(ambiguous, csv: account()),
        throwsFormatException,
      );
      expect(
        parseBrokerFile(
          ambiguous,
          csv: account(
            mapping: {'code': 0, 'name': 1, 'quantity': 2, 'price': 4},
          ),
        ).assets,
        1300,
      );
    },
  );
  test('manual mapping cannot substitute known available quantity or cost', () {
    for (final quantity in [
      '可用数量',
      '可卖数量',
      'available shares',
      'sellable quantity',
    ]) {
      final bytes = utf8.encode('ID,Label,$quantity,Now\n000001,虚构,100,12');
      expect(
        () => parseBrokerFile(
          bytes,
          csv: account(
            mapping: {'code': 0, 'name': 1, 'quantity': 2, 'price': 3},
          ),
        ),
        throwsFormatException,
      );
    }
    for (final price in ['成本价', '买入价', 'cost price', 'average price']) {
      final bytes = utf8.encode('ID,Label,Total,$price\n000001,虚构,100,12');
      expect(
        () => parseBrokerFile(
          bytes,
          csv: account(
            mapping: {'code': 0, 'name': 1, 'quantity': 2, 'price': 3},
          ),
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'duplicate securities missing values and spreadsheet formulas are rejected',
    () {
      for (final text in [
        '$csv'
            '000001,虚构,100,12',
        '证券代码,证券名称,持仓数量,市价\n000001,虚构,,12',
        '证券代码,证券名称,持仓数量,市价\n="000001",虚构,100,12',
      ]) {
        expect(
          () => parseBrokerFile(utf8.encode(text), csv: account()),
          throwsFormatException,
        );
      }
    },
  );
}
