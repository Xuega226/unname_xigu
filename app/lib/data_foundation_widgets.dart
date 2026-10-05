import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data_foundation.dart';
import 'domain.dart';
import 'research.dart';

class QuantDataPanel extends StatefulWidget {
  const QuantDataPanel({
    super.key,
    required this.data,
    required this.onSave,
    this.historyService,
  });
  final WorkspaceData data;
  final Future<bool> Function(WorkspaceData) onSave;
  final MarketHistoryService? historyService;
  @override
  State<QuantDataPanel> createState() => _QuantDataPanelState();
}

class _QuantDataPanelState extends State<QuantDataPanel> {
  bool _busy = false;
  int _page = 0;
  Future<T?> _showDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    List<TextEditingController> controllers = const [],
  }) => showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) =>
        _ControllerScope(controllers: controllers, child: builder(context)),
  );
  String _today() => DateTime.now()
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _importHistory() async {
    final text = TextEditingController();
    final raw = await _showDialog<String>(
      controllers: [text],
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入单个历史序列 JSON'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '需提供 symbol、未复权口径、HTTPS 来源、带时区获取时间和升序 bars；不会改持仓价格。',
                ),
                TextField(
                  key: const Key('history-json-input'),
                  controller: text,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: '历史 JSON'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('校验并预览'),
          ),
        ],
      ),
    );
    if (raw == null || !mounted) return;
    try {
      await _previewHistory(PriceHistory.decode(raw));
    } on FormatException catch (e) {
      _message('未导入，旧历史已保留：${e.message}');
    }
  }

  Future<void> _fetchHistory() async {
    final input = TextEditingController(
      text: widget.data.watchlist.isEmpty
          ? 'SH:600001'
          : '${widget.data.watchlist.first.exchange}:${widget.data.watchlist.first.code}',
    );
    final symbol = await _showDialog<String>(
      controllers: [input],
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('获取公开未复权日线'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '从东方财富公开行情请求约两年、最多 500 根日线。17 点前排除当日数据；停牌与来源缺失可能造成日期间断。',
                ),
                TextField(
                  key: const Key('history-symbol-input'),
                  controller: input,
                  decoration: const InputDecoration(
                    labelText: '交易所:代码（如 SH:600001）',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('获取并预览'),
          ),
        ],
      ),
    );
    if (symbol == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final history = await (widget.historyService ?? MarketHistoryService())
          .history(symbol);
      if (mounted) await _previewHistory(history);
    } catch (_) {
      _message('历史行情获取或校验失败，旧历史已保留；可检查代码、网络或改用 JSON 导入。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _summary(PriceHistory h) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('${h.symbol} · 未复权 · ${h.bars.length} 根'),
      Text(
        '${h.bars.first.date} 至 ${h.bars.last.date} · 首尾收盘 ${h.bars.first.close} / ${h.bars.last.close}',
      ),
      Text('来源：${h.source}', style: const TextStyle(fontSize: 12)),
      Text('获取：${h.fetchedAt}', style: const TextStyle(fontSize: 12)),
      const Text('日期范围不代表完整交易日覆盖；除权除息可能造成跳变，不能据此推算复权收益。'),
    ],
  );

  Future<void> _previewHistory(PriceHistory history) async {
    if (!mounted) return;
    final current = widget.data.priceHistory;
    final existing = current
        .where((h) => h.symbol == history.symbol)
        .firstOrNull;
    if (existing == null && current.length >= 10) {
      _message('最多保存 10 个历史序列，请先删除不需要的序列');
      return;
    }
    if (current.any((h) => h.id == history.id && h.symbol != history.symbol)) {
      _message('历史 ID 已属于其他公司，未应用');
      return;
    }
    final next = [...current.where((h) => h.symbol != history.symbol), history];
    bool saving = false;
    String? error;
    await _showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            existing == null ? '确认新增历史序列' : '确认替换 ${history.symbol} 的历史序列',
          ),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (existing != null)
                    Text(
                      '原序列：${existing.bars.first.date} 至 ${existing.bars.last.date}，${existing.bars.length} 根',
                    ),
                  _summary(history),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('history-confirm-save'),
              onPressed: saving
                  ? null
                  : () async {
                      update(() {
                        saving = true;
                        error = null;
                      });
                      bool ok = false;
                      try {
                        ok = await widget.onSave(
                          widget.data.copyWith(priceHistory: next),
                        );
                      } catch (_) {
                        /* Keep preview available. */
                      }
                      if (!dialogContext.mounted) return;
                      if (ok) {
                        Navigator.pop(dialogContext);
                      } else {
                        update(() {
                          saving = false;
                          error = '保存失败，旧历史已保留，可以重试或取消';
                        });
                      }
                    },
              child: Text(saving ? '保存中…' : '确认保存历史'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(PriceHistory h) async {
    await _showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('导出 ${h.symbol} 历史 JSON'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(child: SelectableText(h.encode())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: h.encode()));
              _message('单序列 JSON 已复制，可保存为文件');
            },
            child: const Text('复制 JSON'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSave(
    String title,
    String text,
    WorkspaceData next,
  ) async {
    bool saving = false;
    String? error;
    await _showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      update(() {
                        saving = true;
                        error = null;
                      });
                      bool ok = false;
                      try {
                        ok = await widget.onSave(next);
                      } catch (_) {
                        /* Keep confirmation open. */
                      }
                      if (!dialogContext.mounted) return;
                      if (ok) {
                        Navigator.pop(dialogContext);
                      } else {
                        update(() {
                          saving = false;
                          error = '保存失败，旧记录已保留';
                        });
                      }
                    },
              child: const Text('确认'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enableFunding() async {
    final date = TextEditingController(text: _today());
    String? error;
    bool saving = false;
    await _showDialog<void>(
      controllers: [date],
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('确认资金流水覆盖起点'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '当前累计转入 ${widget.data.deposits.toStringAsFixed(2)}、转出 ${widget.data.withdrawals.toStringAsFixed(2)} 将保留为期初汇总，不拆造历史日期或流水。',
                  ),
                  const Text(
                    '此前时期未由逐笔流水覆盖。覆盖起点以后录入的流水会增加到期初汇总，避免重复录入已计入汇总的资金。',
                  ),
                  TextField(
                    key: const Key('funding-start-input'),
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: '覆盖起点 YYYY-MM-DD',
                    ),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('funding-enable-confirm'),
              onPressed: saving
                  ? null
                  : () async {
                      try {
                        final d = date.text.trim();
                        if (!validDate(d) || d.compareTo(_today()) > 0) {
                          throw const FormatException('覆盖起点须为有效且不在未来的日期');
                        }
                        final ledger = FundingLedger(
                          coverageStart: d,
                          openingDeposits: widget.data.deposits,
                          openingWithdrawals: widget.data.withdrawals,
                          entries: [],
                        );
                        update(() {
                          saving = true;
                          error = null;
                        });
                        bool ok = false;
                        try {
                          ok = await widget.onSave(
                            widget.data.copyWith(funding: ledger),
                          );
                        } catch (_) {
                          /* Existing totals retained. */
                        }
                        if (!dialogContext.mounted) return;
                        if (ok) {
                          Navigator.pop(dialogContext);
                        } else {
                          update(() {
                            saving = false;
                            error = '保存失败，累计本金与旧记录已保留';
                          });
                        }
                      } on FormatException catch (e) {
                        update(() => error = e.message);
                      }
                    },
              child: const Text('确认启用流水'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editFlow([DatedCashFlow? old]) async {
    final ledger = widget.data.funding;
    if (ledger == null) return;
    final date = TextEditingController(text: old?.date ?? _today());
    final amount = TextEditingController(
      text: old?.amount.toStringAsFixed(2) ?? '',
    );
    final source = TextEditingController(text: old?.source ?? '手动录入');
    CashFlowKind kind = old?.kind ?? CashFlowKind.deposit;
    String? error;
    bool saving = false;
    await _showDialog<void>(
      controllers: [date, amount, source],
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(old == null ? '新增已发生的资金流水' : '编辑资金流水'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('流水只更新累计转入、转出与净本金，不自动修改账户现金或持仓。'),
                  DropdownButtonFormField<CashFlowKind>(
                    key: const Key('funding-kind-input'),
                    initialValue: kind,
                    items: const [
                      DropdownMenuItem(
                        value: CashFlowKind.deposit,
                        child: Text('转入'),
                      ),
                      DropdownMenuItem(
                        value: CashFlowKind.withdrawal,
                        child: Text('转出'),
                      ),
                    ],
                    onChanged: saving ? null : (v) => update(() => kind = v!),
                    decoration: const InputDecoration(labelText: '方向'),
                  ),
                  TextField(
                    key: const Key('funding-date-input'),
                    controller: date,
                    enabled: !saving,
                    decoration: const InputDecoration(
                      labelText: '发生日期 YYYY-MM-DD',
                    ),
                  ),
                  TextField(
                    key: const Key('funding-amount-input'),
                    controller: amount,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: '金额（元，最多两位小数）',
                    ),
                  ),
                  TextField(
                    key: const Key('funding-source-input'),
                    controller: source,
                    enabled: !saving,
                    decoration: const InputDecoration(labelText: '来源说明'),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('funding-flow-save'),
              onPressed: saving
                  ? null
                  : () async {
                      try {
                        final d = date.text.trim();
                        if (!validDate(d) || d.compareTo(_today()) > 0) {
                          throw const FormatException('发生日期须有效且不在未来');
                        }
                        final n = double.tryParse(amount.text.trim());
                        if (n == null) throw const FormatException('请输入有效金额');
                        final flow = DatedCashFlow(
                          id:
                              old?.id ??
                              'flow-${DateTime.now().microsecondsSinceEpoch}',
                          date: d,
                          kind: kind,
                          amount: n,
                          source: source.text.trim(),
                        );
                        final updated = ledger.copyWith(
                          entries: [
                            for (final e in ledger.entries)
                              if (e.id != old?.id) e,
                            flow,
                          ],
                        );
                        update(() {
                          saving = true;
                          error = null;
                        });
                        bool ok = false;
                        try {
                          ok = await widget.onSave(
                            widget.data.copyWith(
                              funding: updated,
                              deposits: updated.deposits,
                              withdrawals: updated.withdrawals,
                            ),
                          );
                        } catch (_) {
                          /* Existing totals retained. */
                        }
                        if (!dialogContext.mounted) return;
                        if (ok) {
                          Navigator.pop(dialogContext);
                        } else {
                          update(() {
                            saving = false;
                            error = '保存失败，流水与累计本金未改变';
                          });
                        }
                      } on FormatException catch (e) {
                        update(() => error = e.message);
                      }
                    },
              child: const Text('确认保存流水'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final ledger = data.funding;
    final entries = ledger == null ? <DatedCashFlow>[] : [...ledger.entries]
      ..sort((a, b) => b.date.compareTo(a.date));
    final pages = entries.isEmpty ? 1 : (entries.length / 20).ceil();
    final page = _page.clamp(0, pages - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '量化数据基础',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Text(
                  '历史日线与资金流水独立保存；不会自动改变持仓或公司研究。历史价格只支持未复权，资金覆盖之前仅保留累计汇总。',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      key: const Key('history-import-json'),
                      onPressed: _busy ? null : _importHistory,
                      child: const Text('导入历史 JSON'),
                    ),
                    OutlinedButton(
                      key: const Key('history-fetch'),
                      onPressed: _busy ? null : _fetchHistory,
                      child: Text(_busy ? '获取中…' : '获取公开历史日线'),
                    ),
                  ],
                ),
                if (data.priceHistory.isEmpty)
                  const Text('尚无历史日线。资料不足时不会计算缺失因子。'),
                for (final h in data.priceHistory)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summary(h),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => _export(h),
                              child: const Text('导出 JSON'),
                            ),
                            TextButton(
                              onPressed: () => _confirmSave(
                                '删除历史序列？',
                                '${h.symbol} 的历史日线将移除，持仓和研究保持不变。',
                                data.copyWith(
                                  priceHistory: data.priceHistory
                                      .where((v) => v.id != h.id)
                                      .toList(),
                                ),
                              ),
                              child: const Text('删除历史'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '按日期的资金流水',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (ledger == null) ...[
                  const Text('尚未启用逐笔流水；当前净本金仍来自手动累计转入与转出，不能据此推算历史净值。'),
                  Text(
                    '累计转入 ${data.deposits.toStringAsFixed(2)} · 转出 ${data.withdrawals.toStringAsFixed(2)} · 净本金 ${data.principal.toStringAsFixed(2)}',
                  ),
                  FilledButton.tonal(
                    key: const Key('funding-enable'),
                    onPressed: _enableFunding,
                    child: const Text('确认起点并启用流水'),
                  ),
                ] else ...[
                  Text('覆盖起点：${ledger.coverageStart}；之前时期不具备逐笔覆盖。'),
                  Text(
                    '期初汇总：转入 ${ledger.openingDeposits.toStringAsFixed(2)} · 转出 ${ledger.openingWithdrawals.toStringAsFixed(2)}',
                  ),
                  Text(
                    '累计转入 ${ledger.deposits.toStringAsFixed(2)} · 转出 ${ledger.withdrawals.toStringAsFixed(2)} · 净本金 ${ledger.principal.toStringAsFixed(2)}',
                  ),
                  FilledButton.tonal(
                    key: const Key('funding-add'),
                    onPressed: () => _editFlow(),
                    child: const Text('新增资金流水'),
                  ),
                  if (entries.isEmpty) const Text('覆盖起点以后尚无逐笔记录。'),
                  for (final e in entries.skip(page * 20).take(20))
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${e.date} · ${e.kind == CashFlowKind.deposit ? '转入' : '转出'} ${e.amount.toStringAsFixed(2)} 元 · ${e.source}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                key: Key('funding-edit-${e.id}'),
                                onPressed: () => _editFlow(e),
                                child: const Text('编辑流水'),
                              ),
                              TextButton(
                                key: Key('funding-delete-${e.id}'),
                                onPressed: () {
                                  final updated = ledger.copyWith(
                                    entries: ledger.entries
                                        .where((v) => v.id != e.id)
                                        .toList(),
                                  );
                                  _confirmSave(
                                    '确认删除资金流水？',
                                    '将删除 ${e.date} 的 ${e.amount.toStringAsFixed(2)} 元流水，累计本金同步更新，账户现金不变。',
                                    data.copyWith(
                                      funding: updated,
                                      deposits: updated.deposits,
                                      withdrawals: updated.withdrawals,
                                    ),
                                  );
                                },
                                child: const Text('删除流水'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (pages > 1)
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton(
                          key: const Key('funding-previous'),
                          onPressed: page > 0
                              ? () => setState(() => _page = page - 1)
                              : null,
                          child: const Text('上一页'),
                        ),
                        Text('${page + 1}/$pages · 共 ${entries.length} 条'),
                        TextButton(
                          key: const Key('funding-next'),
                          onPressed: page < pages - 1
                              ? () => setState(() => _page = page + 1)
                              : null,
                          child: const Text('下一页'),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// A route remains mounted while its closing animation runs. Dispose controllers
// with the dialog subtree, rather than when Navigator.pop completes its Future.
class _ControllerScope extends StatefulWidget {
  const _ControllerScope({required this.controllers, required this.child});
  final List<TextEditingController> controllers;
  final Widget child;
  @override
  State<_ControllerScope> createState() => _ControllerScopeState();
}

class _ControllerScopeState extends State<_ControllerScope> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
