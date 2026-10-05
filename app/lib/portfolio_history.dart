import 'dart:convert';

import 'domain.dart';
import 'portfolio_import_info.dart';
import 'research.dart';

const portfolioHistoryMaxEntries = 20;
const portfolioHistoryMaxChars = 4000000;

const portfolioFailureMessages = <String, String>{
  'file_missing': '绑定文件不存在，请重新选择完整持仓文件。',
  'read_failed': '无法读取持仓文件，请检查文件是否可用。',
  'invalid_snapshot': '持仓文件校验失败，当前持仓未更改。',
  'stale_snapshot': '快照比当前估值旧，当前持仓未更改。',
  'source_changed': '持仓来源已改变，请预览并重新确认资金归属。',
  'manual_modified': '持仓已手动修改，请重新预览后绑定。',
  'save_failed': '保存失败，当前持仓未更改。',
  'capacity_exceeded': '历史容量不足，当前持仓未更改。',
  'empty_snapshot': '快照持仓为空，请人工核对后重新导入。',
  'conflicting_timestamp': '相同快照时间出现不同内容，请人工核对。',
  'settings_failed': '无法保存同步设置，请重新绑定文件。',
};

/// Only reversible portfolio fields are captured. Funding and research stay live.
class PortfolioSnapshot {
  const PortfolioSnapshot({
    required this.cash,
    required this.priceDate,
    required this.holdings,
    this.portfolioImport,
  });
  final double cash;
  final String priceDate;
  final List<Holding> holdings;
  final PortfolioImportInfo? portfolioImport;
  double get assets =>
      cash + holdings.fold(0.0, (sum, h) => sum + h.marketValue);

  factory PortfolioSnapshot.fromWorkspace(WorkspaceData data) =>
      PortfolioSnapshot(
        cash: data.cash,
        priceDate: data.priceDate,
        holdings: List.unmodifiable(data.holdings),
        portfolioImport: data.portfolioImport,
      );
  Map<String, dynamic> toJson() => {
    'cash': cash,
    'priceDate': priceDate,
    'holdings': holdings.map((h) => h.toJson()).toList(),
    'portfolioImport': portfolioImport?.toJson(),
  };

  factory PortfolioSnapshot.fromJson(Map<String, dynamic> j) {
    final cash = j['cash'], rows = j['holdings'], info = j['portfolioImport'];
    if (cash is! num ||
        !cash.isFinite ||
        cash < 0 ||
        rows is! List ||
        rows.length > 10000 ||
        (info != null && info is! Map<String, dynamic>)) {
      throw const FormatException('持仓历史快照格式无效');
    }
    final ids = <String>{};
    final holdings = rows.map((row) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('持仓历史证券格式无效');
      }
      final h = Holding.fromJson(row);
      // A before snapshot may contain older, manually entered holdings. Keep
      // the workspace's existing validity rules so a reviewed broker import
      // can replace them and still restore their exact values. New broker
      // rows retain their stricter code and market-price checks at parsing.
      if (h.id.isEmpty ||
          !ids.add(h.id) ||
          h.code.trim().isEmpty ||
          h.name.trim().isEmpty ||
          h.industry.trim().isEmpty ||
          h.quantity != h.quantity.truncateToDouble() ||
          !h.marketValue.isFinite) {
        throw const FormatException('持仓历史证券字段或数量无效');
      }
      return h;
    }).toList();
    final result = PortfolioSnapshot(
      cash: cash.toDouble(),
      priceDate: dateField(j, 'priceDate'),
      holdings: List.unmodifiable(holdings),
      portfolioImport: info == null ? null : PortfolioImportInfo.fromJson(info),
    );
    if (!result.assets.isFinite) {
      throw const FormatException('持仓历史资产超出可计算范围');
    }
    return result;
  }
}

