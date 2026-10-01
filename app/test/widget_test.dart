import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/main.dart';
import 'package:lianghua_assistant/storage.dart';

void main() {
  testWidgets('editing a study retains its previous investment hypothesis',
      (tester) async {
    final initial = WorkspaceData.demo();
    final store = MemoryWorkspaceStore(initial);
    await tester.pumpWidget(LianghuaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公司研究').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑研究卡').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).at(3), '新的验证指标：下一份报告中的经营现金流。');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.data!.studies.first.thesis, '新的验证指标：下一份报告中的经营现金流。');
    expect(store.data!.reviews.single.text,
        contains(initial.studies.first.thesis));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
  testWidgets('invalid holding input cannot enter persisted portfolio',
      (tester) async {
    final store = MemoryWorkspaceStore(WorkspaceData.demo());
    await tester.pumpWidget(LianghuaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('账户风控').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增持仓'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '000001');
    await tester.enterText(find.byType(TextFormField).at(1), '测试录入');
    await tester.enterText(find.byType(TextFormField).at(2), '测试行业');
    await tester.enterText(find.byType(TextFormField).at(3), '-10');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入非负的有限数值'), findsOneWidget);
    expect(store.data!.holdings.length, 3);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  });
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('research and risk layouts fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          LianghuaApp(store: MemoryWorkspaceStore(WorkspaceData.demo())));
      await tester.pumpAndSettle();
      expect(find.text('先看风险，再做判断'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('公司研究').last);
      await tester.pumpAndSettle();
      expect(find.text('新增研究卡'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('账户风控').last);
      await tester.pumpAndSettle();
      expect(find.text('新增持仓'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('review entry can be saved and survives reopening',
      (tester) async {
    final store = MemoryWorkspaceStore(WorkspaceData.demo());
    await tester.pumpWidget(LianghuaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复查日志').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录一次复查'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '补充现金流资料，下月复查。');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.data!.reviews.single.text, '补充现金流资料，下月复查。');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.pumpWidget(LianghuaApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复查日志').last);
    await tester.pumpAndSettle();
    expect(find.text('补充现金流资料，下月复查。'), findsOneWidget);
  });
}
