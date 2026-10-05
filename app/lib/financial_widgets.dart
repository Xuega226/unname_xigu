import 'package:flutter/material.dart';

import 'domain.dart';
import 'financial_trends.dart';
import 'research.dart';

export 'financial_verification_widgets.dart';

class FinancialTrendDialog extends StatefulWidget {
  const FinancialTrendDialog({
    super.key,
    required this.study,
    required this.records,
  });
  final Study study;
  final List<FinancialRecord> records;
  @override
  State<FinancialTrendDialog> createState() => _FinancialTrendDialogState();
}

class _FinancialTrendDialogState extends State<FinancialTrendDialog> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final groups = widget.records.map(financialWindow).toSet().toList()..sort();
    selected ??= groups.firstOrNull;
    final records =
        widget.records.where((r) => financialWindow(r) == selected).toList()
          ..sort((a, b) => a.end.compareTo(b.end));
    String amount(double? value, String unit) =>
        value == null ? '资料不足' : inTenThousands(value, unit).toStringAsFixed(2);
    return AlertDialog(
      title: Text('${widget.study.name} · 多年度财务变化'),
      content: SizedBox(
        width: 1000,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '显示金额统一换算为万元。只在同一报表口径、同一期间类型、相邻年度且各期仅一条原披露记录时计算同比。口径不明、重述、重复、缺值、零或负基数不自动计算；金融行业需结合专用口径。',
              ),
              const SizedBox(height: 16),
              if (groups.isEmpty) const Text('尚无已核验财务记录'),
              if (groups.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  items: groups
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => selected = v),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('报告期 / 原单位')),
                    ...FinancialRecord.labels.map(
                      (l) => DataColumn(label: Text('$l\n万元')),
                    ),
                    const DataColumn(label: Text('营收同比')),
                    const DataColumn(label: Text('扣非净利同比')),
                  ],
                  rows: records.map((r) {
                    String growth(String metric) {
                      final v = financialYearGrowth(r, metric, widget.records);
                      return v == null
                          ? '不可自动比较'
                          : '${(v * 100).toStringAsFixed(1)}%';
                    }

                    return DataRow(
                      cells: [
                        DataCell(
                          Text(
                            '${r.start} 至 ${r.end}\n${r.unit} · ${r.confirmationLabel}',
                          ),
                        ),
                        ...r.amounts.values.map(
                          (v) => DataCell(Text(amount(v, r.unit))),
                        ),
                        DataCell(Text(growth('revenue'))),
                        DataCell(Text(growth('adjustedProfit'))),
                      ],
                    );
                  }).toList(),
                ),
              ),
              for (final r in records)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    '披露 ${r.disclosedAt} · 来源 [${r.sourceId}]\n${r.evidence.entries.map((e) => '${FinancialRecord.labels[FinancialRecord.metrics.indexOf(e.key)]}：[${e.value.sourceId}]「${e.value.quote}」').join('\n')}',
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
    );
  }
}