class PortfolioHistoryEntry {
  const PortfolioHistoryEntry({
    required this.id,
    required this.timestamp,
    required this.action,
    this.before,
    this.after,
    this.referenceId,
    this.error,
    this.errorCode,
  });
  final String id, timestamp, action;
  final PortfolioSnapshot? before, after;
  final String? referenceId, error, errorCode;
  bool get canRestore => action != 'failure' && before != null && after != null;
  PortfolioDiff? get diff =>
      canRestore ? comparePortfolioSnapshots(before!, after!) : null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp,
    'action': action,
    'before': before?.toJson(),
    'after': after?.toJson(),
    'referenceId': referenceId,
    'error': error,
    'errorCode': errorCode,
  };
  factory PortfolioHistoryEntry.fromJson(Map<String, dynamic> j) {
    final action = textField(j, 'action');
    final before = j['before'], after = j['after'];
    final reference = j['referenceId'], error = j['error'];
    final code = j['errorCode'];
    if (!['import', 'restore', 'failure'].contains(action) ||
        (reference != null &&
            (reference is! String || reference.trim().isEmpty)) ||
        (error != null &&
            (error is! String || error.trim().isEmpty || error.length > 500)) ||
        (action == 'failure' &&
            (before != null ||
                after != null ||
                error == null ||
                code is! String ||
                portfolioFailureMessages[code] != error ||
                reference != null)) ||
        (action != 'failure' &&
            (before is! Map<String, dynamic> ||
                after is! Map<String, dynamic> ||
                error != null ||
                code != null)) ||
        (action == 'restore' && reference == null) ||
        (action == 'import' && reference != null)) {
      throw const FormatException('持仓历史记录无效');
    }
    return PortfolioHistoryEntry(
      id: brokerMetadataLabel(j['id'], '持仓历史 ID'),
      timestamp: brokerTimestamp(j['timestamp'], '持仓历史时间'),
      action: action,
      before: before == null
          ? null
          : PortfolioSnapshot.fromJson(before as Map<String, dynamic>),
      after: after == null
          ? null
          : PortfolioSnapshot.fromJson(after as Map<String, dynamic>),
      referenceId: reference as String?,
      error: error as String?,
      errorCode: code as String?,
    );
  }
}

/// A snapshot difference, never an assertion that a trade was executed.
class PortfolioHoldingChange {
  const PortfolioHoldingChange({required this.code, this.before, this.after});
  final String code;
  final Holding? before, after;
  String get name => after?.name ?? before!.name;
  double get quantityDelta => (after?.quantity ?? 0) - (before?.quantity ?? 0);
  double? get priceDelta =>
      before == null || after == null ? null : after!.price - before!.price;
  double get marketValueDelta =>
      (after?.marketValue ?? 0) - (before?.marketValue ?? 0);
  bool get isAdded => before == null;
  bool get isRemoved => after == null;
  bool get isChanged =>
      isAdded ||
      isRemoved ||
      quantityDelta != 0 ||
      priceDelta != 0 ||
      before!.name != after!.name ||
      before!.industry != after!.industry;
}

class PortfolioDiff {
  const PortfolioDiff({
    required this.holdings,
    required this.cashDelta,
    required this.assetsDelta,
  });
  final List<PortfolioHoldingChange> holdings;
  final double cashDelta, assetsDelta;
  int get additions => holdings.where((h) => h.isAdded).length;
  int get removals => holdings.where((h) => h.isRemoved).length;
  int get changes =>
      holdings.where((h) => !h.isAdded && !h.isRemoved && h.isChanged).length;
}

PortfolioDiff comparePortfolioSnapshots(
  PortfolioSnapshot before,
  PortfolioSnapshot after,
) {
  Map<String, Holding> byCode(List<Holding> holdings) {
    final result = <String, Holding>{};
    for (final h in holdings) {
      final old = result[h.code];
      if (old == null) {
        result[h.code] = h;
      } else {
        final quantity = old.quantity + h.quantity;
        result[h.code] = Holding(
          id: old.id,
          code: h.code,
          name: old.name,
          industry: old.industry,
          quantity: quantity,
          price: quantity > 0
              ? (old.marketValue + h.marketValue) / quantity
              : h.price,
        );
      }
    }
    return result;
  }

  final old = byCode(before.holdings), next = byCode(after.holdings);
  final codes = {...old.keys, ...next.keys}.toList()..sort();
  return PortfolioDiff(
    holdings: List.unmodifiable(
      codes.map(
        (code) => PortfolioHoldingChange(
          code: code,
          before: old[code],
          after: next[code],
        ),
      ),
    ),
    cashDelta: after.cash - before.cash,
    assetsDelta: after.assets - before.assets,
  );
}

void validatePortfolioHistory(List<PortfolioHistoryEntry> entries) {
  final ids = <String>{};
  if (entries.length > portfolioHistoryMaxEntries ||
      jsonEncode(entries.map((e) => e.toJson()).toList()).length >
          portfolioHistoryMaxChars) {
    throw const FormatException('持仓历史超出容量限制');
  }
  for (final entry in entries) {
    PortfolioHistoryEntry.fromJson(entry.toJson());
    if (!ids.add(entry.id) || entry.referenceId == entry.id) {
      throw const FormatException('持仓历史 ID 重复或引用自身');
    }
  }
}

