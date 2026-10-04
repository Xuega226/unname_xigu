import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/credentials.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/research.dart';
import 'package:lianghua_assistant/services.dart';
import 'package:lianghua_assistant/storage.dart';
import 'research_test.dart' show testSource, draftJson, FakeTransport;

void main() {
  for (final linkedBy in ['source', 'watchlist']) {
    testWidgets('company identity remains bound to $linkedBy when editing',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final old = WorkspaceData.demo().studies.first;
      final store = MemoryWorkspaceStore(WorkspaceData.empty().copyWith(
          studies: [old],
          sources: linkedBy == 'source' ? [testSource] : [],
          watchlist: linkedBy == 'watchlist'
              ? [
                  const WatchCompany(
                      id: 'SZ:000001',
                      code: '000001',
                      exchange: 'SZ',
                      name: '测试银行',
                      industry: '银行',
                      source: 'https://example.com/company',
                      fetchedAt: '2026-10-01T00:00:00Z')
                ]
              : []));
      // Use the same identity for the watchlist-linked card.
      if (linkedBy == 'watchlist') {
        store.data = store.data!.copyWith(studies: [
          Study.fromJson({...old.toJson(), 'code': '000001', 'name': '测试银行'})
        ]);
      }
      final before = store.data!.encode();
      await tester.pumpWidget(LianghuaApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('公司研究').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('编辑研究卡'));
      await tester.tap(find.byTooltip('编辑研究卡'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final field in [fields.at(0), fields.at(1)]) {
        expect(
            tester
                .widget<TextField>(find.descendant(
                    of: field, matching: find.byType(TextField)))
                .readOnly,
            isTrue);
      }
      // Even a changed controller must not bypass the identity validation.
      tester.widget<TextFormField>(fields.at(0)).controller!.text = '600000';
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('公司已有资料关联，请为其他公司新建研究卡'), findsOneWidget);
      expect(store.data!.encode(), before);
      tester.widget<TextFormField>(fields.at(0)).controller!.text =
          store.data!.studies.single.code;
      await tester.enterText(fields.at(3), '更新同一公司的研究判断');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(store.data!.studies.single.thesis, '更新同一公司的研究判断');
      expect(store.data!.sources.length, linkedBy == 'source' ? 1 : 0);
      expect(store.data!.reviews.single.text, contains(old.thesis));
      expect(tester.takeException(), isNull);
    });
  }
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
          'data': {'f57': '000001', 'f58': '测试银行', 'f127': '银行', 'f107': 0}
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
