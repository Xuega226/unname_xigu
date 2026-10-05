import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Follow the public menu and disclosure steps before a legacy workflow action.
// Financial assertions in those workflows remain unchanged.
Future<void> revealSimplifiedAction(WidgetTester tester, Finder target) async {
  bool found() {
    try {
      return target.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  if (found()) return;
  final description = target.describeMatch(Plurality.one);
  Future<void> open(Finder control) async {
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  if (['自动查找年报', '导入财报 PDF', '添加原文片段'].any(description.contains)) {
    await open(find.byTooltip('添加资料'));
  } else if (['AI 提取财务候选值', '核对财务字段'].any(description.contains)) {
    await open(find.widgetWithText(ChoiceChip, '财务核验'));
  } else if ([
    '生成 AI 草稿',
    '多年度财务变化',
    '复查计划与清单',
    '研究版本对照',
  ].any(description.contains)) {
    await open(find.byTooltip('更多研究操作').first);
  } else if ([
    '查看原页与选页原文',
    '重新关联原 PDF',
    '定位 PDF 原页',
  ].any(description.contains)) {
    final sourceTab = find.widgetWithText(ChoiceChip, '资料原文');
    if (sourceTab.evaluate().isNotEmpty &&
        !tester.widget<ChoiceChip>(sourceTab).selected) {
      await open(sourceTab);
    }
    final titles = tester
        .widgetList<ExpansionTile>(find.byType(ExpansionTile))
        .map((tile) => tile.title)
        .whereType<Text>()
        .map((title) => title.data)
        .whereType<String>()
        .where((title) => title.toLowerCase().endsWith('.pdf'))
        .toList();
    for (final title in titles) {
      if (found()) break;
      await open(find.text(title).first);
    }
  } else if (description.contains('quant-add-capital') ||
      description.contains('quant-delete-capital')) {
    await open(find.byKey(const ValueKey('quant-capital-section')));
  } else if ([
    'quant-config-window',
    'quant-config-age',
    'quant-config-scope',
    'quant-config-excluded',
    'quant-config-review-days',
    'quant-config-review-condition',
  ].any(description.contains)) {
    await open(find.byKey(const ValueKey('quant-config-advanced')));
  }
}
