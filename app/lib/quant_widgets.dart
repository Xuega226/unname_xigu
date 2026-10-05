import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'research.dart';
import 'quant_models.dart';
import 'quant_engine.dart';

/// Local, explicit rule research. Saving never triggers an external request.
class QuantResearchPanel extends StatefulWidget {
  const QuantResearchPanel({
    super.key,
    required this.data,
    required this.onSave,
    required this.onOpenResearch,
  });
  final WorkspaceData data;
  final Future<bool> Function(WorkspaceData) onSave;
  final ValueChanged<String> onOpenResearch;

  @override
  State<QuantResearchPanel> createState() => _QuantResearchPanelState();
}

class _QuantResearchPanelState extends State<QuantResearchPanel> {
  String? _error;

  void _report(Object error) {
    if (mounted) setState(() => _error = '$error');
  }

  Future<void> _edit({QuantConfig? template, bool example = false}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ConfigDialog(
        state: widget.data.quant,
        template: template,
        example: example,
        onSave: (config) async {
          try {
            final next = widget.data.quant.addVersion(config);
            return await widget.onSave(widget.data.copyWith(quant: next));
          } catch (error) {
            _report(error);
            rethrow;
          }
        },
      ),
    );
  }

  Future<void> _versions() async {
    final chosen = await showDialog<QuantConfig>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('参数版本历史'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('保留最近 20 个版本，早期版本请先导出备份。复用旧版会创建新版本，并需重新核对后启用。'),
                for (final config in widget.data.quant.versions.reversed)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${config.name} · v${config.revision}'),
                          _ConfigText(config),
                          TextButton(
                            key: ValueKey('quant-reuse-${config.id}'),
                            onPressed: () => Navigator.pop(context, config),
                            child: const Text('复用为新的未启用版本'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (chosen != null && mounted) await _edit(template: chosen);
  }

  Future<void> _capital() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CapitalDialog(
        data: widget.data,
        onSave: (fact) async {
          final facts = [...widget.data.quant.shareFacts, fact];
          return widget.onSave(
            widget.data.copyWith(
              quant: widget.data.quant.copyWith(shareFacts: facts),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteCapital(ShareCapitalFact fact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条总股本资料？'),
        content: Text(
          '${fact.symbol} · 生效 ${fact.effectiveDate} · ${_number(fact.totalShares)} 股。删除后，依赖它的估值可能无法计算。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final facts = widget.data.quant.shareFacts
          .where((f) => f.id != fact.id)
          .toList();
      final saved = await widget.onSave(
        widget.data.copyWith(
          quant: widget.data.quant.copyWith(shareFacts: facts),
        ),
      );
      if (!saved) _report('保存失败，原总股本资料已保留');
    } catch (error) {
      _report(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.data.quant.currentConfig;
    final evaluation = evaluateQuant(widget.data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('在自选公司中检验规则。示例默认不启用，资料缺失时保留原因。'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('quant-edit'),
              onPressed: () => _edit(template: config),
              icon: const Icon(Icons.tune),
              label: Text(config == null ? '新建规则' : '修改为新版本'),
            ),
            OutlinedButton(
              key: const ValueKey('quant-example'),
              onPressed: () => _edit(example: true),
              child: const Text('载入未启用示例'),
            ),
            if (widget.data.quant.versions.isNotEmpty)
              OutlinedButton(
                key: const ValueKey('quant-versions'),
                onPressed: _versions,
                child: const Text('参数版本历史'),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        _Panel(
          title: config == null
              ? '尚未配置规则，未计算综合分'
              : '${config.name} · 参数 v${config.revision}',
          child: config == null
              ? const Text('示例默认不启用。创建参数后，需人工核对并明确确认，才开始评分与比较。')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(config.confirmed ? '已核对并启用' : '未启用：不计算综合分与排名'),
                    Text(
                      '观察日 ${config.asOfDate} · ${config.rules.length} 条规则 · ${config.scope}口径',
                    ),
                    ExpansionTile(
                      key: const ValueKey('quant-current-parameters'),
                      tilePadding: EdgeInsets.zero,
                      title: const Text('查看当前参数'),
                      children: [_ConfigText(config)],
                    ),
                  ],
                ),
        ),
        ExpansionTile(
          key: const ValueKey('quant-calculation-info'),
          title: const Text('计算说明'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: const [
            Text(
              '综合分 = 100 × 命中规则的权重之和 ÷ 全部规则权重之和。缺失或不适用的数据不按 0 处理，也不重新分配权重；资料不足时不评分、不入选。',
            ),
            SizedBox(height: 8),
            Text(
              '仅使用观察日前（不含观察日）的日线与已披露资料。当天 17 点后可获取日线，但评分在次日观察时才纳入；同日披露缺少时分信息，也从次日纳入。今天取回的资料不等于当年采集的快照。结果仅供研究，保存规则不会修改持仓、原研究或发送模型请求。',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Panel(
          title: '自选样本与筛选结果',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('自选样本 ${widget.data.watchlist.length} 家；结果仅在当前样本内比较。'),
              if (config == null || !config.confirmed) Text(evaluation.status),
              if (config != null && config.confirmed)
                Text(
                  '入选 ${evaluation.rows.where((r) => r.selected).length} 家。${config.rules.any((r) => r.weight > 0) ? '入选公司显示排名，未入选公司保留原因。' : '仅筛选：未设置评分权重，不显示综合分或排名。'}',
                ),
              if (evaluation.rows.isEmpty) const Text('请先在公司研究中添加自选公司。'),
              for (final row in evaluation.rows) _company(row, evaluation),
            ],
          ),
        ),
        if (config != null) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            key: const ValueKey('quant-comparison'),
            title: const Text('公司间因子对照'),
            subtitle: const Text('展开查看原值图表与资料缺失原因'),
            children: [_comparison(evaluation)],
          ),
        ],
        const SizedBox(height: 12),
        ExpansionTile(
          key: const ValueKey('quant-capital-section'),
          title: const Text('总股本资料'),
          subtitle: Text(
            '${widget.data.quant.shareFacts.length} 条资料 · 已核验 ${widget.data.quant.shareFacts.where((f) => f.verified).length} · 待核验 ${widget.data.quant.shareFacts.where((f) => !f.verified).length}',
          ),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '市销率须使用公司总股本与可核验来源，不使用个人持仓数量。生效日、披露日、来源或已核验状态不足时保留未知。',
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const ValueKey('quant-add-capital'),
                    onPressed: widget.data.watchlist.isEmpty ? null : _capital,
                    child: const Text('记录总股本资料'),
                  ),
                ),
                if (widget.data.quant.shareFacts.isEmpty)
                  const Text('暂无总股本资料。'),
                for (final fact in widget.data.quant.shareFacts)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${fact.symbol} · ${_number(fact.totalShares)} 股 · ${fact.verified ? '已核验' : '待核验'}',
                        ),
                        Text(
                          '生效 ${fact.effectiveDate}；披露 ${fact.disclosedAt}；来源 ${_sourceDescription(fact.sourceId)}',
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            key: ValueKey('quant-delete-capital-${fact.id}'),
                            onPressed: () => _deleteCapital(fact),
                            child: const Text('删除资料'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _company(QuantCompanyResult row, QuantEvaluation evaluation) {
    final company = row.company;
    final rankIndex = evaluation.ranked.indexWhere(
      (r) => r.company.symbol == company.symbol,
    );
    final studies = widget.data.studies.where((s) => s.code == company.code);
    final hasWeights =
        evaluation.config?.rules.any((r) => r.weight > 0) ?? false;
    final status = row.excluded
        ? '已排除'
        : row.selected
        ? row.score == null
              ? '筛选通过（仅筛选）'
              : '入选 · 样本内第 ${rankIndex + 1} 名'
        : row.missingReasons.isNotEmpty
        ? '未评分 / 未入选'
        : '未通过筛选';
    final scoreText = !hasWeights && row.missingReasons.isEmpty
        ? '未设置评分权重'
        : row.score == null
        ? '未知'
        : '${_number(row.score!)} / 100';
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${company.name} · ${company.symbol}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('${company.industry} · $status；综合分 $scoreText'),
            for (final reason in row.missingReasons) Text('• $reason'),
            if (studies.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('quant-open-research-${company.symbol}'),
                  onPressed: () => widget.onOpenResearch(studies.first.id),
                  child: const Text('进入公司研究与人工核验'),
                ),
              ),
            ExpansionTile(
              key: ValueKey('quant-details-${company.symbol}'),
              tilePadding: EdgeInsets.zero,
              title: const Text('因子明细与分项贡献'),
              children: [for (final rule in row.rules) _ruleDetails(rule)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleDetails(QuantRuleResult result) {
    final factor = result.value;
    final rule = result.rule;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${rule.factor.label}：${factor.value == null ? factor.reason : '${_number(factor.value!)} ${factor.unit}'}',
          ),
          Text(
            '${rule.comparison == QuantComparison.gte ? '≥' : '≤'} ${_number(rule.threshold)} ${rule.factor.unit}；权重 ${_number(rule.weight)}；${rule.filter ? '必须通过的筛选条件' : '仅参与评分'}',
          ),
          Text(
            '规则${result.passed == null
                ? '无法判断'
                : result.passed!
                ? '命中'
                : '未命中'}；贡献 ${rule.weight == 0
                ? '不参与评分'
                : result.contribution == null
                ? '未知'
                : '${_number(result.contribution!)} 分'}',
          ),
          if (result.contribution != null) ...[
            const SizedBox(height: 4),
            Semantics(
              label: '该规则贡献 ${_number(result.contribution!)} 分，满分 100 分',
              child: LinearProgressIndicator(
                value: (result.contribution! / 100).clamp(0.0, 1.0),
              ),
            ),
          ],
          Text('公式：${factor.formula}'),
          if (factor.reason.isNotEmpty) Text(factor.reason),
          for (final proof in factor.evidence)
            Text(
              '${proof.label}：${proof.rawValue == null ? '未知' : _number(proof.rawValue!)} ${proof.unit}；期间 ${proof.period}；披露 ${proof.disclosedAt}；来源 ${_sourceDescription(proof.sourceId)}',
            ),
        ],
      ),
    );
  }

  Widget _comparison(QuantEvaluation evaluation) {
    final factors = evaluation.config!.rules.map((r) => r.factor).toSet();
    return _Panel(
      title: '公司间因子对照',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('逐因子比较相同定义、相同单位的原值。正负值按实际方向绘制，资料不足保留原因；不把不同指标放在同一个数轴上。'),
          for (final factor in factors)
            Builder(
              builder: (context) {
                final values = <(String, double)>[];
                final unknown = <String>[];
                for (final row in evaluation.rows) {
                  final matches = row.rules.where(
                    (r) => r.rule.factor == factor,
                  );
                  if (matches.isEmpty) continue;
                  final value = matches.first.value;
                  if (value.value != null && value.unit == factor.unit) {
                    final periods = value.evidence
                        .map((proof) => proof.period)
                        .toSet()
                        .join('；');
                    values.add((
                      periods.isEmpty
                          ? row.company.name
                          : '${row.company.name} · $periods',
                      value.value!,
                    ));
                  } else {
                    unknown.add(
                      '${row.company.name}：${value.reason.isEmpty ? '资料不足' : value.reason}',
                    );
                  }
                }
                final low = values.fold<double>(0, (v, e) => math.min(v, e.$2));
                final high = values.fold<double>(
                  0,
                  (v, e) => math.max(v, e.$2),
                );
                return Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${factor.label}（${factor.unit}）',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final entry in values) ...[
                        Text('${entry.$1}：${_number(entry.$2)} ${factor.unit}'),
                        Semantics(
                          label:
                              '${entry.$1}，${factor.label} ${_number(entry.$2)} ${factor.unit}',
                          child: SizedBox(
                            height: 18,
                            child: CustomPaint(
                              painter: _FactorBar(entry.$2, low, high),
                            ),
                          ),
                        ),
                      ],
                      for (final reason in unknown) Text(reason),
                      if (values.isEmpty && unknown.isEmpty)
                        const Text('尚无可比较因子值。'),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _sourceDescription(String id) {
    final matches = widget.data.sources.where((source) => source.id == id);
    if (matches.isEmpty) return id;
    final source = matches.first;
    final location = source.url.isNotEmpty
        ? source.url
        : '本地文件 ${source.documentId}';
    return '$id · ${source.title} · 第 ${source.page} 页 · $location';
  }
}

String _number(double number) => number == number.roundToDouble()
    ? number.toStringAsFixed(0)
    : (number.abs() < .000001 || number.abs() > 1e12)
    ? number.toStringAsPrecision(10)
    : number
          .toStringAsFixed(8)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _ConfigText extends StatelessWidget {
  const _ConfigText(this.config);
  final QuantConfig config;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        config.confirmed
            ? '已核对并启用；确认时间 ${config.confirmedAt}'
            : '未启用：不计算综合分与排名',
      ),
      Text(
        '观察日 ${config.asOfDate}；财务口径 ${config.scope}；动量窗口 ${config.momentumWindow} 个日线观测间隔（需 ${config.momentumWindow + 1} 根日线）；价格最长 ${config.maxPriceAgeDays} 个自然日',
      ),
      Text('复查间隔 ${config.reviewIntervalDays} 天；${config.reviewCondition}'),
      Text(
        '排除行业：${config.excludedIndustries.isEmpty ? '无' : config.excludedIndustries.join('、')}',
      ),
      for (final rule in config.rules)
        Text(
          '${rule.factor.label} ${rule.comparison == QuantComparison.gte ? '≥' : '≤'} ${_number(rule.threshold)} ${rule.factor.unit}；权重 ${_number(rule.weight)}；${rule.weight == 0
              ? '仅筛选'
              : rule.filter
              ? '筛选 + 评分'
              : '评分'}',
        ),
    ],
  );
}

class _FactorBar extends CustomPainter {
  const _FactorBar(this.value, this.low, this.high);
  final double value, low, high;
  @override
  void paint(Canvas canvas, Size size) {
    final span = high - low;
    final zero = span > 0 ? -low / span * size.width : 0.0;
    final end = span > 0 ? (value - low) / span * size.width : 0.0;
    canvas.drawLine(
      Offset(zero, 0),
      Offset(zero, size.height),
      Paint()..color = const Color(0xff777777),
    );
    canvas.drawRect(
      Rect.fromLTRB(
        math.min(zero, end),
        3,
        math.max(zero, end),
        size.height - 3,
      ),
      Paint()
        ..color = value < 0 ? const Color(0xffb26b30) : const Color(0xff157d72),
    );
  }

  @override
  bool shouldRepaint(covariant _FactorBar oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.low != low ||
      oldDelegate.high != high;
}

class _RuleDraft {
  _RuleDraft(QuantRule rule)
    : id = rule.id,
      factor = rule.factor,
      comparison = rule.comparison,
      threshold = TextEditingController(text: _number(rule.threshold)),
      weight = TextEditingController(text: _number(rule.weight)),
      filter = rule.filter;
  final String id;
  QuantFactor factor;
  QuantComparison comparison;
  final TextEditingController threshold, weight;
  bool filter;
  void dispose() {
    threshold.dispose();
    weight.dispose();
  }
}

class _ConfigDialog extends StatefulWidget {
  const _ConfigDialog({
    required this.state,
    this.template,
    required this.example,
    required this.onSave,
  });
  final QuantState state;
  final QuantConfig? template;
  final bool example;
  final Future<bool> Function(QuantConfig) onSave;
  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  final _form = GlobalKey<FormState>();
  final _advanced = ExpansibleController();
  late TextEditingController _name,
      _date,
      _window,
      _age,
      _excluded,
      _reviewDays,
      _reviewCondition;
  late List<_RuleDraft> _rules;
  final List<_RuleDraft> _retiredRules = [];
  late String _scope;
  bool _confirmed = false, _saving = false;
  String? _error;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _name = TextEditingController(
      text: template?.name ?? (widget.example ? '示例规则（请自行核对）' : '我的研究规则'),
    );
    _date = TextEditingController(
      text:
          template?.asOfDate ??
          DateTime.now().toIso8601String().substring(0, 10),
    );
    _window = TextEditingController(text: '${template?.momentumWindow ?? 20}');
    _age = TextEditingController(text: '${template?.maxPriceAgeDays ?? 7}');
    _excluded = TextEditingController(
      text: template?.excludedIndustries.join('、') ?? '',
    );
    _reviewDays = TextEditingController(
      text: '${template?.reviewIntervalDays ?? 30}',
    );
    _reviewCondition = TextEditingController(
      text: template?.reviewCondition ?? '人工核验新披露与反证，不自动调仓',
    );
    _scope = template?.scope ?? '合并';
    final initial =
        template?.rules ??
        (widget.example
            ? [
                const QuantRule(
                  id: 'example-margin',
                  factor: QuantFactor.adjustedProfitMargin,
                  comparison: QuantComparison.gte,
                  threshold: 10,
                  weight: 1,
                  filter: true,
                ),
                const QuantRule(
                  id: 'example-cash',
                  factor: QuantFactor.cashProfitRatio,
                  comparison: QuantComparison.gte,
                  threshold: 1,
                  weight: 1,
                  filter: false,
                ),
              ]
            : [
                const QuantRule(
                  id: 'first-rule',
                  factor: QuantFactor.close,
                  comparison: QuantComparison.lte,
                  threshold: 20,
                  weight: 1,
                  filter: true,
                ),
              ]);
    _rules = initial.map(_RuleDraft.new).toList();
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _date,
      _window,
      _age,
      _excluded,
      _reviewDays,
      _reviewCondition,
    ]) {
      c.dispose();
    }
    for (final rule in [..._rules, ..._retiredRules]) {
      rule.dispose();
    }
    _advanced.dispose();
    super.dispose();
  }

  void _changed(VoidCallback change) => setState(() {
    change();
    _confirmed = false;
    _error = null;
  });

  Future<void> _save() async {
    if (_saving) return;
    if (_integer(_window.text, 2, 250) != null ||
        _integer(_age.text, 0, 365) != null ||
        _integer(_reviewDays.text, 1, 3650) != null ||
        _required(_reviewCondition.text) != null) {
      _advanced.expand();
      setState(() => _error = '请检查高级设置中标出的参数');
    }
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final nextRevision =
          widget.state.versions.fold<int>(
            0,
            (v, e) => math.max(v, e.revision),
          ) +
          1;
      final config = QuantConfig.fromJson(
        QuantConfig(
          id: 'quant-${DateTime.now().microsecondsSinceEpoch}',
          revision: nextRevision,
          name: _name.text.trim(),
          asOfDate: _date.text.trim(),
          scope: _scope,
          momentumWindow: int.parse(_window.text.trim()),
          maxPriceAgeDays: int.parse(_age.text.trim()),
          reviewIntervalDays: int.parse(_reviewDays.text.trim()),
          reviewCondition: _reviewCondition.text.trim(),
          excludedIndustries: _excluded.text
              .split(RegExp('[、,，;；\n]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList(),
          rules: [
            for (final rule in _rules)
              QuantRule(
                id: rule.id,
                factor: rule.factor,
                comparison: rule.comparison,
                threshold: double.parse(rule.threshold.text.trim()),
                weight: double.parse(rule.weight.text.trim()),
                filter: rule.filter,
              ),
          ],
          confirmed: _confirmed,
          confirmedAt: _confirmed
              ? DateTime.now().toUtc().toIso8601String()
              : null,
        ).toJson(),
      );
      final saved = await widget.onSave(config);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context);
      } else {
        setState(() => _error = '保存失败，原参数与结果已保留，请重试');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key,
    String? Function(String?) validate,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      decoration: InputDecoration(
        labelText: label.split('（').first,
        helperText: label.contains('（')
            ? label.substring(label.indexOf('（') + 1, label.length - 1)
            : null,
        helperMaxLines: 4,
        border: const OutlineInputBorder(),
      ),
      validator: validate,
      enabled: !_saving,
      onChanged: (_) => _changed(() {}),
    ),
  );
  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? '请填写此项' : null;
  String? _integer(String? v, int minimum, int maximum) {
    final number = int.tryParse(v?.trim() ?? '');
    return number == null || number < minimum || number > maximum
        ? '请输入 $minimum 至 $maximum 的整数'
        : null;
  }

  String? _finite(String? v, {bool nonnegative = false}) {
    final number = double.tryParse(v?.trim() ?? '');
    return number == null || !number.isFinite || (nonnegative && number < 0)
        ? '请输入${nonnegative ? '非负' : ''}有限数值'
        : null;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('编辑新参数版本'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          key: const ValueKey('quant-config-scroll'),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('保存为新版本；修改参数后请重新核对。示例默认未启用。'),
                const SizedBox(height: 12),
                _field(_name, '规则名称', 'quant-config-name', _required),
                _field(
                  _date,
                  '观察日 YYYY-MM-DD',
                  'quant-config-date',
                  (v) => validDate(v?.trim() ?? '') ? null : '请输入有效日期',
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('quant-config-scope'),
                  initialValue: _scope,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '财务口径',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final scope in ['合并', '母公司'])
                      DropdownMenuItem(value: scope, child: Text(scope)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => _changed(() => _scope = value!),
                ),
                const SizedBox(height: 12),
                ExpansionTile(
                  key: const ValueKey('quant-config-advanced'),
                  controller: _advanced,
                  maintainState: true,
                  tilePadding: EdgeInsets.zero,
                  title: const Text('高级设置'),
                  subtitle: const Text('动量窗口、价格时效、行业排除与复查'),
                  children: [
                    _field(
                      _window,
                      '动量窗口（日线观测间隔，2–250）',
                      'quant-config-window',
                      (v) => _integer(v, 2, 250),
                    ),
                    _field(
                      _age,
                      '价格最长距观察日（自然日，0–365）',
                      'quant-config-age',
                      (v) => _integer(v, 0, 365),
                    ),
                    _field(
                      _excluded,
                      '排除行业（顿号或逗号分隔）',
                      'quant-config-excluded',
                      (_) => null,
                    ),
                    _field(
                      _reviewDays,
                      '人工复查间隔（天）',
                      'quant-config-review-days',
                      (v) => _integer(v, 1, 3650),
                    ),
                    _field(
                      _reviewCondition,
                      '复查条件与人工操作约定',
                      'quant-config-review-condition',
                      _required,
                    ),
                  ],
                ),
                const Text(
                  '规则：阈值单位随因子显示。权重可为 0，但此规则必须用于筛选；全部权重为 0 时仅筛选，不评分或排名。',
                ),
                for (var index = 0; index < _rules.length; index++)
                  _ruleEditor(index),
                if (_rules.length < 30)
                  OutlinedButton.icon(
                    key: const ValueKey('quant-add-rule'),
                    onPressed: _saving
                        ? null
                        : () => _changed(
                            () => _rules.add(
                              _RuleDraft(
                                QuantRule(
                                  id: 'rule-${DateTime.now().microsecondsSinceEpoch}-${_nextId++}',
                                  factor: QuantFactor.adjustedProfitMargin,
                                  comparison: QuantComparison.gte,
                                  threshold: 10,
                                  weight: 1,
                                  filter: false,
                                ),
                              ),
                            ),
                          ),
                    icon: const Icon(Icons.add),
                    label: const Text('添加规则'),
                  ),
                CheckboxListTile(
                  key: const ValueKey('quant-config-confirm'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('我已核对本版本的范围、日期、公式、阈值、权重与排除条件，确认用于研究评分'),
                  value: _confirmed,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _confirmed = value!),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('quant-config-cancel'),
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('quant-config-save'),
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? '正在保存…'
                : _confirmed
                ? '确认并启用新版本'
                : '保存未启用版本',
          ),
        ),
      ],
    ),
  );

  Widget _ruleEditor(int index) {
    final rule = _rules[index];
    return Card(
      key: ValueKey(rule.id),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('规则 ${index + 1}'),
            DropdownButtonFormField<QuantFactor>(
              key: ValueKey('quant-rule-factor-$index'),
              initialValue: rule.factor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '因子'),
              items: [
                for (final factor in QuantFactor.values)
                  DropdownMenuItem(
                    value: factor,
                    child: Text('${factor.label}（${factor.unit}）'),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => _changed(() => rule.factor = value!),
            ),
            DropdownButtonFormField<QuantComparison>(
              key: ValueKey('quant-rule-comparison-$index'),
              initialValue: rule.comparison,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '比较条件'),
              items: const [
                DropdownMenuItem(
                  value: QuantComparison.gte,
                  child: Text('大于等于 ≥'),
                ),
                DropdownMenuItem(
                  value: QuantComparison.lte,
                  child: Text('小于等于 ≤'),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => _changed(() => rule.comparison = value!),
            ),
            const SizedBox(height: 8),
            _field(
              rule.threshold,
              '阈值（${rule.factor.unit}）',
              'quant-rule-threshold-$index',
              _finite,
            ),
            _field(
              rule.weight,
              '评分权重',
              'quant-rule-weight-$index',
              (v) => _finite(v, nonnegative: true),
            ),
            CheckboxListTile(
              key: ValueKey('quant-rule-filter-$index'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('作为必须通过的筛选条件'),
              value: rule.filter,
              onChanged: _saving
                  ? null
                  : (value) => _changed(() => rule.filter = value!),
            ),
            if (_rules.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: ValueKey('quant-rule-delete-$index'),
                  onPressed: _saving
                      ? null
                      : () => _changed(() {
                          _rules.removeAt(index);
                          _retiredRules.add(rule);
                        }),
                  child: const Text('删除规则'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CapitalDialog extends StatefulWidget {
  const _CapitalDialog({required this.data, required this.onSave});
  final WorkspaceData data;
  final Future<bool> Function(ShareCapitalFact) onSave;
  @override
  State<_CapitalDialog> createState() => _CapitalDialogState();
}

class _CapitalDialogState extends State<_CapitalDialog> {
  final _form = GlobalKey<FormState>();
  final _effective = TextEditingController(),
      _disclosed = TextEditingController(),
      _shares = TextEditingController();
  late String _symbol;
  String? _sourceId, _error;
  bool _verified = false, _saving = false;
  @override
  void initState() {
    super.initState();
    _symbol = widget.data.watchlist.first.symbol;
  }

  @override
  void dispose() {
    _effective.dispose();
    _disclosed.dispose();
    _shares.dispose();
    super.dispose();
  }

  List<SourceExcerpt> get _sources {
    final code = _symbol.split(':').last;
    final studies = widget.data.studies
        .where((s) => s.code == code)
        .map((s) => s.id)
        .toSet();
    return widget.data.sources
        .where((s) => studies.contains(s.studyId))
        .toList();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fact = ShareCapitalFact.fromJson(
        ShareCapitalFact(
          id: 'capital-${DateTime.now().microsecondsSinceEpoch}',
          symbol: _symbol,
          effectiveDate: _effective.text.trim(),
          disclosedAt: _disclosed.text.trim(),
          totalShares: double.parse(_shares.text.trim()),
          sourceId: _sourceId!,
          verified: _verified,
        ).toJson(),
      );
      if (await widget.onSave(fact)) {
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        setState(() => _error = '保存失败，原资料已保留，请重试');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String key,
    String? Function(String?) validator,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      enabled: !_saving,
      decoration: InputDecoration(
        labelText: label.split('（').first,
        helperText: label.contains('（')
            ? label.substring(label.indexOf('（') + 1, label.length - 1)
            : null,
        helperMaxLines: 4,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
      onChanged: (_) => setState(() => _verified = false),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('记录公司总股本'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('请从该公司的研究资料核对总股本，单位为股。修改任意字段后需重新勾选已核验。'),
                DropdownButtonFormField<String>(
                  key: const ValueKey('quant-capital-company'),
                  initialValue: _symbol,
                  isExpanded: true,
                  items: [
                    for (final company in widget.data.watchlist)
                      DropdownMenuItem(
                        value: company.symbol,
                        child: Text('${company.name} ${company.symbol}'),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _symbol = value!;
                          _sourceId = null;
                          _verified = false;
                          _disclosed.clear();
                        }),
                ),
                if (_sources.isEmpty) const Text('该公司没有研究来源，请先在公司研究中添加资料。'),
                DropdownButtonFormField<String>(
                  key: ValueKey('quant-capital-source-$_symbol'),
                  initialValue: _sourceId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '对应研究来源'),
                  items: [
                    for (final source in _sources)
                      DropdownMenuItem(
                        value: source.id,
                        child: Text(
                          '${source.title} · ${source.disclosedAt}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  validator: (value) => value == null ? '请选择该公司的来源' : null,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _sourceId = value;
                          _verified = false;
                          if (value != null) {
                            _disclosed.text = _sources
                                .firstWhere((s) => s.id == value)
                                .disclosedAt;
                          }
                        }),
                ),
                if (_sourceId != null)
                  Text(
                    '来源 ${_sources.firstWhere((s) => s.id == _sourceId).title} · ${_sources.firstWhere((s) => s.id == _sourceId).url}',
                  ),
                _field(
                  _effective,
                  '生效日 YYYY-MM-DD',
                  'quant-capital-effective',
                  (v) => validDate(v?.trim() ?? '') ? null : '请输入有效日期',
                ),
                _field(
                  _disclosed,
                  '实际披露日 YYYY-MM-DD',
                  'quant-capital-disclosed',
                  (v) => validDate(v?.trim() ?? '') ? null : '请输入有效日期',
                ),
                _field(_shares, '公司总股本（股，正整数）', 'quant-capital-shares', (v) {
                  final n = double.tryParse(v?.trim() ?? '');
                  return n == null ||
                          !n.isFinite ||
                          n < 1 ||
                          n != n.roundToDouble() ||
                          n > 1e15
                      ? '请输入有效的正整数股数'
                      : null;
                }),
                CheckboxListTile(
                  key: const ValueKey('quant-capital-verified'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('我已核对原资料、单位、日期与股数'),
                  value: _verified,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _verified = value!),
                ),
                const Text('待核验资料可以保存，但不会用于市销率。'),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('quant-capital-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '正在保存…' : '保存总股本资料'),
        ),
      ],
    ),
  );
}
