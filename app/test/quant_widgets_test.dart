import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianghua_assistant/domain.dart';
import 'package:lianghua_assistant/quant_engine.dart';
import 'package:lianghua_assistant/quant_models.dart';
import 'package:lianghua_assistant/quant_widgets.dart';
import 'package:lianghua_assistant/research.dart';

QuantConfig quantUiConfig() => const QuantConfig(
  id: 'fixture-v1',
  revision: 1,
  name: '虚构样本手算规则',
  asOfDate: '2026-06-01',
  confirmed: true,
  confirmedAt: '2026-06-01T00:00:00Z',
  rules: [
    QuantRule(
      id: 'margin',
      factor: QuantFactor.adjustedProfitMargin,
      comparison: QuantComparison.gte,
      threshold: 10,
      weight: 3,
      filter: true,
    ),
    QuantRule(
      id: 'cash',
      factor: QuantFactor.cashProfitRatio,
      comparison: QuantComparison.gte,
      threshold: 1,
      weight: 1,
      filter: false,
    ),
  ],
);

WorkspaceData quantUiFixture({
  bool configured = true,
  bool negativeCash = false,
}) {
  final names = ['虚构制造甲', '虚构消费乙', '虚构缺值丙', '虚构银行丁'];
  final codes = ['600001', '600002', '600003', '600004'];
  return WorkspaceData.empty().copyWith(
    deposits: 4000,
    withdrawals: 1000,
    cash: 2000,
    watchlist: [
      for (var i = 0; i < names.length; i++)
        WatchCompany(
          id: 'w$i',
          code: codes[i],
          exchange: 'SH',
          name: names[i],
          industry: i == 3 ? '银行' : '制造',
          source: 'https://example.com/fictional-company-$i',
          fetchedAt: '2026-06-01T00:00:00Z',
        ),
    ],
    studies: [
      for (var i = 0; i < names.length; i++)
        Study(
          id: 's$i',
          code: codes[i],
          name: names[i],
          business: '虚构验收样本',
          thesis: '原研究判断',
          counterEvidence: '人工反证',
          reviewCondition: '人工复查',
          source: '',
          updatedAt: '2026-06-01',
        ),
    ],
    sources: [
      for (var i = 0; i < names.length; i++)
        SourceExcerpt(
          id: 'source$i',
          studyId: 's$i',
          title: '虚构2025年报',
          url: 'https://example.com/fictional-report-$i',
          period: '2025年',
          disclosedAt: '2026-04-30',
          page: '1',
          unit: '万元',
          text: '仅用于测试的虚构原文',
        ),
    ],
    financials: [
      for (var i = 0; i < names.length; i++)
        FinancialRecord(
          id: 'financial$i',
          studyId: 's$i',
          sourceId: 'source$i',
          start: '2025-01-01',
          end: '2025-12-31',
          disclosedAt: '2026-04-30',
          unit: '万元',
          revenue: 100,
          adjustedProfit: i == 2
              ? null
              : i == 1
              ? 5
              : 20,
          operatingCash: negativeCash && i == 0
              ? -30
              : i == 1
              ? 10
              : 30,
          cash: 40,
          debt: 10,
          scope: '合并',
          basis: '原披露',
        ),
    ],
    quant: QuantState(versions: configured ? [quantUiConfig()] : []),
  );
}

class QuantHarness extends StatefulWidget {
  const QuantHarness({
    super.key,
    required this.initial,
    this.saveSuccess = true,
    this.scale = 1,
    this.onOpen,
  });
  final WorkspaceData initial;
  final bool saveSuccess;
  final double scale;
  final ValueChanged<String>? onOpen;
  @override
  State<QuantHarness> createState() => QuantHarnessState();
}

