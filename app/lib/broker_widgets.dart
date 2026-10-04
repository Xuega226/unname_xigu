import 'dart:io';

import 'package:flutter/material.dart';

import 'broker_import.dart';
import 'broker_sync.dart';
import 'domain.dart';
import 'forms.dart';

class BrokerImportSelection {
  const BrokerImportSelection(
    this.snapshot,
    this.path,
    this.automatic, {
    this.sourceChangeConfirmed = false,
  });
  final BrokerSnapshot snapshot;
  final String path;
  final bool automatic;
  final bool sourceChangeConfirmed;
}

class BrokerImportDialog extends StatefulWidget {
  const BrokerImportDialog({super.key, required this.data, this.importer});
  final WorkspaceData data;
  final BrokerImportService? importer;
  @override
  State<BrokerImportDialog> createState() => _BrokerImportDialogState();
}

class _BrokerImportDialogState extends State<BrokerImportDialog> {
  BrokerSnapshot? _snapshot;
  String _name = '', _path = '';
  String? _error;
  bool _busy = false, _reviewed = false, _automatic = false;
  bool _sourceChangeConfirmed = false;
  int _holdingPage = 0, _removedPage = 0;
  static const _pageSize = 25;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _error = null;
      _snapshot = null;
      _reviewed = false;
      _automatic = false;
      _sourceChangeConfirmed = false;
      _holdingPage = 0;
      _removedPage = 0;
    });
    try {
      final file = await (widget.importer ?? BrokerImportService()).pick();
      if (file == null) return;
      final bytes = file.bytes;
      CsvAccountDetails? details;
      if (!decodePortfolioText(bytes).trimLeft().startsWith('{')) {
        if (!mounted) return;
        final values = await showDialog<List<String>>(
          context: context,
          builder: (_) => DataFormDialog(
            title: '核对 CSV 的账户信息',
            note: 'CSV 通常缺少现金与估值日期，请按券商账户核对。使用账户别名，不填写密码。当前仅支持 CNY 普通股票账户。',
            fields: [
              InputField('券商名称', widget.data.portfolioImport?.broker ?? ''),
              InputField(
                '账户别名（如主账户）',
                widget.data.portfolioImport?.accountAlias ?? '',
              ),
              InputField('估值日期（YYYY-MM-DD）', widget.data.priceDate, date: true),
              InputField('现金余额（元，非可用资金或购买力）', '', numeric: true),
            ],
          ),
        );
        if (values == null) return;
        details = CsvAccountDetails(
          broker: values[0],
          accountAlias: values[1],
          priceDate: values[2],
          cash: double.parse(values[3]),
        );
      }
      final snapshot = parseBrokerFile(bytes, csv: details);
      applyBrokerSnapshot(
        widget.data,
        snapshot,
        sourceChangeConfirmed: true,
      ); // Fail before displaying an applicable preview.
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _name = file.name;
          _path = file.path;
        });
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '文件读取失败，请重新选择完整的 CSV 或 JSON');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final current = {for (final h in widget.data.holdings) h.code: h};
    final newCodes =
        snapshot?.holdings.map((h) => h.code).toSet() ?? <String>{};
    final removed = widget.data.holdings
        .where((h) => !newCodes.contains(h.code))
        .toList();
    final needsSourceConfirmation =
        snapshot != null &&
        brokerSourceChangeNeedsConfirmation(widget.data, snapshot);
    return AlertDialog(
      title: const Text('导入券商持仓'),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择普通股票账户的完整持仓文件。CSV 手动核对现金与日期；标准 JSON 可在 Windows 自动读取更新。账户直连接口尚待选定券商。',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.folder_open),
                label: Text(_busy ? '正在读取…' : '选择持仓文件'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (snapshot != null) ...[
                const SizedBox(height: 16),
                Text(
                  '$_name · ${snapshot.info.broker} · ${snapshot.info.accountAlias}',
                ),
                Text(
                  '估值日期 ${snapshot.priceDate} · ${snapshot.holdings.length} 项持仓',
                ),
                Text(
                  '现金 ¥ ${snapshot.cash.toStringAsFixed(2)} · 资产 ¥ ${snapshot.assets.toStringAsFixed(2)}',
                ),
                const SizedBox(height: 12),
                const Text('将替换当前账户的全部持仓与现金；保留研究、入金和出金。'),
                if (needsSourceConfirmation) ...[
                  const Text(
                    '券商或账户别名改变，或首次导入前已有资金记录。请核对是否仍属同一账户；其他账户请先导出当前备份、新建空白工作区并自行维护资金。不能根据当前资产倒推本金。',
                  ),
                  CheckboxListTile(
                    key: const ValueKey('broker-source-confirmation'),
                    contentPadding: EdgeInsets.zero,
                    value: _sourceChangeConfirmed,
                    onChanged: (v) =>
                        setState(() => _sourceChangeConfirmed = v!),
                    title: const Text('已核对当前入金、出金仍属于本次导入的同一账户'),
                  ),
                ],
                if (snapshot.holdings.isEmpty)
                  const Text('此文件没有非零持仓：确认后会清空当前持仓。'),
                if (snapshot.holdings.isNotEmpty)
                  Text('全部新持仓（${snapshot.holdings.length} 项）'),
                for (final h
                    in snapshot.holdings
                        .skip(_holdingPage * _pageSize)
                        .take(_pageSize))
                  Padding(
                    key: ValueKey('broker-preview-${h.code}'),
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${h.code} ${h.name} · ${h.quantity.toStringAsFixed(0)} 股 · 市价 ${h.price.toStringAsFixed(2)}'
                      '${current[h.code] == null ? '（新增）' : '\n原 ${current[h.code]!.quantity.toStringAsFixed(0)} 股 · 原市价 ${current[h.code]!.price.toStringAsFixed(2)}'}',
                    ),
                  ),
                if (snapshot.holdings.isNotEmpty)
                  _pages(
                    '持仓',
                    _holdingPage,
                    snapshot.holdings.length,
                    (page) => setState(() => _holdingPage = page),
                  ),
                if (removed.isNotEmpty) ...[
                  Text('全部将移除持仓（${removed.length} 项）'),
                  for (final h
                      in removed.skip(_removedPage * _pageSize).take(_pageSize))
                    Padding(
                      key: ValueKey('broker-removed-${h.code}'),
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '将移除：${h.code} ${h.name} · 原 ${h.quantity.toStringAsFixed(0)} 股 · 原市价 ${h.price.toStringAsFixed(2)}',
                      ),
                    ),
                  _pages(
                    '移除',
                    _removedPage,
                    removed.length,
                    (page) => setState(() => _removedPage = page),
                  ),
                ],
                if (Platform.isWindows && snapshot.info.format == 'json')
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _automatic,
                    onChanged: (v) => setState(() => _automatic = v!),
                    title: const Text('应用在前台时，每 15 秒自动读取同一文件'),
                    subtitle: const Text('文件由外部工具更新；账户变化、旧日期、空持仓和人工修改需重新核对。'),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reviewed,
                  onChanged: (v) => setState(() => _reviewed = v!),
                  title: const Text('已核对账户、完整持仓、现金和估值日期'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  !_reviewed ||
                  snapshot == null ||
                  (needsSourceConfirmation && !_sourceChangeConfirmed)
              ? null
              : () => Navigator.pop(
                  context,
                  BrokerImportSelection(
                    snapshot,
                    _path,
                    _automatic,
                    sourceChangeConfirmed: _sourceChangeConfirmed,
                  ),
                ),
          child: const Text('确认导入'),
        ),
      ],
    );
  }

  Widget _pages(String kind, int page, int count, ValueChanged<int> change) {
    final total = (count / _pageSize).ceil();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$kind第 ${page + 1}/$total 页 · 共 $count 项'),
          TextButton(
            key: ValueKey('broker-$kind-previous'),
            onPressed: page == 0 ? null : () => change(page - 1),
            child: const Text('上一页'),
          ),
          TextButton(
            key: ValueKey('broker-$kind-next'),
            onPressed: page + 1 == total ? null : () => change(page + 1),
            child: const Text('下一页'),
          ),
        ],
      ),
    );
  }
}
