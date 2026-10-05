import 'research.dart';

String financialWindow(FinancialRecord f) {
  final span =
      int.parse(f.end.substring(0, 4)) - int.parse(f.start.substring(0, 4));
  return '${f.scope} · ${f.basis} · ${f.start.substring(5)} 至 ${f.end.substring(5)} · 跨 $span 年';
}

double inTenThousands(double value, String unit) =>
    value *
    switch (unit) {
      '元' => 0.0001,
      '万元' => 1,
      '亿元' => 10000,
      _ => throw const FormatException('金额单位无效'),
    };

double? financialYearGrowth(
  FinancialRecord current,
  String metric,
  List<FinancialRecord> records,
) {
  if (current.scope == '未注明' || current.basis != '原披露') return null;
  final start = DateTime.parse(current.start),
      end = DateTime.parse(current.end);
  final group = records
      .where(
        (r) =>
            r.studyId == current.studyId &&
            financialWindow(r) == financialWindow(current),
      )
      .toList();
  if (group
          .where((r) => r.start == current.start && r.end == current.end)
          .length !=
      1) {
    return null;
  }
  final prior = group
      .where(
        (r) =>
            int.parse(r.start.substring(0, 4)) == start.year - 1 &&
            int.parse(r.end.substring(0, 4)) == end.year - 1,
      )
      .toList();
  if (prior.length != 1) return null;
  final value = current.amounts[metric], base = prior.single.amounts[metric];
  if (value == null || base == null || value < 0 || base <= 0) return null;
  final normalized = inTenThousands(value, current.unit);
  final normalizedBase = inTenThousands(base, prior.single.unit);
  final result = normalized / normalizedBase - 1;
  return result.isFinite ? result : null;
}
