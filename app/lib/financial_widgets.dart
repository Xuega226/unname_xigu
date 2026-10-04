import 'package:flutter/material.dart';

import 'credentials.dart';
import 'domain.dart';
import 'financial_extraction.dart';
import 'financial_trends.dart';
import 'forms.dart';
import 'reports.dart';
import 'research.dart';
import 'services.dart';

class FinancialExtractionDialog extends StatefulWidget {
  const FinancialExtractionDialog({
    super.key,
    required this.study,
    required this.sources,
    required this.documents,
    required this.store,
    required this.service,
    required this.save,
  });
  final Study study;
  final List<SourceExcerpt> sources;
  final List<ReportDocument> documents;
  final CredentialStore store;
  final DeepSeekService service;
  final Future<bool> Function(FinancialRecord) save;
  @override
  State<FinancialExtractionDialog> createState() =>
      _FinancialExtractionDialogState();
}

class _FinancialExtractionDialogState extends State<FinancialExtractionDialog> {
  final start = TextEditingController(), end = TextEditingController();
  final form = GlobalKey<FormState>();
  final sourceIds = <String>{}, chosen = <int>{};
  String scope = '合并', basis = '原披露', message = '';
  FinancialCandidateBatch? batch;
  bool busy = false, reviewed = false;
  List<SourceExcerpt> get sources =>
      widget.sources.where((s) => sourceIds.contains(s.id)).toList();
  @override
  void initState() {
    super.initState();
    if (widget.sources.isNotEmpty) {
      sourceIds.add(widget.sources.first.id);
      final docs = widget.documents.where(
        (d) => d.id == widget.sources.first.documentId,
      );
      if (docs.isNotEmpty) {
        start.text = docs.first.start;
        end.text = docs.first.end;
      }
    }
  }

  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  void invalidate() {
    batch = null;
    reviewed = false;
    chosen.clear();
  }

  String? error(FinancialCandidate c) {
    final problem = c.error(sources, start.text.trim(), end.text.trim(), scope);
    if (problem != null) return problem;
    final source = sources.singleWhere((s) => s.id == c.proof.sourceId);
    final docs = widget.documents.where((d) => d.id == source.documentId);
    if (docs.isNotEmpty &&
        (docs.first.start != c.start || docs.first.end != c.end)) {
      return '报告日期与导入财报不一致';
    }
    return null;
  }

