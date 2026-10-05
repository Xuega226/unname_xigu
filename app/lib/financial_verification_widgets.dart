import 'dart:convert';

import 'package:flutter/material.dart';

import 'credentials.dart';
import 'domain.dart';
import 'financial_audit.dart';
import 'financial_extraction.dart';
import 'financial_verification.dart';
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
    this.records = const [],
    this.specialIndustry = false,
  });
  final Study study;
  final List<SourceExcerpt> sources;
  final List<ReportDocument> documents;
  final CredentialStore store;
  final DeepSeekService service;
  final Future<bool> Function(FinancialRecord) save;
  final List<FinancialRecord> records;
  final bool specialIndustry;
  @override
  State<FinancialExtractionDialog> createState() =>
      _FinancialExtractionDialogState();
}

class _FinancialExtractionDialogState extends State<FinancialExtractionDialog> {
  final start = TextEditingController(), end = TextEditingController();
  final form = GlobalKey<FormState>();
  final sourceIds = <String>{}, chosen = <int>{};
  final overrides = <int, String>{};
  String scope = '未注明', basis = '原披露', message = '', activity = '', model = '';
  String? reportKey, fingerprint;
  FinancialCandidateBatch? batch;
  FinancialReviewResult? review;
  FinancialRecord? pendingRecord;
  bool busy = false, saving = false, closed = false;
  int generation = 0;
  List<SourceExcerpt> get sources =>
      widget.sources.where((s) => sourceIds.contains(s.id)).toList();
  List<SourceExcerpt> get reportSources =>
      widget.sources.where((s) => financialReportKey(s) == reportKey).toList();
  ReportDocument? get document => widget.documents
      .where((d) => d.id == sources.firstOrNull?.documentId)
      .firstOrNull;
  bool active(int token) => mounted && !closed && generation == token;
  String currentFingerprint() => financialInputFingerprint(
    studyId: widget.study.id,
    sources: sources,
    start: start.text.trim(),
    end: end.text.trim(),
    scope: scope,
    basis: basis,
  );
  @override
  void initState() {
    super.initState();
    if (widget.sources.isNotEmpty) {
      selectReport(financialReportKey(widget.sources.first));
    }
    loadModel();
  }

  Future<void> loadModel() async {
    try {
      final settings = await widget.store.read();
      if (mounted && !closed && !busy && batch == null) {
        setState(() => model = settings.model);
      }
    } catch (_) {
      if (mounted) setState(() => message = '本机配置读取失败，请在设置中检查');
    }
  }

  @override
  void dispose() {
    generation++;
    start.dispose();
    end.dispose();
    super.dispose();
  }

  void invalidate() {
    generation++;
    batch = null;
    review = null;
    fingerprint = null;
    pendingRecord = null;
    chosen.clear();
    overrides.clear();
  }

  void selectReport(String key) {
    invalidate();
    reportKey = key;
    sourceIds.clear();
    sourceIds.addAll(reportSources.map((s) => s.id));
    start.clear();
    end.clear();
    scope = '未注明';
    basis = '未注明';
    final doc = document;
    if (doc != null) {
      start.text = doc.start;
      end.text = doc.end;
      scope = doc.preparation?.scope ?? '未注明';
      basis =
          doc.origin?.isRevision == true ||
              RegExp(r'修订|更正|重述').hasMatch(doc.title)
          ? '未注明'
          : '原披露';
    }
    if (scope == '未注明') {
      final text = sources.map((s) => s.text).join('\n');
      final detected = ['合并', '母公司']
          .where((s) => RegExp('$s(?:财务报表|资产负债表|利润表|现金流量表)').hasMatch(text))
          .toList();
      if (detected.length == 1) scope = detected.single;
    }
  }

  String? problem(FinancialCandidate c) => financialCandidateProblem(
    c,
    studyId: widget.study.id,
    sources: sources,
    documents: widget.documents,
    start: start.text.trim(),
    end: end.text.trim(),
    scope: scope,
  );
  void stop() {
    if (saving) return;
    setState(() {
      invalidate();
      busy = false;
      activity = '未完成';
      message = '已停止等待；旧数据保持，已发出的请求可能已计费。';
    });
  }

