import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';

const _cashColor = Color(0xff547aa5);
const _stockColor = Color(0xff157d72);
const _lossColor = Color(0xffb26b30);

String _amount(double value) => '¥${value.toStringAsFixed(2)}';
String _percent(double? value) =>
    value == null ? '无法计算' : '${(value * 100).toStringAsFixed(1)}%';

class RiskExposure {
  const RiskExposure(this.label, this.value, this.details);
  final String label, details;
  final double value;
}

/// The same account-asset and net-principal denominators as WorkspaceData.
/// This view model never writes the workspace or infers transactions.
class RiskChartValues {
  RiskChartValues(this.data);
  final WorkspaceData data;
  double? get cashWeight => data.assets > 0 ? data.cash / data.assets : null;
  double lossAmount(double decline) {
    data.stressLoss(decline); // Keep the domain's range validation.
    return data.stocks * decline;
  }

  double postAssets(double decline) => data.assets - lossAmount(decline);
  double? exposureWeight(RiskExposure row) =>
      data.assets > 0 ? row.value / data.assets : null;
  double get profitAmount => data.assets - data.principal;

  List<RiskExposure> get holdings => _sorted([
    for (final h in data.holdings)
      RiskExposure(
        '${h.name} · ${h.code}',
        h.marketValue,
        '${h.industry.trim().isEmpty ? '行业资料不足' : h.industry}；'
            '总数量 ${h.quantity.toStringAsFixed(2)} 股，市价 ${_amount(h.price)}',
      ),
  ]);

  List<RiskExposure> get industries {
    final amounts = <String, double>{};
    final securities = <String, List<String>>{};
    for (final h in data.holdings) {
      final industry = h.industry.trim().isEmpty ? '行业资料不足' : h.industry.trim();
      amounts.update(
        industry,
        (value) => value + h.marketValue,
        ifAbsent: () => h.marketValue,
      );
      securities.putIfAbsent(industry, () => []).add('${h.name} ${h.code}');
    }
    return _sorted([
      for (final entry in amounts.entries)
        RiskExposure(entry.key, entry.value, securities[entry.key]!.join('、')),
    ]);
  }

  List<RiskExposure> _sorted(List<RiskExposure> rows) => rows
    ..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      return byValue == 0 ? a.label.compareTo(b.label) : byValue;
    });
}

class RiskCharts extends StatelessWidget {
  const RiskCharts({
    super.key,
    required this.data,
    required this.stress,
    required this.onStressChanged,
  });
  final WorkspaceData data;
  final double stress;
  final ValueChanged<double> onStressChanged;

  @override
  Widget build(BuildContext context) {
    final values = RiskChartValues(data);
    final selected = stress.clamp(0.0, 1.0).toDouble();
    final date = DateTime.tryParse(data.priceDate);
    final today = DateUtils.dateOnly(DateTime.now());
    final stale = date != null && today.difference(date).inDays > 7;
    final status = data.isDemo
        ? '演示数据，不能用于真实账户判断'
        : data.portfolioImport == null
        ? '手工记录，尚未核验券商快照'
        : data.portfolioImport!.modified
        ? '导入后已修改，请重新核对估值'
        : '已导入文件；完整性和估值仍需人工核验';
    final cards = <Widget>[
      _ChartCard('资产构成', _assetComposition(context, values)),
      _ChartCard('相对本金盈亏', _principalGauge(context, values)),
      _ChartCard(
        '个股集中度',
        _ExposureBars(
          key: const ValueKey('risk-holdings'),
          values: values,
          rows: values.holdings,
          name: '个股',
        ),
      ),
      _ChartCard(
        '行业集中度',
        _ExposureBars(
          key: const ValueKey('risk-industries'),
          values: values,
          rows: values.industries,
          name: '行业',
        ),
      ),
      _ChartCard('指定情景压力曲线', _scenario(context, values, selected)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '风险图表 · 估值日期 ${data.priceDate}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '$status${stale ? '；估值已超过 7 天，数据可能陈旧' : ''}。'
          '全部价格应对应同一日期。',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            // Large text uses one column even on a medium desktop viewport.
            final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
          final columns = constraints.maxWidth >= 900 && !largeText ? 2 : 1;
            final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const Text(
          '历史净值与高点回撤：资料不足。需要连续估值和带日期的资金流水；'
          '导入历史不能替代净值序列。',
        ),
      ],
    );
  }