  Future<void> generate() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      message = '';
      invalidate();
    });
    try {
      final settings = await widget.store.read();
      final result = await widget.service.extractFinancials(
        key: settings.key,
        model: settings.model,
        company: '${widget.study.name} ${widget.study.code}',
        sources: sources,
        start: start.text.trim(),
        end: end.text.trim(),
        scope: scope,
      );
      if (mounted) setState(() => batch = result);
    } on ServiceFailure catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) setState(() => message = '本机配置读取或候选值解析失败，未保存财务记录');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> accept() async {
    if (!reviewed || batch == null || chosen.isEmpty) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final selected = chosen.map((i) => batch!.candidates[i]).toList();
      if (selected.any((c) => error(c) != null)) {
        throw const FormatException('所选候选的引用或期间无效');
      }
      final record = confirmFinancialCandidates(
        studyId: widget.study.id,
        candidates: selected,
        sources: sources,
        start: start.text.trim(),
        end: end.text.trim(),
        scope: scope,
        basis: basis,
      );
      final saved = await widget.save(record);
      if (mounted) {
        if (saved) {
          Navigator.pop(context, record);
        } else {
          setState(() => message = '保存失败，候选值未应用');
        }
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => message = e.message.toString());
    } catch (_) {
      if (mounted) setState(() => message = '财务保存失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = sources.fold<int>(0, (n, s) => n + s.text.length);
    return AlertDialog(
      title: Text('${widget.study.name} · AI 财务候选值'),
      content: SizedBox(
        width: 800,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '仅发送勾选原文及出处到 DeepSeek，按账户计费。提取结果须核对本期列、指标名称、单位及报表口径，确认后才保存。',
                ),
                const SizedBox(height: 12),
                for (final entry in [('报告开始日期', start), ('报告结束日期', end)])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: entry.$2,
                      enabled: !busy,
                      decoration: InputDecoration(labelText: entry.$1),
                      validator: (v) => InputField(
                        entry.$1,
                        '',
                        date: true,
                      ).validate(v ?? ''),
                      onChanged: (_) => setState(invalidate),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '目标报表口径'),
                  items: ['合并', '母公司']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          scope = v!;
                          invalidate();
                        }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: basis,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '数字披露版本（请对照原文）'),
                  items: ['原披露', '重述', '未注明']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          basis = v!;
                          reviewed = false;
                        }),
                ),
                const SizedBox(height: 16),
                Text('已选 ${sources.length} 段原文 · $count / 60000 字'),
                for (final source in widget.sources)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: sourceIds.contains(source.id),
                      title: Text('${source.title} · ${source.page}'),
                      subtitle: Text(
                        '${source.period} · ${source.unit} · ${source.text.length} 字',
                      ),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              if (v!) {
                                sourceIds.add(source.id);
                              } else {
                                sourceIds.remove(source.id);
                              }
                              invalidate();
                            }),
                    ),
                    children: [SelectableText(source.text)],
                  ),
                if (busy) const LinearProgressIndicator(),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(message),
                  ),
                if (batch != null) ...[
                  const Divider(),
                  Text(
                    batch!.candidates.isEmpty
                        ? '未找到可核验候选值，可补充资料或手动录入。'
                        : '选择你已核验的候选值',
                  ),
                  for (var i = 0; i < batch!.candidates.length; i++)
                    candidate(i),
                  if (batch!.missing.isNotEmpty)
                    Text('资料不足：\n${batch!.missing.join('\n')}'),
                  if (batch!.notes.isNotEmpty)
                    Text('口径说明：\n${batch!.notes.join('\n')}'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: reviewed,
                    onChanged: busy || chosen.isEmpty
                        ? null
                        : (v) => setState(() => reviewed = v!),
                    title: const Text('我已逐项核对原文、本期列、报告期间、合并/母公司口径和单位，确认保存所选数字'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        OutlinedButton(
          onPressed: busy || sources.isEmpty || count > 60000 ? null : generate,
          child: Text(batch == null ? '发送选定资料并提取' : '重新提取'),
        ),
        FilledButton(
          onPressed: busy || !reviewed || chosen.isEmpty ? null : accept,
          child: const Text('保存已核验财务记录'),
        ),
      ],
    );
  }

  Widget candidate(int i) {
    final c = batch!.candidates[i], problem = error(batch!.candidates[i]);
    final source = widget.sources
        .where((s) => s.id == c.proof.sourceId)
        .firstOrNull;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: chosen.contains(i),
              title: Text('${c.label}：${c.proof.rawValue} ${c.unit}'),
              subtitle: Text(
                '${c.start} 至 ${c.end} · ${c.scope}\n原文指标：${c.proof.label}',
              ),
              onChanged: busy || problem != null
                  ? null
                  : (v) => setState(() {
                      if (v!) {
                        chosen.add(i);
                      } else {
                        chosen.remove(i);
                      }
                      reviewed = false;
                    }),
            ),
            Text(
              problem == null ? '引用和原始数值检查通过；仍须确认指标含义及本期列' : '禁止保存：$problem',
            ),
            SelectableText(
              '[${c.proof.sourceId}] ${source?.page ?? '来源不存在'}\n「${c.proof.quote}」',
            ),
          ],
        ),
      ),
    );
  }
}

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
                            '${r.start} 至 ${r.end}\n${r.unit} · ${r.origin == 'aiConfirmed' ? 'AI候选已核验' : '人工录入'}',
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