int _sequence = 0;
PortfolioHistoryEntry _event({
  required String action,
  PortfolioSnapshot? before,
  PortfolioSnapshot? after,
  String? referenceId,
  String? errorCode,
}) {
  final now = DateTime.now().toUtc();
  return PortfolioHistoryEntry(
    id: 'portfolio-${now.microsecondsSinceEpoch}-${_sequence++}',
    timestamp: now.toIso8601String(),
    action: action,
    before: before,
    after: after,
    referenceId: referenceId,
    errorCode: errorCode,
    error: errorCode == null ? null : portfolioFailureMessages[errorCode],
  );
}

List<PortfolioHistoryEntry> _append(
  List<PortfolioHistoryEntry> history,
  PortfolioHistoryEntry entry,
) {
  PortfolioHistoryEntry.fromJson(entry.toJson());
  if (jsonEncode([entry.toJson()]).length > portfolioHistoryMaxChars) {
    throw const FormatException('本次持仓快照过大，无法保留可撤销历史');
  }
  final result = [...history, entry];
  // Always keep the new event and the most recent reversible event. A failure
  // must never evict the only snapshot that can undo a successful import.
  final protected = <String>{entry.id};
  final reversible = result.where((e) => e.canRestore);
  if (reversible.isNotEmpty) protected.add(reversible.last.id);
  while (result.length > portfolioHistoryMaxEntries ||
      jsonEncode(result.map((e) => e.toJson()).toList()).length >
          portfolioHistoryMaxChars) {
    final index = result.indexWhere((e) => !protected.contains(e.id));
    if (index < 0) {
      throw const FormatException('持仓历史容量不足，请减少快照大小后再导入');
    }
    result.removeAt(index);
  }
  validatePortfolioHistory(result);
  return List.unmodifiable(result);
}

WorkspaceData _withHistory(WorkspaceData data, PortfolioHistoryEntry entry) {
  final next = data.copyWith(
    portfolioHistory: _append(data.portfolioHistory, entry),
  );
  // Validate the full, indented backup budget before any caller persists it.
  // Reject rather than silently discard research to make a snapshot fit.
  WorkspaceData.decode(next.encode());
  return next;
}

WorkspaceData recordPortfolioImport(WorkspaceData before, WorkspaceData after) {
  if (before.isDemo || after.isDemo) {
    throw const FormatException('演示工作区不可记录真实持仓导入');
  }
  return _withHistory(
    after,
    _event(
      action: 'import',
      before: PortfolioSnapshot.fromWorkspace(before),
      after: PortfolioSnapshot.fromWorkspace(after),
    ),
  );
}

/// Codes and messages are fixed. Paths, exception text and credentials never
/// become portable failure history. Adjacent duplicate failures are suppressed.
WorkspaceData recordPortfolioFailure(
  WorkspaceData data,
  String code, {
  String? safeMessage,
}) {
  if (data.isDemo) return data;
  final message = portfolioFailureMessages[code];
  if (message == null || (safeMessage != null && safeMessage != message)) {
    throw const FormatException('仅允许记录预定义的安全失败提示');
  }
  if (data.portfolioHistory.isNotEmpty &&
      data.portfolioHistory.last.action == 'failure' &&
      data.portfolioHistory.last.errorCode == code) {
    return data;
  }
  return _withHistory(data, _event(action: 'failure', errorCode: code));
}

WorkspaceData restorePortfolioHistory(WorkspaceData data, String entryId) {
  final entries = data.portfolioHistory.where((e) => e.id == entryId);
  if (data.isDemo || entries.length != 1 || !entries.single.canRestore) {
    throw const FormatException('只能恢复真实工作区的可恢复持仓历史');
  }
  final target = entries.single.before!;
  final restored = data.copyWith(
    cash: target.cash,
    priceDate: target.priceDate,
    holdings: List.of(target.holdings),
    portfolioImport: target.portfolioImport?.markModified(),
    clearPortfolioImport: target.portfolioImport == null,
  );
  return _withHistory(
    restored,
    _event(
      action: 'restore',
      referenceId: entryId,
      before: PortfolioSnapshot.fromWorkspace(data),
      after: PortfolioSnapshot.fromWorkspace(restored),
    ),
  );
}
