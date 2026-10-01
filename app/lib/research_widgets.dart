import 'package:flutter/material.dart';
import 'credentials.dart';
import 'domain.dart';
import 'forms.dart';
import 'research.dart';
import 'services.dart';

class CompanyLookupDialog extends StatefulWidget {
  const CompanyLookupDialog({super.key, required this.service});
  final MarketService service;
  @override
  State<CompanyLookupDialog> createState() => _CompanyLookupDialogState();
}

class _CompanyLookupDialogState extends State<CompanyLookupDialog> {
  final code = TextEditingController();
  String exchange = 'SH', error = '';
  bool busy = false;
  WatchCompany? company;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('添加真实自选公司'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                    initialValue: exchange,
                    decoration: const InputDecoration(labelText: '交易所'),
                    items: const [
                      DropdownMenuItem(value: 'SH', child: Text('上海 SH')),
                      DropdownMenuItem(value: 'SZ', child: Text('深圳 SZ')),
                      DropdownMenuItem(value: 'BJ', child: Text('北京 BJ'))
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                              exchange = v!;
                              company = null;
                            })),
                const SizedBox(height: 16),
                TextField(
                    controller: code,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '六位股票代码（保留前导零）'),
                    onChanged: (_) => setState(() => company = null)),
                const SizedBox(height: 16),
                if (company != null)
                  SelectableText(
                      '${company!.name} · ${company!.symbol}\n行业：${company!.industry}\n来源：东方财富\n获取：${company!.fetchedAt}\n${company!.source}'),
                if (error.isNotEmpty)
                  Text(error, style: const TextStyle(color: Colors.red)),
                if (busy)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator()),
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = '';
                          company = null;
                        });
                        try {
                          final found = await widget.service
                              .lookup(exchange, code.text.trim());
                          if (mounted) setState(() => company = found);
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('核验公司')),
            FilledButton(
                onPressed: busy || company == null
                    ? null
                    : () => Navigator.pop(context, company),
                child: const Text('加入自选'))
          ]);
}

class DeepSeekSettingsDialog extends StatefulWidget {
  const DeepSeekSettingsDialog(
      {super.key, required this.store, required this.service});
  final CredentialStore store;
  final DeepSeekService service;
  @override
  State<DeepSeekSettingsDialog> createState() => _DeepSeekSettingsDialogState();
}

class _DeepSeekSettingsDialogState extends State<DeepSeekSettingsDialog> {
  final key = TextEditingController(),
      model = TextEditingController(text: DeepSeekService.defaultModel);
  bool busy = true, ready = false;
  String message = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.store.read();
      if (mounted) {
        key.text = value.key;
        model.text = value.model;
        ready = true;
      }
    } catch (_) {
      message = '无法读取本机安全存储，请重试；未保存明文密钥';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  void dispose() {
    key.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await fn();
    } on ServiceFailure catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) setState(() => message = '安全存储操作失败，未保存明文密钥');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('DeepSeek 本地设置'),
          content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    '密钥由本机系统安全存储保存，不进入研究备份。生成草稿时仅发送所选公司的资料片段到 DeepSeek；模型服务按其账户计费。换设备后需重新设置密钥。'),
                const SizedBox(height: 20),
                TextField(
                    controller: key,
                    obscureText: true,
                    enabled: ready && !busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration:
                        const InputDecoration(labelText: 'DeepSeek API Key')),
                const SizedBox(height: 16),
                TextField(
                    controller: model,
                    enabled: ready && !busy,
                    decoration:
                        const InputDecoration(labelText: '模型 ID（可由连接检查获取）')),
                const SizedBox(height: 16),
                if (message.isNotEmpty) Text(message),
                if (busy) const CircularProgressIndicator(),
              ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('关闭')),
            TextButton(
                onPressed: busy
                    ? null
                    : () => action(() async {
                          await widget.store.clear();
                          key.clear();
                          if (mounted) {
                            setState(() {
                              ready = true;
                              message = '已删除本机密钥';
                            });
                          }
                        }),
                child: const Text('删除密钥')),
            OutlinedButton(
                onPressed: !ready || busy
                    ? null
                    : () => action(() async {
                          if (key.text.trim().isEmpty) {
                            throw ServiceFailure('请填写密钥');
                          }
                          final models =
                              await widget.service.models(key.text.trim());
                          if (mounted) {
                            setState(() =>
                                message = '连接成功，可用模型：${models.join('、')}');
                          }
                        }),
                child: const Text('检查连接')),
            FilledButton(
                onPressed: !ready || busy
                    ? null
                    : () => action(() async {
                          if (key.text.trim().isEmpty ||
                              !RegExp(r'^[a-zA-Z0-9_.-]{1,100}$')
                                  .hasMatch(model.text.trim())) {
                            throw ServiceFailure('请填写密钥和有效模型 ID');
                          }
                          await widget.store.write(AiSettings(
                              key: key.text.trim(), model: model.text.trim()));
                          if (mounted) setState(() => message = '已安全保存到本机');
                        }),
                child: const Text('保存设置'))
          ]);
}