class QuantHarnessState extends State<QuantHarness> {
  late WorkspaceData data = widget.initial;
  int saves = 0;
  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(widget.scale)),
      child: child!,
    ),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(widget.scale)),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: QuantResearchPanel(
              data: data,
              onSave: (next) async {
                saves++;
                if (widget.saveSuccess) setState(() => data = next);
                return widget.saveSuccess;
              },
              onOpenResearch: widget.onOpen ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> showQuantControl(WidgetTester tester, String key) async {
  final group = key == 'quant-add-capital'
      ? 'quant-capital-section'
      : const [
          'quant-config-window',
          'quant-config-age',
          'quant-config-excluded',
          'quant-config-review-days',
          'quant-config-review-condition',
        ].contains(key)
      ? 'quant-config-advanced'
      : null;
  if (group != null && find.byKey(ValueKey(key)).evaluate().isEmpty) {
    await tester.ensureVisible(find.byKey(ValueKey(group)));
    await tester.tap(find.byKey(ValueKey(group)));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> tapQuantControl(WidgetTester tester, String key) async {
  await showQuantControl(tester, key);
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> editQuantControl(
  WidgetTester tester,
  String key,
  String value,
) async {
  await showQuantControl(tester, key);
  await tester.enterText(find.byKey(ValueKey(key)), value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认展示状态与结果，参数说明和资料维护按需展开', (tester) async {
    final key = GlobalKey<QuantHarnessState>();
    final before = quantUiFixture();
    await tester.pumpWidget(QuantHarness(key: key, initial: before));
    expect(find.text('已核对并启用'), findsOneWidget);
    expect(find.textContaining('最新年度所需字段'), findsWidgets);
    expect(find.textContaining('综合分 = 100'), findsNothing);
    expect(find.byKey(const ValueKey('quant-add-capital')), findsNothing);
    expect(find.textContaining('至 2025-12-31：'), findsNothing);
    await tapQuantControl(tester, 'quant-calculation-info');
    expect(find.textContaining('综合分 = 100'), findsOneWidget);
    await tapQuantControl(tester, 'quant-current-parameters');
    expect(find.textContaining('确认时间'), findsOneWidget);
    expect(key.currentState!.data.encode(), before.encode());
    expect(key.currentState!.saves, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折叠的高级设置有误时自动展开，错误参数不会保存', (tester) async {
    final key = GlobalKey<QuantHarnessState>();
    await tester.pumpWidget(QuantHarness(key: key, initial: quantUiFixture()));
    await tapQuantControl(tester, 'quant-edit');
    expect(find.byKey(const ValueKey('quant-config-window')), findsNothing);
    await editQuantControl(tester, 'quant-config-window', '1');
    await tester.ensureVisible(find.text('高级设置'));
    await tester.tap(find.text('高级设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quant-config-window')), findsNothing);
    await tapQuantControl(tester, 'quant-config-save');
    expect(find.byKey(const ValueKey('quant-config-window')), findsOneWidget);
    expect(find.text('请输入 2 至 250 的整数'), findsOneWidget);
    expect(find.text('请检查高级设置中标出的参数'), findsOneWidget);
    expect(key.currentState!.saves, 0);
    await editQuantControl(tester, 'quant-config-window', '20');
    await tapQuantControl(tester, 'quant-config-save');
    expect(key.currentState!.saves, 1);
    expect(key.currentState!.data.quant.currentConfig!.confirmed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('初始无规则，示例保存后仍未启用、不评分、不改资金研究', (tester) async {
    final key = GlobalKey<QuantHarnessState>();
    final before = quantUiFixture(configured: false);
    await tester.pumpWidget(QuantHarness(key: key, initial: before));
    expect(find.text('尚未配置规则，未计算综合分'), findsOneWidget);
    await tapQuantControl(tester, 'quant-example');
    await editQuantControl(tester, 'quant-config-date', '2026-06-01');
    await tapQuantControl(tester, 'quant-config-save');
    final data = key.currentState!.data;
    expect(data.quant.versions, hasLength(1));
    expect(data.quant.currentConfig!.confirmed, isFalse);
    expect(evaluateQuant(data).ranked, isEmpty);
    expect(evaluateQuant(data).rows.every((r) => r.score == null), isTrue);
    expect(data.cash, before.cash);
    expect(data.deposits, before.deposits);
    expect(data.studies.first.thesis, before.studies.first.thesis);
    expect(find.text('未启用：不计算综合分与排名'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('改变权重和阈值创建版本，修改会取消核对，手算分数同步变化', (tester) async {
    final key = GlobalKey<QuantHarnessState>();
    await tester.pumpWidget(QuantHarness(key: key, initial: quantUiFixture()));
    expect(evaluateQuant(key.currentState!.data).rows[1].score, 25);
    await tapQuantControl(tester, 'quant-edit');
    await tapQuantControl(tester, 'quant-config-confirm');
    await editQuantControl(tester, 'quant-rule-weight-1', '3');
    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('quant-config-confirm')),
    );
    expect(checkbox.value, isFalse);
    expect(key.currentState!.data.quant.versions, hasLength(1));
    await tapQuantControl(tester, 'quant-config-confirm');
    await tapQuantControl(tester, 'quant-config-save');
    var data = key.currentState!.data;
    expect(data.quant.versions, hasLength(2));
    expect(data.quant.currentConfig!.revision, 2);
    expect(evaluateQuant(data).rows[0].score, 100);
    expect(evaluateQuant(data).rows[1].score, 50);
    expect(data.quant.versions.first.rules[1].weight, 1);
    await tapQuantControl(tester, 'quant-edit');
    await editQuantControl(tester, 'quant-rule-threshold-0', '25');
    await tapQuantControl(tester, 'quant-config-confirm');
    await tapQuantControl(tester, 'quant-config-save');
    data = key.currentState!.data;
    expect(evaluateQuant(data).ranked, isEmpty);
    expect(evaluateQuant(data).rows[0].score, 50);
    expect(data.quant.currentConfig!.revision, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消与保存失败保留全部旧参数，失败对话框可重试', (tester) async {
    final key = GlobalKey<QuantHarnessState>();
    final before = quantUiFixture().encode();
    await tester.pumpWidget(
      QuantHarness(key: key, initial: quantUiFixture(), saveSuccess: false),
    );
    await tapQuantControl(tester, 'quant-edit');
    await editQuantControl(tester, 'quant-config-name', '不会保存');
    await tapQuantControl(tester, 'quant-config-cancel');
    expect(key.currentState!.data.encode(), before);
    expect(key.currentState!.saves, 0);
    await tapQuantControl(tester, 'quant-edit');
    await editQuantControl(tester, 'quant-config-name', '保存失败');
    await tapQuantControl(tester, 'quant-config-confirm');
    await tapQuantControl(tester, 'quant-config-save');
    expect(key.currentState!.data.encode(), before);
    expect(find.byKey(const ValueKey('quant-config-save')), findsOneWidget);
    expect(find.text('保存失败，原参数与结果已保留，请重试'), findsOneWidget);
    await tapQuantControl(tester, 'quant-config-cancel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('结果显示原值、来源、贡献与特殊行业未知，研究入口保持study归属', (tester) async {
    String? opened;
    await tester.pumpWidget(
      QuantHarness(initial: quantUiFixture(), onOpen: (id) => opened = id),
    );
    expect(find.textContaining('银行、保险、证券不适用'), findsWidgets);
    expect(find.textContaining('最新年度所需字段'), findsWidgets);
    await tapQuantControl(tester, 'quant-open-research-SH:600001');
    expect(opened, 's0');
    await tapQuantControl(tester, 'quant-details-SH:600001');
    expect(find.textContaining('经营现金流：30 万元'), findsOneWidget);
    expect(find.textContaining('来源 source0'), findsWidgets);
    expect(find.textContaining('贡献 75 分'), findsOneWidget);
    expect(find.textContaining('贡献 25 分'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('复用历史参数创建未启用新版本，保留原确认与阈值', (tester) async {
    final key = GlobalKey<QuantHarnessState>();
    await tester.pumpWidget(QuantHarness(key: key, initial: quantUiFixture()));
    await tapQuantControl(tester, 'quant-versions');
    expect(find.textContaining('早期版本请先导出备份'), findsOneWidget);
    await tapQuantControl(tester, 'quant-reuse-fixture-v1');
    await tapQuantControl(tester, 'quant-config-save');
    final versions = key.currentState!.data.quant.versions;
    expect(versions, hasLength(2));
    expect(versions.first.confirmed, isTrue);
    expect(versions.last.confirmed, isFalse);
    expect(versions.last.revision, 2);
    expect(versions.last.rules.first.threshold, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('负经营现金流保留负因子值，真实贡献为零，原值对照注明期间', (tester) async {
    final data = quantUiFixture(negativeCash: true);
    final row = evaluateQuant(data).rows.first;
    expect(row.score, 75);
    expect(row.rules[1].value.value, -1.5);
    expect(row.rules[1].contribution, 0);
    await tester.pumpWidget(QuantHarness(initial: data));
    await tapQuantControl(tester, 'quant-comparison');
    expect(find.textContaining('至 2025-12-31：-1.5 倍'), findsOneWidget);
    await tapQuantControl(tester, 'quant-details-SH:600001');
    expect(find.textContaining('经营现金流：-30 万元'), findsOneWidget);
    expect(find.textContaining('未命中；贡献 0 分'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部权重为零显示仅筛选，入选不伪装成排名或资料缺失', (tester) async {
    final config = quantUiConfig().copyWith(
      rules: [
        const QuantRule(
          id: 'filter-only',
          factor: QuantFactor.adjustedProfitMargin,
          comparison: QuantComparison.gte,
          threshold: 10,
          weight: 0,
          filter: true,
        ),
      ],
    );
    final data = quantUiFixture().copyWith(
      quant: QuantState(versions: [config]),
    );
    final result = evaluateQuant(data);
    expect(result.rows.first.selected, isTrue);
    expect(result.rows.first.score, isNull);
    expect(result.ranked, isEmpty);
    await tester.pumpWidget(QuantHarness(initial: data));
    expect(find.textContaining('筛选通过（仅筛选）'), findsOneWidget);
    expect(find.textContaining('未设置评分权重，不显示综合分或排名'), findsOneWidget);
    expect(find.textContaining('样本内第'), findsNothing);
    await tapQuantControl(tester, 'quant-details-SH:600001');
    expect(find.textContaining('贡献 不参与评分'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('总股本选择公司来源，日期或股数改动使核验失效，待核验可保存', (tester) async {
    final key = GlobalKey<QuantHarnessState>();
    await tester.pumpWidget(QuantHarness(key: key, initial: quantUiFixture()));
    await tapQuantControl(tester, 'quant-add-capital');
    await tapQuantControl(tester, 'quant-capital-source-SH:600001');
    await tester.tap(find.text('虚构2025年报 · 2026-04-30').last);
    await tester.pumpAndSettle();
    await editQuantControl(tester, 'quant-capital-effective', '2025-12-31');
    await editQuantControl(tester, 'quant-capital-shares', '100000');
    await tapQuantControl(tester, 'quant-capital-verified');
    await editQuantControl(tester, 'quant-capital-shares', '200000');
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('quant-capital-verified')),
          )
          .value,
      isFalse,
    );
    await tapQuantControl(tester, 'quant-capital-save');
    final fact = key.currentState!.data.quant.shareFacts.single;
    expect(fact.symbol, 'SH:600001');
    expect(fact.sourceId, 'source0');
    expect(fact.disclosedAt, '2026-04-30');
    expect(fact.totalShares, 200000);
    expect(fact.verified, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('390px两倍字体可以编辑口径日期并增删规则，无横向溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<QuantHarnessState>();
    await tester.pumpWidget(
      QuantHarness(key: key, initial: quantUiFixture(), scale: 2),
    );
    expect(tester.takeException(), isNull);
    await tapQuantControl(tester, 'quant-edit');
    await editQuantControl(tester, 'quant-config-date', '2026-06-02');
    await tapQuantControl(tester, 'quant-config-scope');
    await tester.tap(find.text('母公司').last);
    await tester.pumpAndSettle();
    await tapQuantControl(tester, 'quant-add-rule');
    await editQuantControl(tester, 'quant-rule-threshold-2', '-5');
    await tapQuantControl(tester, 'quant-rule-delete-1');
    await tapQuantControl(tester, 'quant-config-save');
    final config = key.currentState!.data.quant.currentConfig!;
    expect(config.scope, '母公司');
    expect(config.asOfDate, '2026-06-02');
    expect(config.rules, hasLength(2));
    expect(config.rules.last.threshold, -5);
    expect(config.confirmed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