  Future<void> generate() async {
    if (busy || !form.currentState!.validate()) return;
    invalidate();
    final token = ++generation;
    final inputSources = List<SourceExcerpt>.from(sources),
        inputStart = start.text.trim(),
        inputEnd = end.text.trim(),
        inputScope = scope;
    final inputFingerprint = currentFingerprint();
    setState(() {
      busy = true;
      message = '';
      activity = '提取中';
    });
    try {
      final settings = await widget.store.read();
      if (!active(token)) return;
      setState(() => model = settings.model);
      final extracted = await widget.service.extractFinancials(
        key: settings.key,
        model: settings.model,
        company: '${widget.study.name} ${widget.study.code}',
        sources: inputSources,
        start: inputStart,
        end: inputEnd,
        scope: inputScope,
      );
      if (!active(token)) return;
      setState(() {
        batch = extracted;
        activity = '程序检查';
      });
      if (!extracted.candidates.any((c) => problem(c) == null)) {
        setState(() {
          activity = '资料不足或需要处理';
          message = '没有可用候选，未发送复核请求。可补资料或转人工录入。';
        });
        return;
      }
      setState(() => activity = 'AI 复核中');
      final checked = await widget.service.reviewFinancials(
        key: settings.key,
        model: settings.model,
        company: '${widget.study.name} ${widget.study.code}',
        sources: inputSources,
        batch: extracted,
        start: inputStart,
        end: inputEnd,
        scope: inputScope,
        basis: basis,
      );
      if (!active(token) || currentFingerprint() != inputFingerprint) return;
      setState(() {
        review = checked;
        fingerprint = inputFingerprint;
        chosen.addAll(
          defaultFinancialSelection(
            extracted,
            checked,
            problem,
            sources,
            specialIndustry: widget.specialIndustry,
          ),
        );
        activity = chosen.isEmpty ? '需要处理' : '待确认';
        if (chosen.isEmpty) message = '正常候选未形成一致集合，请检查异常、单位或版本，必要时转人工录入。';
      });
    } on ServiceFailure catch (e) {
      if (active(token)) {
        setState(() {
          message = e.message;
          activity = '未完成';
        });
      }
    } catch (_) {
      if (active(token)) {
        setState(() {
          message = '配置读取或模型结果处理失败，未保存记录';
          activity = '未完成';
        });
      }
    } finally {
      if (active(token)) setState(() => busy = false);
    }
  }

  String status(int i) {
    final c = batch!.candidates[i];
    if (problem(c) != null) return '待处理';
    if (widget.specialIndustry &&
        ['cash', 'debt', 'operatingCash'].contains(c.metric)) {
      return '不适用';
    }
    final verdict = review?.decisions[i].verdict;
    if (verdict == 'notApplicable') return '不适用';
    if (verdict == 'pass' &&
        batch!.candidates.where((v) => v.metric == c.metric).length == 1) {
      return '可确认';
    }
    return verdict == 'unknown' || verdict == null ? '资料不足' : '待处理';
  }

  int summaryCount(String category) => FinancialRecord.metrics.where((metric) {
    final indices = batch!.candidates
        .asMap()
        .entries
        .where((e) => e.value.metric == metric)
        .map((e) => e.key)
        .toList();
    if (indices.isEmpty) return category == '资料不足';
    if (indices.length > 1) return category == '待处理';
    return status(indices.single) == category;
  }).length;