class EvidenceDialog extends StatefulWidget {
  const EvidenceDialog(
      {super.key,
      required this.study,
      required this.sources,
      required this.financials,
      required this.addSource,
      required this.addFinancial,
      required this.specialIndustry});
  final Study study;
  final List<SourceExcerpt> sources;
  final List<FinancialRecord> financials;
  final Future<bool> Function(SourceExcerpt) addSource;
  final Future<bool> Function(FinancialRecord) addFinancial;
  final bool specialIndustry;
  @override
  State<EvidenceDialog> createState() => _EvidenceDialogState();
}

class _EvidenceDialogState extends State<EvidenceDialog> {
  late final sources = [...widget.sources], financials = [...widget.financials];
  String message = '';
  bool busy = false;
  Future<List<String>?> form(
          String title, List<InputField> fields, String note) =>
      showDialog<List<String>>(
          context: context,
          builder: (_) =>
              DataFormDialog(title: title, fields: fields, note: note));
  Future<void> source() async {
    final v = await form(
        '录入原始资料片段',
        [
          const InputField('报告或公告标题', ''),
          const InputField('原始 HTTPS 网址', ''),
          const InputField('报告期（例如 2025 年度）', ''),
          InputField('披露日期', dateToday(), date: true),
          const InputField('页码或章节位置', ''),
          const InputField('原文金额单位（元 / 万元 / 亿元；无金额填不适用）', ''),
          const InputField('逐字原文（最多 24000 字）', '', multiline: true)
        ],
        '请从原始财报或公告摘录。片段保存后保留稳定 ID；更正时新增片段，旧引用仍可追溯。');
    if (v == null || !mounted) return;
    setState(() => busy = true);
    try {
      final s = SourceExcerpt.fromJson({
        'id': newId(),
        'studyId': widget.study.id,
        'title': v[0],
        'url': v[1],
        'period': v[2],
        'disclosedAt': v[3],
        'page': v[4],
        'unit': v[5],
        'text': v[6]
      });
      final saved = await widget.addSource(s);
      if (mounted) {
        setState(() {
          if (saved) sources.add(s);
          message = saved ? '资料已保存' : '保存失败，片段未应用';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> financial() async {
    if (sources.isEmpty) {
      setState(() => message = '先录入带出处的原文，再据此核对财务字段');
      return;
    }
    final chosen = await showDialog<SourceExcerpt>(
        context: context,
        builder: (c) => SimpleDialog(title: const Text('选择财务来源片段'), children: [
              for (final s in sources)
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(c, s),
                    child: Text('${s.title} · ${s.period}\n[${s.id}]'))
            ]));
    if (chosen == null || !mounted) return;
    final v = await form(
        '核对财务记录',
        [
          const InputField('报告开始日期', '', date: true),
          const InputField('报告结束日期', '', date: true),
          InputField('披露日期', chosen.disclosedAt, date: true),
          InputField('金额单位（元 / 万元 / 亿元）', chosen.unit),
          const InputField('营业收入（缺失留空）', '', numeric: true, optional: true),
          const InputField('扣非净利润（允许负数，缺失留空）', '',
              numeric: true, signed: true, optional: true),
          const InputField('经营现金流（允许负数，缺失留空）', '',
              numeric: true, signed: true, optional: true),
          const InputField('期末现金（缺失留空）', '', numeric: true, optional: true),
          const InputField('期末有息负债（缺失留空）', '', numeric: true, optional: true),
        ],
        '来源：${chosen.title} · ${chosen.period} · ${chosen.page}。期间、披露日和单位须与原文一致。现金、债务是期末余额，其余为本报告期间累计额。请人工核对，不自动推断缺失数字。');
    if (v == null || !mounted) return;
    setState(() => busy = true);
    try {
      final f = FinancialRecord.fromJson({
        'id': newId(),
        'studyId': widget.study.id,
        'sourceId': chosen.id,
        'start': v[0],
        'end': v[1],
        'disclosedAt': v[2],
        'unit': v[3],
        'revenue': double.tryParse(v[4]),
        'adjustedProfit': double.tryParse(v[5]),
        'operatingCash': double.tryParse(v[6]),
        'cash': double.tryParse(v[7]),
        'debt': double.tryParse(v[8])
      });
      if (f.disclosedAt != chosen.disclosedAt || f.unit != chosen.unit) {
        throw const FormatException('披露日期与单位必须和来源片段一致');
      }
      if ([f.revenue, f.adjustedProfit, f.operatingCash, f.cash, f.debt]
          .every((v) => v == null)) {
        throw const FormatException('至少核对一个财务字段');
      }
      final saved = await widget.addFinancial(f);
      if (mounted) {
        setState(() {
          if (saved) financials.add(f);
          message = saved ? '财务记录已保存' : '保存失败，记录未应用';
        });
      }
    } catch (e) {
      if (mounted) setState(() => message = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('${widget.study.name} · 资料与财务'),
          content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    const Text('金额缺失显示“资料不足”。原文片段不代表已自动核验，公司名称、报告期间及数字仍需对照公告。'),
                    if (widget.specialIndustry)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              '金融行业：银行、保险、证券公司的债务与现金流口径特殊，不套用普通工业企业的现金覆盖判断；需补充资本充足率、资产质量等行业资料。')),
                    if (message.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(message)),
                    if (busy) const LinearProgressIndicator(),
                    for (final s in sources)
                      ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(s.title),
                          subtitle: Text(
                              '${s.period} · ${s.disclosedAt} · ${s.page} · ${s.unit}\n[${s.id}]'),
                          children: [SelectableText('${s.url}\n\n${s.text}')]),
                    const SizedBox(height: 16),
                    for (final f in financials)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SelectableText(
                              '${f.start} 至 ${f.end} · 单位：${f.unit}\n披露 ${f.disclosedAt} · 来源 [${f.sourceId}]\n营收 ${amount(f.revenue)} · 扣非净利 ${amount(f.adjustedProfit)}\n经营现金流 ${amount(f.operatingCash)} · 期末现金 ${amount(f.cash)} · 有息负债 ${amount(f.debt)}')),
                    if (sources.isEmpty) const Text('尚无原始资料片段'),
                  ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('关闭')),
            OutlinedButton(
                onPressed: busy ? null : financial,
                child: const Text('核对财务字段')),
            FilledButton(
                onPressed: busy ? null : source, child: const Text('添加原文片段'))
          ]);
}

