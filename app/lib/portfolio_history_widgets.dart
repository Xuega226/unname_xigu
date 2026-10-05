import 'package:flutter/material.dart';

import 'domain.dart';
import 'portfolio_history.dart';
import 'portfolio_import_info.dart';

String _money(double value) => '¥ ${value.toStringAsFixed(2)}';
String _signed(double value, {int digits = 2}) =>
    '${value > 0 ? '+' : ''}${value.toStringAsFixed(digits)}';

/// All securities in both snapshots are available, including unchanged rows.
class PortfolioDiffView extends StatefulWidget {
  const PortfolioDiffView({
    super.key,
    required this.before,
    required this.after,
  });
  final PortfolioSnapshot before, after;
  @override
  State<PortfolioDiffView> createState() => _PortfolioDiffViewState();
}

class _PortfolioDiffViewState extends State<PortfolioDiffView> {
  static const _pageSize = 25;
  int _page = 0;

  @override
  void didUpdateWidget(covariant PortfolioDiffView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.before != widget.before || oldWidget.after != widget.after) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = comparePortfolioSnapshots(widget.before, widget.after);
    final pages = (diff.holdings.length / _pageSize).ceil();
    final rows = diff.holdings.skip(_page * _pageSize).take(_pageSize);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('以下为持仓快照差异，数量或市值变化不能证明发生了买卖成交。'),
        const SizedBox(height: 8),
        Text('估值日期：${widget.before.priceDate} → ${widget.after.priceDate}'),
        Text(
          '现金：${_money(widget.before.cash)} → ${_money(widget.after.cash)}（变化 ${_signed(diff.cashDelta)} 元）',
        ),
        Text(
          '总资产：${_money(widget.before.assets)} → ${_money(widget.after.assets)}（变化 ${_signed(diff.assetsDelta)} 元）',
        ),
        Text(
          '证券并集 ${diff.holdings.length} 项 · 新增 ${diff.additions} · 移除 ${diff.removals} · 变化 ${diff.changes}',
        ),
        if (diff.holdings.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('前后均无持仓。'),
          ),
        for (final row in rows)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row.code} ${row.name} · ${row.isAdded
                        ? '新增'
                        : row.isRemoved
                        ? '移除'
                        : row.isChanged
                        ? '变化'
                        : '未变化'}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (row.before != null &&
                      row.after != null &&
                      row.before!.name != row.after!.name)
                    Text('证券名称：${row.before!.name} → ${row.after!.name}'),
                  if (row.before != null &&
                      row.after != null &&
                      row.before!.industry != row.after!.industry)
                    Text('行业：${row.before!.industry} → ${row.after!.industry}'),
                  Text(
                    '股数：${(row.before?.quantity ?? 0).toStringAsFixed(0)} → ${(row.after?.quantity ?? 0).toStringAsFixed(0)}（变化 ${_signed(row.quantityDelta, digits: 0)} 股）',
                  ),
                  Text(
                    '价格：${row.before == null ? '—' : _money(row.before!.price)} → ${row.after == null ? '—' : _money(row.after!.price)}（变化 ${row.priceDelta == null ? '—' : '${_signed(row.priceDelta!)} 元'}）',
                  ),
                  Text(
                    '市值：${_money(row.before?.marketValue ?? 0)} → ${_money(row.after?.marketValue ?? 0)}（变化 ${_signed(row.marketValueDelta)} 元）',
                  ),
                ],
              ),
            ),
          ),
        if (pages > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('第 ${_page + 1} / $pages 页 · 每页 $_pageSize 项'),
                OutlinedButton(
                  key: const ValueKey('portfolio-diff-previous'),
                  onPressed: _page > 0 ? () => setState(() => _page--) : null,
                  child: const Text('上一页'),
                ),
                OutlinedButton(
                  key: const ValueKey('portfolio-diff-next'),
                  onPressed: _page + 1 < pages
                      ? () => setState(() => _page++)
                      : null,
                  child: const Text('下一页'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Selection opens the caller's confirmation preview; this panel never saves.
class PortfolioHistoryPanel extends StatelessWidget {
  const PortfolioHistoryPanel({
    super.key,
    required this.data,
    required this.onRestore,
  });
  final WorkspaceData data;
  final ValueChanged<String> onRestore;

  Future<void> _showDiff(BuildContext context, PortfolioHistoryEntry entry) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('完整持仓差异'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: PortfolioDiffView(
                before: entry.before!,
                after: entry.after!,
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

  @override
  Widget build(BuildContext context) {
    final entries = data.portfolioHistory.reversed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '持仓导入历史',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('最多保留 20 条；优先保留最近可恢复记录，容量不足时提示。'),
        const Text('恢复只改变持仓、现金与估值日期；保留当前研究、入金、出金和亏损偏好，并停止自动读取。'),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('暂无导入或恢复记录。'),
          ),
        for (final entry in entries)
          Card(
            key: ValueKey('portfolio-history-${entry.id}'),
            margin: const EdgeInsets.only(top: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.action == 'import'
                        ? '导入持仓'
                        : entry.action == 'restore'
                        ? '恢复持仓'
                        : '同步失败'} · ${brokerTimeLabel(entry.timestamp)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (entry.error != null)
                    Text(
                      entry.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if (entry.after?.portfolioImport != null)
                    Text(
                      '来源：${entry.after!.portfolioImport!.broker} · ${entry.after!.portfolioImport!.accountAlias}',
                    ),
                  if (entry.referenceId != null)
                    const Text('此记录恢复了此前记录之前的持仓；也可撤销本次恢复。'),
                  if (entry.canRestore) ...[
                    Text(
                      '估值日期：${entry.before!.priceDate} → ${entry.after!.priceDate}',
                    ),
                    Text(
                      '新增 ${entry.diff!.additions} · 移除 ${entry.diff!.removals} · 变化 ${entry.diff!.changes} · 现金变化 ${_signed(entry.diff!.cashDelta)} 元',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          key: ValueKey('history-diff-${entry.id}'),
                          onPressed: () => _showDiff(context, entry),
                          child: const Text('查看完整差异'),
                        ),
                        OutlinedButton(
                          key: ValueKey('history-restore-${entry.id}'),
                          onPressed: () => onRestore(entry.id),
                          child: const Text('恢复此记录之前'),
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
