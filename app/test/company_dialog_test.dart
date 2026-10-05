import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/research_widgets.dart';
import 'package:lianghua_assistant/services.dart';

class _CompanyTransport implements JsonTransport {
  @override
  Future<Map<String, dynamic>> request(Uri uri,
      {Map<String, String> headers = const {},
      Map<String, dynamic>? body}) async {
    expect(uri.queryParameters['secid'], '0.000001');
    expect(uri.queryParameters['fields']!.split(','), contains('f107'));
    return {
      'rc': 0,
      'data': {
        'f107': 0,
        'f57': '000001',
        'f58': '移动端键盘场景测试银行股份有限公司',
        'f127': '银行及其他金融服务行业'
      }
    };
  }
}

void main() {
  for (final size in [const Size(390, 844), const Size(320, 640)]) {
    testWidgets('lookup dialog remains usable with keyboard at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      WatchCompany? joined;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
              body: Center(
                  child: FilledButton(
                      onPressed: () async {
                        joined = await showDialog<WatchCompany>(
                            context: context,
                            builder: (_) => CompanyLookupDialog(
                                service: MarketService(
                                    transport: _CompanyTransport(),
                                    clock: () => DateTime.utc(2026, 10, 4))));
                      },
                      child: const Text('打开查询'))));
        }),
      ));
      await tester.tap(find.text('打开查询'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深圳 SZ').last);
      await tester.pumpAndSettle();
      final code = find.byType(TextField);
      await tester.ensureVisible(code);
      await tester.enterText(code, '000001');
      // Model the keyboard appearing only after the code field gains focus.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('核验公司'));
      await tester.tap(find.text('核验公司'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('移动端键盘场景测试银行股份有限公司'), findsOneWidget);
      expect(
          find.textContaining('https://push2.eastmoney.com/api/qt/stock/get'),
          findsOneWidget);
      expect(find.textContaining('2026-10-04T00:00:00.000Z'), findsOneWidget);
      await tester.ensureVisible(find.text('加入自选'));
      await tester.tap(find.text('加入自选'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(joined!.symbol, 'SZ:000001');
      expect(joined!.name, '移动端键盘场景测试银行股份有限公司');
    });
  }
}