String amount(double? value) =>
    value == null ? '资料不足' : value.toStringAsFixed(2);

class DraftDialog extends StatefulWidget {
  const DraftDialog(
      {super.key,
      required this.study,
      required this.sources,
      required this.store,
      required this.service});
  final Study study;
  final List<SourceExcerpt> sources;
  final CredentialStore store;
  final DeepSeekService service;
  @override
  State<DraftDialog> createState() => _DraftDialogState();
}

class _DraftDialogState extends State<DraftDialog> {
  ResearchDraft? draft;
  bool busy = false, reviewed = false;
  String message = '';
  @override
  Widget build(BuildContext context) {
    final errors = draft?.validate(widget.sources) ?? <String>[];
    return AlertDialog(
        title: Text('${widget.study.name} · AI 研究草稿'),
        content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(
                      '将 ${widget.sources.length} 段原文及其来源元数据发送到 DeepSeek，按模型账户计费。不会发送账户持仓或密钥到研究备份。草稿暂存于本次窗口，接受后才成为研究卡版本。'),
                  const SizedBox(height: 12),
                  if (widget.sources.isEmpty) const Text('资料不足：请先添加带出处的原文片段。'),
                  if (message.isNotEmpty) Text(message),
                  if (busy)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator()),
                  if (draft != null) ...[
                    Text(errors.isEmpty
                        ? '引用 ID 与逐字摘录检查通过；仍需人工检查引用是否支持判断。'
                        : '引用无效，禁止接受：\n${errors.join('\n')}'),
                    for (var i = 0; i < ResearchDraft.keys.length; i++) ...[
                      const SizedBox(height: 16),
                      Text(ResearchDraft.labels[i],
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      SelectableText(
                          draft!.render(ResearchDraft.keys[i]).isEmpty
                              ? '资料不足'
                              : draft!.render(ResearchDraft.keys[i])),
                    ],
                    const SizedBox(height: 16),
                    for (final s in widget.sources)
                      ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('[${s.id}] ${s.title}'),
                          subtitle: Text(
                              '${s.period} · ${s.disclosedAt} · ${s.page} · ${s.unit}'),
                          children: [SelectableText('${s.url}\n${s.text}')]),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: reviewed,
                        onChanged: errors.isEmpty
                            ? (v) => setState(() => reviewed = v!)
                            : null,
                        title: const Text('我已对照原文核验事实、数字和推测，确认保存此版本')),
                  ]
                ]))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('关闭')),
          OutlinedButton(
              onPressed: busy || widget.sources.isEmpty
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        message = '';
                        draft = null;
                        reviewed = false;
                      });
                      try {
                        final settings = await widget.store.read();
                        final result = await widget.service.draft(
                            key: settings.key,
                            model: settings.model,
                            company:
                                '${widget.study.name} ${widget.study.code}',
                            sources: widget.sources);
                        if (mounted) setState(() => draft = result);
                      } on ServiceFailure catch (e) {
                        if (mounted) setState(() => message = e.message);
                      } catch (_) {
                        if (mounted) {
                          setState(() => message = '本机密钥读取或草稿解析失败，未修改研究卡');
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              child: Text(draft == null ? '发送资料并生成' : '重新生成')),
          FilledButton(
              onPressed: busy || draft == null || !reviewed || errors.isNotEmpty
                  ? null
                  : () => Navigator.pop(context, draft),
              child: const Text('接受为研究卡版本'))
        ]);
  }
}