  Widget _assetComposition(BuildContext context, RiskChartValues values) {
    final assets = data.assets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('账户资产 ${_amount(assets)}；占比分母为账户资产'),
        const SizedBox(height: 12),
        if (assets <= 0)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('暂无账户资产，现金和股票占比无法计算。'),
          )
        else
          Center(
            child: Semantics(
              label:
                  '资产构成：现金 ${_amount(data.cash)} ${_percent(values.cashWeight)}；'
                  '股票 ${_amount(data.stocks)} ${_percent(data.stockWeight)}',
              button: true,
              child: InkWell(
                key: const ValueKey('risk-asset-details'),
                onTap: () => _details(
                  context,
                  '资产构成',
                  '现金 ${_amount(data.cash)}，占账户资产 ${_percent(values.cashWeight)}\n'
                      '股票 ${_amount(data.stocks)}，占账户资产 ${_percent(data.stockWeight)}\n'
                      '合计 ${_amount(assets)}；估值日期 ${data.priceDate}',
                ),
                child: SizedBox(
                  width: 176,
                  height: 176,
                  child: CustomPaint(
                    painter: _DonutPainter(values.cashWeight!),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _legend(
          _cashColor,
          '现金 ${_amount(data.cash)} · ${_percent(values.cashWeight)}',
        ),
        _legend(
          _stockColor,
          '股票 ${_amount(data.stocks)} · ${_percent(data.stockWeight)}',
        ),
        const Text('点按环形图查看数值。'),
      ],
    );
  }

  Widget _principalGauge(
    BuildContext context,
    RiskChartValues values,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('净投入本金 ${_amount(data.principal)}（入金减出金）'),
      Text('盈亏金额 ${_amount(values.profitAmount)}；比例分母为净投入本金'),
      const SizedBox(height: 12),
      if (data.profitRate == null)
        const Text('净投入本金不大于零，相对本金盈亏比例无法计算。请核对资金记录。')
      else ...[
        Semantics(
          label:
              '当前相对本金盈亏 ${_percent(data.profitRate)}；'
              '亏损偏好标记 ${_percent(-data.lossBudget)}',
          button: true,
          child: InkWell(
            key: const ValueKey('risk-principal-details'),
            onTap: () => _details(
              context,
              '相对本金盈亏',
              '净投入本金 ${_amount(data.principal)}\n'
                  '账户资产 ${_amount(data.assets)}\n'
                  '盈亏金额 ${_amount(values.profitAmount)}\n'
                  '盈亏比例 ${_percent(data.profitRate)}（分母为净投入本金）\n'
                  '亏损偏好标记 ${_percent(-data.lossBudget)}；不是止损指令',
            ),
            child: SizedBox(
              height: 68,
              width: double.infinity,
              child: CustomPaint(
                painter: _GaugePainter(data.profitRate!, data.lossBudget),
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            Text(
              '刻度下限 ${_percent(math.min(-1.0, math.min(data.profitRate!, -data.lossBudget)))}',
            ),
            const Text('灰线：0%'),
            Text('上限 ${_percent(math.max(1.0, data.profitRate!))}'),
          ],
        ),
        _legend(_stockColor, '圆点：当前盈亏 ${_percent(data.profitRate)}'),
        _legend(_lossColor, '竖线：亏损偏好标记 ${_percent(-data.lossBudget)}'),
      ],
      Text(
        '亏损偏好 ${_percent(data.lossBudget)} 是提醒参数，实际亏损可能超过它；'
        '不是账户资产的压力损失比例，也不是止损指令。',
      ),
    ],
  );

  Widget _scenario(
    BuildContext context,
    RiskChartValues values,
    double selected,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('横轴：所有股票假设跌幅 0%–100%；纵轴：损失 / 账户资产。现金不变。'),
      const SizedBox(height: 12),
      if (data.assets <= 0)
        const Text('暂无账户资产，压力损失比例无法计算。')
      else ...[
        Text('纵轴范围 0%–100%，当前股票权重 ${_percent(data.stockWeight)}'),
        Semantics(
          label:
              '指定情景曲线：股票下跌 ${_percent(selected)}，'
              '账户损失 ${_percent(data.stressLoss(selected))}',
          child: SizedBox(
            height: math.max(
              156,
              MediaQuery.textScalerOf(context).scale(12) * 10,
            ),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final value in [100, 75, 50, 25, 0])
                        Text('$value%', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                Expanded(
                  child: SizedBox.expand(
                    child: CustomPaint(
                      painter: _ScenarioPainter(data.stockWeight!, selected),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text('跌幅 0%'), Text('100%')],
        ),
      ],
      Text('假设股票下跌 ${_percent(selected)}'),
      Slider(
        key: const ValueKey('risk-stress-slider'),
        value: selected,
        min: 0,
        max: 1,
        divisions: 20,
        label: _percent(selected),
        semanticFormatterCallback: _percent,
        onChanged: onStressChanged,
      ),
      Text(
        '账户损失 ${_percent(data.stressLoss(selected))} · '
        '损失金额 ${_amount(values.lossAmount(selected))}',
      ),
      Text('情景后资产 ${_amount(values.postAssets(selected))}'),
      const Text('拖动滑块查看对应点和数值。这是指定情景，不是预测、VaR 或最大损失估计。'),
    ],
  );
}

Widget _legend(Color color, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 5, right: 8),
        child: SizedBox(width: 12, height: 12, child: ColoredBox(color: color)),
      ),
      Expanded(child: Text(text)),
    ],
  ),
);

void _details(BuildContext context, String title, String text) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

class _ChartCard extends StatelessWidget {
  const _ChartCard(this.title, this.child);
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _ExposureBars extends StatefulWidget {
  const _ExposureBars({
    super.key,
    required this.values,
    required this.rows,
    required this.name,
  });
  final RiskChartValues values;
  final List<RiskExposure> rows;
  final String name;
  @override
  State<_ExposureBars> createState() => _ExposureBarsState();
}

class _ExposureBarsState extends State<_ExposureBars> {
  int page = 0;
  static const pageSize = 25;
  @override
  Widget build(BuildContext context) {
    final pages = math.max(1, (widget.rows.length / pageSize).ceil());
    final current = page.clamp(0, pages - 1);
    final rows = widget.rows.skip(current * pageSize).take(pageSize);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('按市值排序，占比分母为账户资产 ${_amount(widget.values.data.assets)}。点按条形查看明细。'),
        if (widget.rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('尚无持仓。'),
          ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: InkWell(
              key: ValueKey('risk-${widget.name}-${row.label}'),
              onTap: () => _details(
                context,
                row.label,
                '${row.details}\n市值 ${_amount(row.value)}\n'
                '占账户资产 ${_percent(widget.values.exposureWeight(row))}\n'
                '估值日期 ${widget.values.data.priceDate}',
              ),
              child: Semantics(
                button: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.label),
                    Text(
                      '${_amount(row.value)} · ${_percent(widget.values.exposureWeight(row))}',
                    ),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value:
                          widget.values.exposureWeight(row)?.clamp(0.0, 1.0) ??
                          0,
                      minHeight: 10,
                      color: _stockColor,
                      semanticsLabel: '${row.label}账户资产占比',
                      semanticsValue: _percent(
                        widget.values.exposureWeight(row),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.rows.isNotEmpty)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('第 ${current + 1}/$pages 页 · 共 ${widget.rows.length} 项'),
              TextButton(
                key: ValueKey('risk-${widget.name}-previous'),
                onPressed: current > 0
                    ? () => setState(() => page = current - 1)
                    : null,
                child: const Text('上一页'),
              ),
              TextButton(
                key: ValueKey('risk-${widget.name}-next'),
                onPressed: current + 1 < pages
                    ? () => setState(() => page = current + 1)
                    : null,
                child: const Text('下一页'),
              ),
            ],
          ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.cashWeight);
  final double cashWeight;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(18, 18, size.width - 36, size.height - 36);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2,
      false,
      paint..color = _stockColor,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * cashWeight,
      false,
      paint..color = _cashColor,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      cashWeight != oldDelegate.cashWeight;
}

class _ScenarioPainter extends CustomPainter {
  _ScenarioPainter(this.weight, this.selected);
  final double weight, selected;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 8, size.width - 16, size.height - 16);
    final grid = Paint()
      ..color = const Color(0xffc9d7d4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = rect.bottom - rect.height * i / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }
    Offset point(double decline) => Offset(
      rect.left + rect.width * decline,
      rect.bottom - rect.height * weight * decline,
    );
    canvas.drawLine(
      point(0),
      point(1),
      Paint()
        ..color = _stockColor
        ..strokeWidth = 3,
    );
    final selectedPoint = point(selected);
    canvas.drawLine(
      Offset(selectedPoint.dx, rect.bottom),
      selectedPoint,
      Paint()
        ..color = _lossColor
        ..strokeWidth = 2,
    );
    canvas.drawCircle(selectedPoint, 6, Paint()..color = _lossColor);
  }

