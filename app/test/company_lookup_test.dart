import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/research_widgets.dart';
import 'package:lianghua_assistant/services.dart';

import 'research_test.dart' show FakeTransport;
import 'third_round_flow_test.dart' show dialogHost, tapVisible, enterVisible;

void main() {
  test('exchange inference preserves leading zeroes and rejects incomplete or unsupported codes', () {
    expect(aShareExchangeForCode('001246'), 'SZ');
    expect(aShareExchangeForCode('300001'), 'SZ');
    expect(aShareExchangeForCode('600660'), 'SH');
    expect(aShareExchangeForCode('920001'), 'BJ');
    expect(aShareExchangeForCode('00124'), isNull);
    expect(aShareExchangeForCode('1246'), isNull);
    expect(aShareExchangeForCode('200001'), isNull);
  });
  for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
    testWidgets(
      '001246 automatically selects Shenzhen and verifies N力勤 at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final transport = FakeTransport(
          (u, b) => {
            'rc': 0,
            'data': {'f57': '001246', 'f58': 'N力勤', 'f127': '能源金属'},
          },
        );
        await dialogHost(
          tester,
          CompanyLookupDialog(service: MarketService(transport: transport)),
        );
        await enterVisible(tester, find.byType(TextField), '001246');
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .initialValue,
          'SZ',
        );
        await tapVisible(tester, find.text('核验公司'));
        expect(transport.uri!.queryParameters['secid'], '0.001246');
        expect(find.textContaining('N力勤 · SZ:001246'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '加入自选'))
              .onPressed,
          isNotNull,
        );
        await enterVisible(tester, find.byType(TextField), '600660');
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .initialValue,
          'SH',
        );
        expect(find.textContaining('N力勤 · SZ:001246'), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '加入自选'))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'manual wrong exchange explains the mismatch and changing it clears the error',
    (tester) async {
      final transport = FakeTransport(
        (u, b) => throw StateError('No network expected'),
      );
      await dialogHost(
        tester,
        CompanyLookupDialog(service: MarketService(transport: transport)),
      );
      await enterVisible(tester, find.byType(TextField), '001246');
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tapVisible(tester, find.text('上海 SH').last);
      await tapVisible(tester, find.text('核验公司'));
      expect(find.text('001246 对应深圳 SZ，当前选择上海 SH，请切换交易所'), findsOneWidget);
      expect(transport.uri, isNull);
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tapVisible(tester, find.text('深圳 SZ').last);
      expect(find.textContaining('请切换交易所'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