class FinancialComparisonDialog extends StatefulWidget {
  const FinancialComparisonDialog({super.key, required this.data});
  final WorkspaceData data;
  @override
  State<FinancialComparisonDialog> createState() =>
      _FinancialComparisonDialogState();
}

class _FinancialComparisonDialogState extends State<FinancialComparisonDialog> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    String group(FinancialRecord f) => '${f.start} 至 ${f.end} · ${f.unit}';
    final groups = widget.data.financials.map(group).toSet().toList()..sort();
    selected ??= groups.firstOrNull;
    final records =
        widget.data.financials.where((f) => group(f) == selected).toList();
    final studies = {for (final s in widget.data.studies) s.id: s};
    return AlertDialog(
        title: const Text('同期间财务比较'),
        content: SizedBox(
            width: 960,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text(
                      '仅展示报告起止日期和单位完全一致的记录。现金与债务是期末余额，金融行业不能套用普通企业指标。重复录入的版本分别显示，需核对来源。'),
                  const SizedBox(height: 16),
                  if (groups.isEmpty) const Text('尚无财务记录，请在研究卡中先核对字段。'),
                  if (groups.isNotEmpty)
                    DropdownButtonFormField<String>(
                        initialValue: selected,
                        isExpanded: true,
                        items: groups
                            .map((g) =>
                                DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (v) => setState(() => selected = v)),
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                          columns: const [
                            DataColumn(label: Text('公司 / 来源 ID')),
                            DataColumn(label: Text('营收')),
                            DataColumn(label: Text('扣非净利')),
                            DataColumn(label: Text('经营现金流')),
                            DataColumn(label: Text('现金')),
                            DataColumn(label: Text('有息负债'))
                          ],
                          rows: records
                              .map((f) => DataRow(cells: [
                                    DataCell(SelectableText(
                                        '${studies[f.studyId]!.name}\n[${f.sourceId}]')),
                                    ...[
                                      f.revenue,
                                      f.adjustedProfit,
                                      f.operatingCash,
                                      f.cash,
                                      f.debt
                                    ].map((v) => DataCell(Text(amount(v))))
                                  ]))
                              .toList())),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭'))
        ]);
  }
}
