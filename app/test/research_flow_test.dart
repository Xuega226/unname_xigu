import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';
import 'research_test.dart' show testSource, draftJson, FakeTransport;

void main() {
  for (final valid in [true, false]) {
    testWidgets(
        'AI draft valid=$valid requires review and preserves previous version',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final old = WorkspaceData.demo().studies.first;
      final store = MemoryWorkspaceStore(WorkspaceData.empty()
          .copyWith(studies: [old], sources: [testSource]));
      final credentials =
          MemoryCredentialStore(const AiSettings(key: 'unit-test-sentinel'));
      final ai = DeepSeekService(
          transport: FakeTransport((u, b) => {
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {
                      'content': jsonEncode(
                          draftJson(sourceId: valid ? 'source-1' : 'invented'))
                    }
                  }
                ]
              }));
      await tester.pumpWidget(
          LianghuaApp(store: store, ai: ai, credentials: credentials));
      await tester.pumpAndSettle();
      await tester.tap(find.text('公司研究').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('生成 AI 草稿'));
      await tester.tap(find.text('生成 AI 草稿'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发送资料并生成'));
      await tester.pumpAndSettle();
      expect(store.data!.studies.single.thesis, old.thesis);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, '接受为研究卡版本'))
              .onPressed,
          isNull);
      final check = find.byType(CheckboxListTile);
      await tester.ensureVisible(check);
      if (valid) {
        await tester.tap(check);
        await tester.pumpAndSettle();
        await tester.tap(find.text('接受为研究卡版本'));
        await tester.pumpAndSettle();
        expect(store.data!.studies.single.business, contains('source-1'));
        expect(store.data!.reviews.single.text, contains(old.thesis));
        expect(store.data!.reviews.single.text, contains('营收100万元'));
      } else {
        expect(tester.widget<CheckboxListTile>(check).onChanged, isNull);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(store.data!.reviews, isEmpty);
      }
      expect(store.data!.encode(), isNot(contains('unit-test-sentinel')));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'real company lookup keeps leading zeroes and cannot mix into demo',
      (tester) async {
    final transport = FakeTransport((u, b) => {
          'rc': 0,
          'data': {'f57': '000001', 'f58': '测试银行', 'f127': '银行'}
        });
    final store = MemoryWorkspaceStore(WorkspaceData.empty());
    await tester.pumpWidget(
        LianghuaApp(store: store, market: MarketService(transport: transport)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公司研究').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加真实公司'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深圳 SZ').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000001');
    await tester.tap(find.text('核验公司'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入自选'));
    await tester.pumpAndSettle();
    expect(store.data!.watchlist.single.symbol, 'SZ:000001');
    expect(store.data!.studies.single.code, '000001');
    expect(
        () => WorkspaceData.decode(store.data!.copyWith(isDemo: true).encode()),
        throwsFormatException);
  });
}
