import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain.dart';
import 'storage.dart';
import 'forms.dart';
import 'research.dart';
import 'services.dart';
import 'credentials.dart';
import 'research_widgets.dart';
import 'report_import.dart';
import 'report_fetch.dart';
import 'financial_widgets.dart';
import 'review_widgets.dart';

import 'dart:io';

import 'broker_import.dart';
import 'broker_sync.dart';
import 'broker_widgets.dart';
import 'portfolio_import_info.dart';
import 'portfolio_history.dart';
import 'portfolio_history_widgets.dart';
import 'risk_charts.dart';
import 'quant_widgets.dart';
import 'data_foundation.dart';
import 'data_foundation_widgets.dart';

void main() => runApp(const LianghuaApp());

const ink = Color(0xFF152D35);
const teal = Color(0xFF117D75);
String money(double v) => '¥ ${v.toStringAsFixed(2)}';
String percentage(double? v) =>
    v == null ? '无法计算' : '${(v * 100).toStringAsFixed(1)}%';

class LianghuaApp extends StatelessWidget {
  const LianghuaApp({
    super.key,
    this.store,
    this.fontFamily,
    this.market,
    this.ai,
    this.credentials,
    this.pdfImporter,
    this.reportFiles,
    this.reportFetcher,
    this.brokerSettings,
    this.brokerImporter,
    this.historyService,
  });
  final WorkspaceStore? store;
  final MarketService? market;
  final DeepSeekService? ai;
  final CredentialStore? credentials;
  final PdfImportService? pdfImporter;
  final ReportFileStore? reportFiles;
  final ReportFetchService? reportFetcher;
  final BrokerSettingsStore? brokerSettings;
  final BrokerImportService? brokerImporter;
  final MarketHistoryService? historyService;
  final String? fontFamily;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '未名溪谷',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    theme: ThemeData(
      fontFamily: fontFamily,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF3F6F5),
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        primary: teal,
        surface: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w700, color: ink),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    ),
    home: WorkspaceScreen(
      store: store,
      market: market,
      ai: ai,
      credentials: credentials,
      pdfImporter: pdfImporter,
      reportFiles: reportFiles,
      reportFetcher: reportFetcher,
      brokerSettings: brokerSettings,
      brokerImporter: brokerImporter,
      historyService: historyService,
    ),
  );
}

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    this.store,
    this.market,
    this.ai,
    this.credentials,
    this.pdfImporter,
    this.reportFiles,
    this.reportFetcher,
    this.brokerSettings,
    this.brokerImporter,
    this.historyService,
  });
  final WorkspaceStore? store;
  final MarketService? market;
  final DeepSeekService? ai;
  final CredentialStore? credentials;
  final PdfImportService? pdfImporter;
  final ReportFileStore? reportFiles;
  final ReportFetchService? reportFetcher;
  final BrokerSettingsStore? brokerSettings;
  final BrokerImportService? brokerImporter;
  final MarketHistoryService? historyService;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with WidgetsBindingObserver {
  WorkspaceStore? _store;
  WorkspaceData? _data;
  String? _error;
  bool _saving = false;
  bool _networkBusy = false;
  bool _foreground = true, _brokerDialogBusy = false;
  BrokerFileSync? _brokerSync;
  late final _market = widget.market ?? MarketService();
  late final _ai = widget.ai ?? DeepSeekService();
  late final _credentials = widget.credentials ?? SecureCredentialStore();
  late final _pdfImporter = widget.pdfImporter ?? PdfImportService();
  late final _reportFetcher = widget.reportFetcher ?? ReportFetchService();
  late final _reportFiles = widget.reportFiles == null
      ? LocalReportFileStore.create()
      : Future<ReportFileStore>.value(widget.reportFiles);
  int _page = 0;
  String? _focusedStudyId;
  final _contentScroll = ScrollController();
  double _stress = .3;
  final titles = const ['研究总览', '公司研究', '账户风控', '复查日志', '量化研究'];
  final icons = const [
    Icons.space_dashboard_outlined,
    Icons.business_outlined,
    Icons.shield_outlined,
    Icons.edit_note_outlined,
    Icons.calculate_outlined,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
  }

  void _brokerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _brokerSync?.dispose();
    _contentScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _store = widget.store ?? await LocalWorkspaceStore.create();
      final saved = await _store!.load();
      final data = saved ?? WorkspaceData.demo();
      if (saved == null) await _store!.save(data);
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
        if (_brokerSync == null &&
            (Platform.isWindows || widget.brokerSettings != null)) {
          _brokerSync = BrokerFileSync(
            settingsStore:
                widget.brokerSettings ??
                (widget.store == null
                    ? LocalBrokerSettingsStore()
                    : MemoryBrokerSettingsStore()),
            currentData: () => _data,
            canApply: () =>
                mounted &&
                _foreground &&
                !_saving &&
                !_networkBusy &&
                !_brokerDialogBusy &&
                (ModalRoute.of(context)?.isCurrent ?? false),
            save: (next) => _save(next, portfolioImporting: true),
          )..addListener(_brokerChanged);
          await _brokerSync!.initialize();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> _save(
    WorkspaceData value, {
    bool portfolioImporting = false,
  }) async {
    if (_saving) return false;
    final previous = _data;
    if (!portfolioImporting &&
        previous?.portfolioImport != null &&
        value.portfolioImport?.digest == previous!.portfolioImport!.digest &&
        portfolioFingerprint(previous) != portfolioFingerprint(value)) {
      value = value.copyWith(
        portfolioImport: value.portfolioImport!.markModified(),
      );
    }
    setState(() => _saving = true);
    try {
      WorkspaceData.decode(value.encode());
      await _store!.save(value);
      if (mounted) {
        setState(() => _data = value);
        _message('已保存到本机');
      }
      if (_brokerSync?.settings != null &&
          (value.portfolioImport == null ||
              value.portfolioImport!.modified ||
              value.portfolioImport!.identity !=
                  _brokerSync!.settings!.identity)) {
        try {
          await _brokerSync!.stop();
        } catch (_) {
          _message('自动读取已暂停，设置保存失败，请重新核对文件绑定');
        }
      }
      return true;
    } catch (e) {
      _message('保存失败，当前修改未应用：$e');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  void _navigate(int page, {String? studyId}) {
    setState(() {
      _page = page;
      _focusedStudyId = studyId;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _contentScroll.hasClients) _contentScroll.jumpTo(0);
    });
  }

  Future<bool> _saveQuant(WorkspaceData next) async {
    if (_data == null) return false;
    return _save(_data!.copyWith(quant: next.quant));
  }

  Future<bool> _saveDataFoundation(WorkspaceData next) async {
    if (_data == null) return false;
    return _save(
      _data!.copyWith(
        priceHistory: next.priceHistory,
        funding: next.funding,
        deposits: next.funding?.deposits ?? _data!.deposits,
        withdrawals: next.funding?.withdrawals ?? _data!.withdrawals,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: SizedBox(
            width: 520,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 16),
                  const Text('本地数据未能读取', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 12),
                  Text('原文件已保留，请勿用示例覆盖。\n$_error'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _load, child: const Text('重试')),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (_data == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final data = _data!;
    final desktop = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '未名溪谷',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_saving || _networkBusy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          PopupMenuButton<String>(
            enabled: !_saving && !_networkBusy,
            tooltip: '数据与设置',
            onSelected: _action,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('账户设置')),
              PopupMenuItem(value: 'deepseek', child: Text('DeepSeek 本地设置')),
              PopupMenuItem(value: 'export', child: Text('导出备份')),
              PopupMenuItem(value: 'import', child: Text('导入备份')),
              PopupMenuItem(value: 'empty', child: Text('新建空白工作区')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: desktop
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (i) => _navigate(i),
              destinations: List.generate(
                titles.length,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: titles[i],
                ),
              ),
            ),
      body: Row(
        children: [
          if (desktop)
            NavigationRail(
              backgroundColor: Colors.white,
              selectedIndex: _page,
              extended: MediaQuery.sizeOf(context).width >= 1100,
              labelType: MediaQuery.sizeOf(context).width >= 1100
                  ? null
                  : NavigationRailLabelType.all,
              onDestinationSelected: (i) => _navigate(i),
              destinations: List.generate(
                titles.length,
                (i) => NavigationRailDestination(
                  icon: Icon(icons[i]),
                  label: Text(titles[i]),
                ),
              ),
            ),
          Expanded(
            child: AbsorbPointer(
              absorbing: _saving || _networkBusy,
              child: ListView(
                controller: _contentScroll,
                padding: EdgeInsets.all(desktop ? 28 : 16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                titles[_page],
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              Chip(
                                label: Text(
                                  data.isDemo
                                      ? '虚构模拟数据'
                                      : data.portfolioImport == null
                                      ? '手动录入 · 未核验'
                                      : '含持仓文件导入 · 研究待核验',
                                ),
                                avatar: const Icon(
                                  Icons.info_outline,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '计划持有约一年 · 可以延长 · 亏损偏好 ${percentage(data.lossBudget)}',
                            style: const TextStyle(color: Color(0xFF586E75)),
                          ),
                          const SizedBox(height: 20),
                          if (_page == 0) ..._overview(data),
                          if (_page == 1) ..._studies(data),
                          if (_page == 2) ..._risk(data),
                          if (_page == 3) ..._reviews(data),
                          if (_page == 4) ..._quant(data),
                          const SizedBox(height: 24),
                          const Text(
                            'v0.7.1 · 可配置因子规则与评分 · 历史行情与资金流水 · 单账户风控',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF647A80),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _overview(WorkspaceData d) => [
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '先看风险，再做判断',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '把依据写下来，把反面证据留下来。\n一年后复查投资假设，持续持有也需要新的依据。',
            style: TextStyle(color: Color(0xFFD1E1E3), height: 1.7),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () => setState(() => _page = 1),
            child: const Text('开始研究公司'),
          ),
        ],
      ),
    ),
    const SizedBox(height: 18),
    _metrics(d),
    const SizedBox(height: 18),
    _panel('这一轮要完成什么', [
      _line(
        Icons.fact_check_outlined,
        '补齐公司资料',
        '${d.studies.length} 张研究卡；关键数字需要原始来源、单位与披露日期。',
      ),
      _line(
        Icons.balance_outlined,
        '检查账户风险',
        '${d.holdings.length} 项持仓；先看集中程度，再做指定情景的压力测试。',
      ),
      _line(
        Icons.history_outlined,
        '记录复查依据',
        '${d.reviews.length} 条记录；保留原始判断，不用新结论覆盖旧记录。',
      ),
    ]),
    const SizedBox(height: 16),
    _notice(
      d.isDemo
          ? '这里的企业、代码和价格全部是虚构示例。可以先体验功能，再从菜单新建空白工作区。'
          : d.portfolioImport == null
          ? '当前数据来自手动录入，尚未核验。请保持所有持仓价格的估值日期一致。'
          : '持仓来自文件导入，请核对券商与快照时间；研究资料仍需人工核验。',
    ),
  ];

  Widget _metrics(WorkspaceData d) => LayoutBuilder(
    builder: (_, c) {
      final width = c.maxWidth >= 640
          ? (c.maxWidth - 24) / 3
          : c.maxWidth >= 320
          ? (c.maxWidth - 12) / 2
          : c.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _metric(
            c.maxWidth >= 640 ? width : c.maxWidth,
            '账户资产',
            money(d.assets),
            '现金 + 持仓市值',
          ),
          _metric(width, '股票总仓位', percentage(d.stockWeight), '占整个账户资产'),
          _metric(
            width,
            '相对本金盈亏',
            percentage(d.profitRate),
            '净投入本金 ${money(d.principal)}',
          ),
        ],
      );
    },
  );
  Widget _metric(double width, String label, String value, String detail) =>
      SizedBox(
        width: width,
        child: _panel(label, [
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: teal,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: const TextStyle(fontSize: 12, color: Color(0xFF647A80)),
          ),
        ]),
      );
  Widget _panel(String title, List<Widget> children, {Widget? trailing}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E8E6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      );
  Widget _line(IconData icon, String title, String detail) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: teal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(detail),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _notice(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFE5F0ED),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text),
  );

  List<Widget> _studies(WorkspaceData d) => [
    if (_focusedStudyId != null)
      TextButton(onPressed: () => _navigate(1), child: const Text('返回全部公司研究')),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _studyDialog(),
          icon: const Icon(Icons.add),
          label: const Text('新增研究卡'),
        ),
        OutlinedButton.icon(
          onPressed: _copyPrompt,
          icon: const Icon(Icons.copy),
          label: const Text('复制 AI 分析模板'),
        ),
      ],
    ),
    const SizedBox(height: 16),
    if (_focusedStudyId == null) _watchlist(d),
    const SizedBox(height: 12),
    OutlinedButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => FinancialComparisonDialog(data: d),
      ),
      child: const Text('同期间财务比较'),
    ),
    const SizedBox(height: 16),
    if (d.studies.isEmpty) _notice('还没有研究卡。先添加一家公司，并记录你为什么想研究它。'),
    for (final s in d.studies.where(
      (study) => _focusedStudyId == null || study.id == _focusedStudyId,
    )) ...[
      _panel(
        '${s.name} · ${s.code}',
        [
          Text(
            s.source.isEmpty ? '资料不足 · 尚无原始来源' : '已录入来源 · 待人工核验',
            style: const TextStyle(color: teal),
          ),
          const SizedBox(height: 12),
          _studySection('主营业务与财务事实', s.business),
          _studySection('一年投资假设与验证指标', s.thesis),
          _studySection('反面证据与缺失信息', s.counterEvidence),
          _studySection('需要重新评估的条件', s.reviewCondition),
          _studySection('来源、报告期、披露日期与单位', s.source),
          Text(
            '录入更新：${s.updatedAt}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          Text(
            '${reviewDueLabel(s)} · ${s.reviewTasks.where((t) => t.status == '待验证').length} 项待验证',
            style: const TextStyle(color: teal),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _evidence(s),
                child: Text(
                  '资料与财务（${d.sources.where((e) => e.studyId == s.id).length} 段原文）',
                ),
              ),
              FilledButton.tonal(
                onPressed: d.isDemo ? null : () => _draft(s),
                child: const Text('生成 AI 草稿'),
              ),
              OutlinedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => FinancialTrendDialog(
                    study: s,
                    records: d.financials
                        .where((f) => f.studyId == s.id)
                        .toList(),
                  ),
                ),
                child: const Text('多年度财务变化'),
              ),
              OutlinedButton(
                onPressed: () => _reviewPlan(s),
                child: const Text('复查计划与清单'),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => StudyHistoryDialog(
                    study: s,
                    versions: d.studyVersions
                        .where((v) => v.study.id == s.id)
                        .toList(),
                  ),
                ),
                child: const Text('研究版本对照'),
              ),
            ],
          ),
        ],
        trailing: IconButton(
          tooltip: '编辑研究卡',
          onPressed: () => _studyDialog(s),
          icon: const Icon(Icons.edit_outlined),
        ),
      ),
      const SizedBox(height: 14),
    ],
  ];
  Widget _studySection(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF647A80)),
        ),
        const SizedBox(height: 4),
        SelectableText(value.trim().isEmpty ? '未录入，无法判断' : value),
      ],
    ),
  );

  List<Widget> _risk(WorkspaceData d) => [
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _holdingDialog(),
          icon: const Icon(Icons.add),
          label: const Text('新增持仓'),
        ),
        OutlinedButton(onPressed: _accountDialog, child: const Text('账户设置')),
        OutlinedButton.icon(
          onPressed: d.isDemo ? null : _brokerImport,
          icon: const Icon(Icons.account_balance_outlined),
          label: const Text('导入券商持仓'),
        ),
        if (!d.isDemo)
          OutlinedButton(
            onPressed: _applyQuotes,
            child: const Text('应用同日行情到持仓'),
          ),
      ],
    ),
    const SizedBox(height: 16),
    _panel('券商持仓导入', [
      if (d.isDemo) const Text('真实持仓请先从菜单新建空白工作区。'),
      if (d.portfolioImport == null)
        const Text('可导入完整 CSV / 标准 JSON。账户直连尚待选定券商。')
      else ...[
        Text(
          '${d.portfolioImport!.broker} · ${d.portfolioImport!.accountAlias} · ${d.portfolioImport!.format.toUpperCase()} 文件',
        ),
        Text('快照时间：${brokerTimeLabel(d.portfolioImport!.capturedAt)}'),
        Text('上次导入：${brokerTimeLabel(d.portfolioImport!.importedAt)}'),
        if (d.portfolioImport!.modified) const Text('导入后已人工修改或应用行情，自动读取已关闭。'),
      ],
      if (_brokerSync != null) ...[
        const SizedBox(height: 8),
        Text(_brokerSync!.status),
        if (_brokerSync!.settings != null)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _brokerSync!.check,
                child: const Text('检查文件更新'),
              ),
              TextButton(
                onPressed: _stopBrokerSync,
                child: const Text('关闭自动读取'),
              ),
            ],
          ),
      ],
    ]),
    const SizedBox(height: 16),
    _metrics(d),
    const SizedBox(height: 16),
    _notice(
      d.profitRate == null
          ? '净投入本金不大于零，无法计算相对本金盈亏。请先核对入金与出金记录。'
          : d.profitRate! <= -d.lossBudget
          ? '当前相对本金亏损已达到或超过你的偏好值，请复查资料、仓位与资金需求。此提示不自动下单。'
          : '亏损偏好 ${percentage(d.lossBudget)} 是提醒参数，实际亏损可能超过它。高点回撤：历史不足，无法计算。',
    ),
    const SizedBox(height: 16),
    RiskCharts(
      data: d,
      stress: _stress,
      onStressChanged: (value) => setState(() => _stress = value),
    ),
    const SizedBox(height: 16),
    _panel('持仓与行业集中度', [
      Text('估值日期：${d.priceDate} · 全部价格需对应同一日期'),
      const SizedBox(height: 12),
      if (d.holdings.isEmpty) const Text('尚无持仓。'),
      for (final h in d.holdings)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${h.name} · ${h.code}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${h.industry} · ${h.quantity.toStringAsFixed(0)} 股 × ${h.price.toStringAsFixed(2)} 元',
                    ),
                    Text(
                      '${money(h.marketValue)}  /  ${percentage(d.weight(h))}',
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '编辑持仓',
                onPressed: () => _holdingDialog(h),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '删除持仓',
                onPressed: () async {
                  if (await _confirm('删除持仓？', '将删除 ${h.name} 的记录，不会产生真实交易。')) {
                    await _save(
                      d.copyWith(
                        holdings: d.holdings
                            .where((v) => v.id != h.id)
                            .toList(),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
      const Divider(),
      for (final entry in d.industries.entries)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(child: Text(entry.key)),
              Text(percentage(d.assets > 0 ? entry.value / d.assets : null)),
            ],
          ),
        ),
    ]),
    const SizedBox(height: 16),
    PortfolioHistoryPanel(data: d, onRestore: _restorePortfolio),
  ];

  List<Widget> _quant(WorkspaceData d) => [
    if (d.isDemo)
      _notice('当前是虚构演示。请从数据与设置新建空白工作区，再添加自选公司和核验资料；量化示例不会自动启用。')
    else ...[
      QuantResearchPanel(
        data: d,
        onSave: _saveQuant,
        onOpenResearch: (studyId) => _navigate(
          1,
          studyId: d.studies.any((s) => s.id == studyId) ? studyId : null,
        ),
      ),
      const SizedBox(height: 16),
      QuantDataPanel(
        data: d,
        onSave: _saveDataFoundation,
        historyService: widget.historyService,
      ),
    ],
  ];

  List<Widget> _reviews(WorkspaceData d) => [
    FilledButton.icon(
      onPressed: _reviewDialog,
      icon: const Icon(Icons.add),
      label: const Text('记录一次复查'),
    ),
    const SizedBox(height: 16),
    _notice('建议每月复查；新财报或重大公告出现时补充记录。当前版本不发送后台提醒。'),
    const SizedBox(height: 16),
    if (d.reviews.isEmpty)
      _panel('保留你的第一份判断', [
        const Text('写下研究依据、反面证据和下一次验证日期。后续编辑研究卡时，旧内容也会保留在这里。'),
      ]),
    for (final r in d.reviews.reversed) ...[
      _panel(r.company, [
        Text(
          r.createdAt,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        SelectableText(r.text),
      ]),
      const SizedBox(height: 12),
    ],
  ];

  Future<void> _action(String value) async {
    switch (value) {
      case 'account':
        await _accountDialog();
      case 'deepseek':
        await showDialog<void>(
          context: context,
          builder: (_) =>
              DeepSeekSettingsDialog(store: _credentials, service: _ai),
        );
      case 'export':
        await _backupDialog(false);
      case 'import':
        await _backupDialog(true);
      case 'empty':
        if (await _confirm('新建空白工作区？', '会替换当前工作区。请先导出需要保留的数据。')) {
          await _save(WorkspaceData.empty());
        }
    }
  }

  Future<void> _stopBrokerSync() async {
    try {
      await _brokerSync?.stop();
    } catch (_) {
      _message('自动读取已暂停，但本地设置保存失败');
    }
  }

  Future<void> _brokerImport() async {
    if (_brokerDialogBusy || _saving) return;
    _brokerDialogBusy = true;
    try {
      final selected = await showDialog<BrokerImportSelection>(
        context: context,
        builder: (_) =>
            BrokerImportDialog(data: _data!, importer: widget.brokerImporter),
      );
      if (selected == null || !mounted) return;
      final next = applyBrokerSnapshot(
        _data!,
        selected.snapshot,
        sourceChangeConfirmed: selected.sourceChangeConfirmed,
      );
      final recorded = recordPortfolioImport(_data!, next);
      if (!await _save(recorded, portfolioImporting: true) || !mounted) {
        if (mounted) await _recordPortfolioFailure('save_failed');
        return;
      }
      if (selected.automatic) {
        await _brokerSync?.bind(selected.path, selected.snapshot);
      } else {
        await _brokerSync?.stop();
      }
    } on FormatException catch (e) {
      _message('导入未应用：${e.message}');
    } catch (_) {
      _message('持仓已保存时可继续使用；自动读取配置失败，请重新绑定文件');
    } finally {
      _brokerDialogBusy = false;
    }
  }

  Future<void> _recordPortfolioFailure(String code) async {
    if (!mounted || _saving || _data == null || _data!.isDemo) return;
    try {
      final next = recordPortfolioFailure(_data!, code);
      if (!identical(next, _data)) await _save(next, portfolioImporting: true);
    } catch (_) {
      // Keep the current portfolio if a failure record cannot be persisted.
    }
  }

  Future<void> _restorePortfolio(String entryId) async {
    if (_brokerDialogBusy || _saving || _data == null) return;
    _brokerDialogBusy = true;
    try {
      final current = _data!;
      final restored = restorePortfolioHistory(current, entryId);
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('恢复导入前的持仓？'),
          content: SizedBox(
            width: 660,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('只恢复持仓、现金与估值日期；保留当前研究、资料、入金、出金及风险偏好。恢复成功后关闭自动读取。'),
                  const SizedBox(height: 12),
                  PortfolioDiffView(
                    before: PortfolioSnapshot.fromWorkspace(current),
                    after: PortfolioSnapshot.fromWorkspace(restored),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      if (await _save(restored, portfolioImporting: true)) {
        await _stopBrokerSync();
      }
    } on FormatException catch (error) {
      _message('恢复未应用：${error.message}');
    } finally {
      _brokerDialogBusy = false;
    }
  }

  Future<void> _accountDialog() async {
    final d = _data!;
    final values = await _form(
      '账户设置',
      [
        InputField('现金（元）', '${d.cash}', numeric: true),
        InputField(
          '累计入金（元）',
          '${d.deposits}',
          numeric: true,
          readOnly: d.funding != null,
          readOnlyMessage: '累计资金由流水维护，请在量化研究页更新资金记录',
        ),
        InputField(
          '累计出金（元）',
          '${d.withdrawals}',
          numeric: true,
          readOnly: d.funding != null,
          readOnlyMessage: '累计资金由流水维护，请在量化研究页更新资金记录',
        ),
        InputField(
          '可承受暂时亏损（%）',
          '${d.lossBudget * 100}',
          numeric: true,
          max: 100,
        ),
        InputField('价格估值日期（YYYY-MM-DD）', d.priceDate, date: true),
      ],
      note: d.funding == null
          ? '入金和出金是账户资金流，不是买卖股票金额。仅支持现金和股票，不包含融资负债。'
          : '累计入金、出金已由量化研究页的带日期资金记录维护。资金记录不自动改变现金余额，请用完整账户快照核对现金。',
    );
    if (values != null) {
      await _save(
        d.copyWith(
          cash: double.parse(values[0]),
          deposits: double.parse(values[1]),
          withdrawals: double.parse(values[2]),
          lossBudget: double.parse(values[3]) / 100,
          priceDate: values[4],
        ),
      );
    }
  }

  Future<void> _holdingDialog([Holding? h]) async {
    final values = await _form(
      h == null ? '新增持仓' : '编辑持仓',
      [
        InputField('股票代码', h?.code ?? ''),
        InputField('公司名称', h?.name ?? ''),
        InputField('行业', h?.industry ?? ''),
        InputField(
          '数量（股）',
          '${h?.quantity ?? 0}',
          numeric: true,
          integer: true,
        ),
        InputField('同一估值日期的价格（元）', '${h?.price ?? 0}', numeric: true),
      ],
      note: _data!.isDemo
          ? '当前处于模拟工作区。真实数据请先从菜单新建空白工作区。'
          : '请人工核验代码、行业和价格，所有持仓使用同一估值日期。',
    );
    if (values == null) return;
    final holding = Holding(
      id: h?.id ?? newId(),
      code: values[0],
      name: values[1],
      industry: values[2],
      quantity: double.parse(values[3]),
      price: double.parse(values[4]),
    );
    final items = [..._data!.holdings];
    if (h == null) {
      items.add(holding);
    } else {
      items[items.indexWhere((v) => v.id == h.id)] = holding;
    }
    await _save(_data!.copyWith(holdings: items));
  }

  Future<void> _studyDialog([Study? s]) async {
    final identityLocked = s != null && studyIdentityLocked(_data!, s);
    final values = await _form(
      s == null ? '新增研究卡' : '编辑研究卡',
      [
        InputField('股票代码', s?.code ?? '', readOnly: identityLocked),
        InputField('公司名称', s?.name ?? '', readOnly: identityLocked),
        InputField(
          '主营业务与财务事实',
          s?.business ?? '',
          multiline: true,
          optional: true,
        ),
        InputField(
          '一年投资假设与验证指标',
          s?.thesis ?? '',
          multiline: true,
          optional: true,
        ),
        InputField(
          '反面证据与缺失信息',
          s?.counterEvidence ?? '',
          multiline: true,
          optional: true,
        ),
        InputField(
          '需要重新评估的条件',
          s?.reviewCondition ?? '',
          multiline: true,
          optional: true,
        ),
        InputField(
          '来源、报告期、披露日期、页码与单位',
          s?.source ?? '',
          multiline: true,
          optional: true,
        ),
      ],
      note: identityLocked
          ? '公司已关联资料、自选、历史或复查计划，代码与名称保留原值。研究其他公司请新建研究卡，避免沿用旧公司的证据。其余内容可继续编辑。'
          : '只填写可核验的事实。缺资料可以留空，不会自动生成研究结论。',
    );
    if (values == null) return;
    final study = Study(
      id: s?.id ?? newId(),
      code: values[0],
      name: values[1],
      business: values[2],
      thesis: values[3],
      counterEvidence: values[4],
      reviewCondition: values[5],
      source: values[6],
      updatedAt: dateToday(),
      nextReviewAt: s?.nextReviewAt ?? '',
      reviewTasks: s?.reviewTasks ?? [],
    );
    final items = [..._data!.studies];
    if (s == null) {
      items.add(study);
    } else {
      await _save(saveStudyVersion(_data!, study, '人工编辑研究卡'));
      return;
    }
    await _save(_data!.copyWith(studies: items));
  }

  Future<void> _reviewDialog() async {
    final values = await _form('记录一次复查', [
      const InputField('公司或账户', '账户整体'),
      const InputField('原始判断、新证据、反面证据与下次复查日期', '', multiline: true),
    ], note: '保存后保留原记录。需要更正时，新增一条说明。');
    if (values != null) {
      await _save(
        _data!.copyWith(
          reviews: [
            ..._data!.reviews,
            ReviewEntry(
              id: newId(),
              company: values[0],
              text: values[1],
              createdAt: DateTime.now().toIso8601String(),
            ),
          ],
        ),
      );
    }
  }

  Future<List<String>?> _form(
    String title,
    List<InputField> fields, {
    required String note,
  }) => showDialog<List<String>>(
    context: context,
    builder: (_) => DataFormDialog(title: title, fields: fields, note: note),
  );

  Future<void> _backupDialog(bool importing) async {
    if (importing && (_brokerDialogBusy || _saving)) return;
    if (importing) _brokerDialogBusy = true;
    try {
      final parsed = await showDialog<WorkspaceData>(
        context: context,
        builder: (_) => BackupDialog(
          data: _data!,
          importing: importing,
          onCopied: () => _message('备份已复制到剪贴板'),
        ),
      );
      if (parsed != null &&
          mounted &&
          await _confirm(
            '替换当前工作区？',
            '备份包含 ${parsed.holdings.length} 项持仓、${parsed.studies.length} 张研究卡、${parsed.reviews.length} 条复查记录、${parsed.quant.versions.length} 版量化参数、${parsed.priceHistory.length} 份历史行情和 ${parsed.funding?.entries.length ?? 0} 条资金流水。恢复会替换这些记录，随后关闭文件自动读取，需重新预览并绑定。',
          )) {
        // Persist a guard with the restored workspace before attempting to
        // remove a live binding. If settings removal fails, reopening cannot
        // reapply that old source over this restored account snapshot.
        final restored = _brokerSync?.settings != null
            ? parsed.copyWith(
                portfolioImport: parsed.portfolioImport?.markModified(),
              )
            : parsed;
        if (await _save(restored, portfolioImporting: true)) {
          await _stopBrokerSync();
        }
      }
    } finally {
      if (importing) _brokerDialogBusy = false;
    }
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(
      const ClipboardData(
        text: '''请仅根据我随后提供的财报与公告资料，生成一份约一年持有期的公司研究卡。
输出：1.主营业务与财务事实；2.支持理由与未来一年验证指标；3.反面证据；4.缺失信息；5.需要重新评估的条件。
每项事实注明原始来源、页码、报告期、披露日期与单位。事实与推测分开，不编造缺失数据；无法判断时明确说明。数字计算必须人工或程序复核。不要生成保证收益或自动买卖指令。
待提供资料：股票代码、主营业务、近三年和最新财报、现金流、债务、估值及重大公告。''',
      ),
    );
    _message('分析模板已复制；也可在真实研究卡中使用 DeepSeek 草稿');
  }

  Widget _watchlist(
    WorkspaceData d,
  ) => _panel('真实自选 · ${d.watchlist.length}/10 家', [
    if (d.isDemo) const Text('当前是虚构演示。请先导出所需数据，并从菜单新建空白工作区后添加真实公司。'),
    if (!d.isDemo) ...[
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: d.watchlist.length >= 10 ? null : _addCompany,
            icon: const Icon(Icons.add),
            label: const Text('添加真实公司'),
          ),
          OutlinedButton(
            onPressed: d.watchlist.isEmpty ? null : _refreshQuotes,
            child: const Text('更新自选日线'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('使用东方财富未复权收盘价。北京时间 17:00 前只取之前已完成的交易日；不自动改变持仓估值。'),
      for (final c in d.watchlist)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.name} · ${c.symbol} · ${c.industry}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      c.close == null
                          ? '尚无行情'
                          : '${c.close!.toStringAsFixed(2)} 元 · 交易日 ${c.tradeDate}（距今 ${DateTime.now().toUtc().add(const Duration(hours: 8)).difference(DateTime.parse('${c.tradeDate}T00:00:00Z')).inDays} 个自然日）',
                    ),
                    if (c.quoteFetchedAt != null)
                      Text('获取：${c.quoteFetchedAt} · 旧交易日不能代表当前行情'),
                    if (c.error.isNotEmpty)
                      Text(
                        '上次更新失败：${c.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    Material(
                      color: Colors.transparent,
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('查看来源'),
                        children: [
                          SelectableText(
                            '公司信息：${c.source}\n获取：${c.fetchedAt}\n日线：${c.quoteSource ?? '尚未获取'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '移除自选',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  if (await _confirm('移除自选？', '移除 ${c.name}，研究卡、来源与持仓会保留。')) {
                    await _save(
                      _data!.copyWith(
                        watchlist: _data!.watchlist
                            .where((v) => v.id != c.id)
                            .toList(),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
    ],
  ]);
  Future<void> _addCompany() async {
    final c = await showDialog<WatchCompany>(
      context: context,
      builder: (_) => CompanyLookupDialog(service: _market),
    );
    if (c == null || !mounted) return;
    if (_data!.watchlist.any((v) => v.symbol == c.symbol)) {
      _message('公司已在自选中');
      return;
    }
    final studies = [..._data!.studies];
    if (!studies.any((s) => s.code == c.code)) {
      studies.add(
        Study(
          id: newId(),
          code: c.code,
          name: c.name,
          business: '',
          thesis: '',
          counterEvidence: '',
          reviewCondition: '',
          source: '公司名称和行业：${c.source}\n获取：${c.fetchedAt}',
          updatedAt: dateToday(),
        ),
      );
    }
    await _save(
      _data!.copyWith(watchlist: [..._data!.watchlist, c], studies: studies),
    );
  }

  Future<void> _refreshQuotes() async {
    setState(() => _networkBusy = true);
    final updated = <WatchCompany>[];
    try {
      for (final c in _data!.watchlist) {
        try {
          updated.add(await _market.quote(c));
        } on ServiceFailure catch (e) {
          updated.add(
            c.failed(
              '${DateTime.now().toUtc().toIso8601String()} · ${e.message}',
            ),
          );
        } catch (_) {
          updated.add(c.failed('行情校验失败，保留旧价格'));
        }
      }
      if (mounted) await _save(_data!.copyWith(watchlist: updated));
    } finally {
      if (mounted) setState(() => _networkBusy = false);
    }
  }

  Future<void> _applyQuotes() async {
    try {
      final next = applyPortfolioQuotes(_data!);
      if (!await _confirm(
        '更新全部持仓估值？',
        '全部 ${next.holdings.length} 项持仓使用 ${next.priceDate} 收盘价。可能是旧交易日，请核对后确认。',
      )) {
        return;
      }
      await _save(
        next.copyWith(
          reviews: [
            ...next.reviews,
            ReviewEntry(
              id: newId(),
              company: '账户估值',
              createdAt: DateTime.now().toIso8601String(),
              text:
                  '全部持仓统一更新至 ${next.priceDate} 的东方财富未复权收盘价。\n${next.watchlist.where((c) => next.holdings.any((h) => h.code == c.code)).map((c) => '${c.symbol} ${c.close} · 获取 ${c.quoteFetchedAt}\n${c.quoteSource}').join('\n')}',
            ),
          ],
        ),
      );
    } catch (e) {
      _message('$e');
    }
  }

  Future<void> _evidence(Study s) async {
    final files = await _reportFiles;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EvidenceDialog(
        study: s,
        documents: _data!.documents.where((d) => d.studyId == s.id).toList(),
        importer: _pdfImporter,
        reportFetcher: _reportFetcher,
        exchange: _data!.watchlist
            .where((c) => c.code == s.code)
            .map((c) => c.exchange)
            .firstOrNull,
        files: files,
        store: _credentials,
        service: _ai,
        allowAI: !_data!.isDemo,
        sources: _data!.sources.where((e) => e.studyId == s.id).toList(),
        financials: _data!.financials.where((e) => e.studyId == s.id).toList(),
        specialIndustry: _data!.watchlist.any(
          (c) => c.code == s.code && c.specialIndustry,
        ),
        addSource: (e) async {
          await _save(_data!.copyWith(sources: [..._data!.sources, e]));
          return _data!.sources.any((v) => v.id == e.id);
        },
        addFinancial: (e) async {
          await _save(_data!.copyWith(financials: [..._data!.financials, e]));
          return _data!.financials.any((v) => v.id == e.id);
        },
        addDocument: (document, bytes) async {
          final next = _data!.copyWith(
            documents: [..._data!.documents, document],
            sources: [..._data!.sources, ...document.excerpts()],
          );
          WorkspaceData.decode(next.encode());
          await files.put(document.sha256, bytes);
          await _save(next);
          return _data!.documents.any((d) => d.id == document.id);
        },
      ),
    );
  }

  Future<void> _reviewPlan(Study s) async {
    final next = await showDialog<Study>(
      context: context,
      builder: (_) => ReviewPlanDialog(
        study: s,
        sources: _data!.sources.where((e) => e.studyId == s.id).toList(),
      ),
    );
    if (next != null && mounted) {
      await _save(saveStudyVersion(_data!, next, '人工更新复查计划与核验状态'));
    }
  }

  Future<void> _draft(Study s) async {
    final sources = _data!.sources.where((e) => e.studyId == s.id).toList();
    final draft = await showDialog<ResearchDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DraftDialog(
        study: s,
        sources: sources,
        store: _credentials,
        service: _ai,
      ),
    );
    if (draft == null || !mounted || draft.validate(sources).isNotEmpty) return;
    final next = s.copyWith(
      business: draft.render('facts'),
      thesis: draft.render('support'),
      counterEvidence:
          '${draft.render('counter')}\n\n缺失信息：\n${draft.render('missing')}',
      reviewCondition: draft.render('review'),
      source: sources
          .map(
            (e) =>
                '[${e.id}] ${e.title} · ${e.period} · ${e.disclosedAt} · ${e.page} · ${e.unit}\n${e.url}',
          )
          .join('\n'),
      updatedAt: dateToday(),
    );
    await _save(saveStudyVersion(_data!, next, '人工核验后接受 DeepSeek 草稿'));
  }
}