  Future<void> handleException(int i) async {
    if (problem(batch!.candidates[i]) != null || review == null || busy) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('人工处理语义例外'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请查看原文并记录选择本期列、指标含义或口径的依据；程序硬错误仍不能绕过。'),
              TextField(
                controller: controller,
                maxLength: 2000,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '处理依据'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(c, controller.text.trim());
              }
            },
            child: const Text('记录依据并纳入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !mounted) return;
    setState(() {
      overrides[i] = reason;
      selectCandidate(i);
    });
  }

  void selectCandidate(int i) {
    final c = batch!.candidates[i];
    chosen.removeWhere((n) => batch!.candidates[n].metric == c.metric);
    chosen.add(i);
    pendingRecord = null;
  }

  Future<void> accept() async {
    if (busy ||
        batch == null ||
        review == null ||
        chosen.isEmpty ||
        fingerprint != currentFingerprint()) {
      return;
    }
    setState(() {
      busy = true;
      saving = true;
      message = '';
      activity = '保存中';
    });
    try {
      final indices = chosen.toList()..sort();
      final selected = indices.map((i) => batch!.candidates[i]).toList();
      if (selected.any((c) => problem(c) != null)) {
        throw const FormatException('所选来源或期间已失效');
      }
      final reportIds = selected
          .map(
            (c) => financialReportKey(
              sources.singleWhere((s) => s.id == c.proof.sourceId),
            ),
          )
          .toSet();
      if (reportIds.length != 1) {
        throw const FormatException('请选择同一份报告，不能合并不同版本');
      }
      if (indices.any(
        (i) =>
            review!.decisions[i].verdict != 'pass' && !overrides.containsKey(i),
      )) {
        throw const FormatException('请处理语义例外后再确认');
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
      final audit = FinancialAudit.fromJson({
        'version': 1,
        'method': 'reportConfirmed',
        'model': model,
        'extractionVersion': financialExtractionVersion,
        'reviewVersion': financialReviewVersion,
        'checkVersion': financialCheckVersion,
        'fingerprint': fingerprint,
        'acceptedAt': DateTime.now().toUtc().toIso8601String(),
        'sources': sources.map((s) => s.toJson()).toList(),
        'candidates': batch!.candidates.map((c) => c.toJson()).toList(),
        'reviews': review!.decisions.map((r) => r.toJson()).toList(),
        'selected': indices,
        'overrides': [
          for (final i in indices)
            if (overrides.containsKey(i)) {'index': i, 'reason': overrides[i]},
        ],
        'usage': [
          if (document?.preparation?.method == 'ai')
            {
              'stage': 'preparation',
              if (financialUsage(document!.preparation!.usage) == null)
                'unknown': true,
              ...?financialUsage(document!.preparation!.usage),
            },
          {
            'stage': 'extraction',
            if (batch!.usage == null) 'unknown': true,
            ...?batch!.usage,
          },
          {
            'stage': 'review',
            if (review!.usage == null) 'unknown': true,
            ...?review!.usage,
          },
        ],
        if (document?.preparation != null)
          'preparation': document!.preparation!.toJson(),
      });
      pendingRecord ??= FinancialRecord.fromJson({
        ...record.toJson(),
        'audit': audit.toJson(),
      });
      if (widget.records.any(
        (r) => sameFinancialSubmission(r, pendingRecord!),
      )) {
        setState(() => message = '相同字段与证据已保存，无需重复提交');
        return;
      }
      final saved = await widget.save(pendingRecord!);
      if (!mounted) return;
      if (saved) {
        Navigator.pop(context, pendingRecord);
      } else {
        setState(() => message = '保存失败，旧记录保持；可重试，本批次不会重复写入。');
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => message = e.message.toString());
    } catch (_) {
      if (mounted) setState(() => message = '保存失败，旧记录保持，请重试');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          saving = false;
          activity = '待确认';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = sources.fold<int>(0, (n, s) => n + s.text.length);
    final reportKeys = widget.sources.map(financialReportKey).toSet().toList();
    return PopScope(
      canPop: !saving,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          closed = true;
          generation++;
        }
      },
      child: AlertDialog(
        title: Text('${widget.study.name} · AI 预核验'),
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
                    '仅发送本份报告的选定原文与出处，提取和复核最多两次请求，按 DeepSeek 账户计费；确认摘要后才保存。',
                  ),
                  Text('当前模型：${model.isEmpty ? '配置读取中' : model}'),
                  const SizedBox(height: 12),
                  if (reportKeys.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey('financial-report-$reportKey'),
                      initialValue: reportKey,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '选择报告（版本分别处理）',
                      ),
                      items: reportKeys.map((k) {
                        final s = widget.sources.firstWhere(
                          (s) => financialReportKey(s) == k,
                        );
                        return DropdownMenuItem(
                          value: k,
                          child: Text(
                            '${s.title} · ${s.period} · 披露 ${s.disclosedAt}',
                          ),
                        );
                      }).toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() => selectReport(v!)),
                    ),
                  for (final entry in [('报告开始日期', start), ('报告结束日期', end)])
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: entry.$2,
                        enabled: !busy,
                        decoration: InputDecoration(labelText: entry.$1),
                        validator: (v) =>
                            !validDate(v ?? '') ? '请填写有效日期 YYYY-MM-DD' : null,
                        onChanged: (_) => setState(invalidate),
                      ),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('scope-$scope'),
                    initialValue: scope,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '目标报表口径'),
                    items: ['未注明', '合并', '母公司']
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
                    key: ValueKey('basis-$basis'),
                    initialValue: basis,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '数字披露版本'),
                    items: ['原披露', '重述', '未注明']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            basis = v!;
                            invalidate();
                          }),
                  ),
                  if (document?.origin?.isRevision == true)
                    const Text('修订公告：请检查更正范围，明确原披露或重述口径。'),
                  if (widget.specialIndustry)
                    const Text('特殊行业：现金、债务和现金流需行业口径，相关项不默认纳入。'),
                  Text('已选 ${sources.length} 段原文 · $count / 60000 字'),
                  ExpansionTile(
                    title: const Text('发送范围与原文（可调整）'),
                    children: [
                      for (final s in reportSources)
                        ExpansionTile(
                          title: CheckboxListTile(
                            value: sourceIds.contains(s.id),
                            title: Text('${s.page} · ${s.unit}'),
                            onChanged: busy
                                ? null
                                : (v) => setState(() {
                                    if (v!) {
                                      sourceIds.add(s.id);
                                    } else {
                                      sourceIds.remove(s.id);
                                    }
                                    invalidate();
                                  }),
                          ),
                          children: [SelectableText(s.text)],
                        ),
                    ],
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (activity.isNotEmpty) Text(activity),
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(message),
                    ),
                  if (batch != null) ...[
                    const Divider(),
                    Text(
                      '核验摘要：可确认 ${summaryCount('可确认')} · 待处理 ${summaryCount('待处理')} · 资料不足 ${summaryCount('资料不足')} · 不适用 ${summaryCount('不适用')}',
                    ),
                    for (var i = 0; i < batch!.candidates.length; i++)
                      candidate(i),
                    for (final metric in FinancialRecord.metrics.where(
                      (m) => !batch!.candidates.any((c) => c.metric == m),
                    ))
                      Text(
                        '${FinancialRecord.labels[FinancialRecord.metrics.indexOf(metric)]}：资料不足',
                      ),
                    if (batch!.missing.isNotEmpty)
                      Text('不足：${batch!.missing.join('；')}'),
                    if (batch!.notes.isNotEmpty)
                      Text('说明：${batch!.notes.join('；')}'),
                    Text(
                      '本次将保存 ${chosen.length} 项，其余排除或缺失。确认表示采纳摘要，无需声称已逐项人工对照原页。',
                    ),
                    Text(
                      '实际消耗：提取 ${batch!.usage == null ? '未知' : jsonEncode(batch!.usage)}；复核 ${review?.usage == null ? '未知' : jsonEncode(review!.usage)}',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving
                ? null
                : () {
                    closed = true;
                    generation++;
                    Navigator.pop(context);
                  },
            child: const Text('关闭'),
          ),
          if (busy && !saving)
            TextButton(
              key: const ValueKey('financial-stop'),
              onPressed: stop,
              child: const Text('停止等待'),
            ),
          OutlinedButton(
            key: const ValueKey('financial-start'),
            onPressed: busy || sources.isEmpty || count > 60000
                ? null
                : generate,
            child: const Text('发送范围并预核验'),
          ),
          FilledButton(
            key: const ValueKey('financial-save'),
            onPressed:
                busy ||
                    review == null ||
                    chosen.isEmpty ||
                    fingerprint != currentFingerprint()
                ? null
                : accept,
            child: const Text('确认并保存可采纳字段'),
          ),
        ],
      ),
    );
  }

  Widget candidate(int i) {
    final c = batch!.candidates[i], hard = problem(batch!.candidates[i]);
    final decision = review?.decisions[i];
    return Card(
      key: ValueKey('financial-candidate-$i'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.label}：${c.proof.rawValue} ${c.unit} · ${status(i)}'),
            Text(chosen.contains(i) ? '已纳入本次确认' : '未纳入本次确认'),
            if (hard != null) Text('禁止保存：$hard'),
            if (decision != null) Text('AI 复核：${decision.reason}'),
            if (overrides.containsKey(i)) Text('人工处理：${overrides[i]}'),
            ExpansionTile(
              title: const Text('展开指标、原文与检查依据'),
              children: [
                SelectableText(
                  '${c.proof.label} · ${c.start} 至 ${c.end} · ${c.scope}\n[${c.proof.sourceId}] ${sources.where((s) => s.id == c.proof.sourceId).firstOrNull?.page ?? '来源不存在'}\n「${c.proof.quote}」\n程序：${hard ?? '来源与原始数字检查通过'}\n复核依据：${decision?.quote ?? '尚未完成'}',
                ),
              ],
            ),
            if (review != null && hard == null)
              Wrap(
                spacing: 8,
                children: [
                  if (chosen.contains(i))
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              chosen.remove(i);
                              pendingRecord = null;
                            }),
                      child: const Text('排除此项'),
                    )
                  else if (decision?.verdict == 'pass' &&
                      !(widget.specialIndustry &&
                          ['cash', 'debt', 'operatingCash'].contains(c.metric)))
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => selectCandidate(i)),
                      child: const Text('纳入此项'),
                    ),
                  if (!chosen.contains(i))
                    TextButton(
                      onPressed: busy ? null : () => handleException(i),
                      child: const Text('人工处理此项'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