  @override
  bool shouldRepaint(_ScenarioPainter oldDelegate) =>
      weight != oldDelegate.weight || selected != oldDelegate.selected;
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.profit, this.budget);
  final double profit, budget;
  @override
  void paint(Canvas canvas, Size size) {
    final minimum = math.min(-1.0, math.min(profit, -budget));
    final maximum = math.max(1.0, profit);
    double x(double value) =>
        10 + (size.width - 20) * (value - minimum) / (maximum - minimum);
    final y = size.height / 2;
    canvas.drawLine(
      Offset(10, y),
      Offset(size.width - 10, y),
      Paint()
        ..color = const Color(0xffc9d7d4)
        ..strokeWidth = 10,
    );
    canvas.drawLine(
      Offset(x(0), y - 10),
      Offset(x(0), y + 10),
      Paint()
        ..color = Colors.blueGrey
        ..strokeWidth = 2,
    );
    canvas.drawLine(
      Offset(x(-budget), y - 20),
      Offset(x(-budget), y + 20),
      Paint()
        ..color = _lossColor
        ..strokeWidth = 3,
    );
    canvas.drawCircle(Offset(x(profit), y), 7, Paint()..color = _stockColor);
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) =>
      profit != oldDelegate.profit || budget != oldDelegate.budget;
}
