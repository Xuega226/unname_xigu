import 'dart:convert';

import 'research.dart';
import 'reports.dart';

double _number(Map<String, dynamic> json, String key, {double minimum = 0}) {
  final value = json[key];
  if (value is! num || !value.isFinite || value < minimum) {
    throw FormatException('$key 必须是大于等于 $minimum 的有限数值');
  }
  return value.toDouble();
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key 必须是文本');
  return value;
}

class Holding {
  const Holding({
    required this.id,
    required this.code,
    required this.name,
    required this.industry,
    required this.quantity,
    required this.price,
  });
  final String id, code, name, industry;
  final double quantity, price;
  double get marketValue => quantity * price;
  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'industry': industry,
        'quantity': quantity,
        'price': price,
      };
  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
        id: _string(j, 'id'),
        code: _string(j, 'code'),
        name: _string(j, 'name'),
        industry: _string(j, 'industry'),
        quantity: _number(j, 'quantity'),
        price: _number(j, 'price'),
      );
}

class Study {
  const Study({
    required this.id,
    required this.code,
    required this.name,
    required this.business,
    required this.thesis,
    required this.counterEvidence,
    required this.reviewCondition,
    required this.source,
    required this.updatedAt,
    this.nextReviewAt = '',
    this.reviewTasks = const [],
  });
  final String id, code, name, business, thesis, counterEvidence;
  final String reviewCondition, source, updatedAt;
  final String nextReviewAt;
  final List<ReviewTask> reviewTasks;
  Study copyWith({
    String? business,
    String? thesis,
    String? counterEvidence,
    String? reviewCondition,
    String? source,
    String? updatedAt,
    String? nextReviewAt,
    List<ReviewTask>? reviewTasks,
  }) =>
      Study(
        id: id,
        code: code,
        name: name,
        business: business ?? this.business,
        thesis: thesis ?? this.thesis,
        counterEvidence: counterEvidence ?? this.counterEvidence,
        reviewCondition: reviewCondition ?? this.reviewCondition,
        source: source ?? this.source,
        updatedAt: updatedAt ?? this.updatedAt,
        nextReviewAt: nextReviewAt ?? this.nextReviewAt,
        reviewTasks: reviewTasks ?? this.reviewTasks,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'business': business,
        'thesis': thesis,
        'counterEvidence': counterEvidence,
        'reviewCondition': reviewCondition,
        'source': source,
        'updatedAt': updatedAt,
        'nextReviewAt': nextReviewAt,
        'reviewTasks': reviewTasks.map((t) => t.toJson()).toList(),
      };
  factory Study.fromJson(Map<String, dynamic> j) {
    final nextReview = j['nextReviewAt'] ?? '';
    final tasks = j['reviewTasks'] ?? [];
    if (nextReview is! String ||
        (nextReview.isNotEmpty && !validDate(nextReview)) ||
        tasks is! List ||
        tasks.length > 30) {
      throw const FormatException('复查日期或清单格式无效');
    }
    final parsedTasks = tasks.map((t) {
      if (t is! Map<String, dynamic>) throw const FormatException('复查项格式无效');
      return ReviewTask.fromJson(t);
    }).toList();
    if (parsedTasks.map((t) => t.id).toSet().length != parsedTasks.length) {
      throw const FormatException('复查项 ID 重复');
    }
    return Study(
      id: _string(j, 'id'),
      code: _string(j, 'code'),
      name: _string(j, 'name'),
      business: _string(j, 'business'),
      thesis: _string(j, 'thesis'),
      counterEvidence: _string(j, 'counterEvidence'),
      reviewCondition: _string(j, 'reviewCondition'),
      source: _string(j, 'source'),
      updatedAt: _string(j, 'updatedAt'),
      nextReviewAt: nextReview,
      reviewTasks: parsedTasks,
    );
  }
}

class ReviewTask {
  const ReviewTask({
    required this.id,
    required this.text,
    this.status = '待验证',
    this.note = '',
    this.sourceIds = const [],
  });
  final String id, text, status, note;
  final List<String> sourceIds;
  static const statuses = ['待验证', '成立', '不成立', '资料不足'];
  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'status': status,
        'note': note,
        'sourceIds': sourceIds,
      };
  factory ReviewTask.fromJson(Map<String, dynamic> j) {
    final status = textField(j, 'status'), ids = j['sourceIds'];
    if (!statuses.contains(status) ||
        ids is! List ||
        ids.any((id) => id is! String || id.isEmpty) ||
        ids.length > 20) {
      throw const FormatException('复查状态或来源无效');
    }
    final note = textField(j, 'note', optional: true);
    if (['成立', '不成立'].contains(status) && note.trim().isEmpty) {
      throw const FormatException('核验成立或不成立时须记录判断依据');
    }
    return ReviewTask(
      id: textField(j, 'id'),
      text: textField(j, 'text'),
      status: status,
      note: note,
      sourceIds: ids.cast<String>(),
    );
  }
}

class StudyVersion {
  const StudyVersion({
    required this.id,
    required this.study,
    required this.createdAt,
    required this.reason,
  });
  final String id, createdAt, reason;
  final Study study;
  Map<String, dynamic> toJson() => {
        'id': id,
        'study': study.toJson(),
        'createdAt': createdAt,
        'reason': reason,
      };
  factory StudyVersion.fromJson(Map<String, dynamic> j) {
    if (j['study'] is! Map<String, dynamic>) {
      throw const FormatException('研究历史格式无效');
    }
    return StudyVersion(
      id: textField(j, 'id'),
      study: Study.fromJson(j['study']),
      createdAt: timestampField(j, 'createdAt'),
      reason: textField(j, 'reason'),
    );
  }
}

class ReviewEntry {
  const ReviewEntry({
    required this.id,
    required this.company,
    required this.text,
    required this.createdAt,
  });
  final String id, company, text, createdAt;
  Map<String, dynamic> toJson() => {
        'id': id,
        'company': company,
        'text': text,
        'createdAt': createdAt,
      };
  factory ReviewEntry.fromJson(Map<String, dynamic> j) => ReviewEntry(
        id: _string(j, 'id'),
        company: _string(j, 'company'),
        text: _string(j, 'text'),
        createdAt: _string(j, 'createdAt'),
      );
}

class WorkspaceData {
  const WorkspaceData({
    required this.isDemo,
    required this.cash,
    required this.deposits,
    required this.withdrawals,
    required this.lossBudget,
    required this.priceDate,
    required this.holdings,
    required this.studies,
    required this.reviews,
    this.watchlist = const [],
    this.sources = const [],
    this.financials = const [],
    this.documents = const [],
    this.studyVersions = const [],
  });
  final bool isDemo;
  final double cash, deposits, withdrawals, lossBudget;
  final String priceDate;
  final List<Holding> holdings;
  final List<Study> studies;
  final List<ReviewEntry> reviews;
  final List<WatchCompany> watchlist;
  final List<SourceExcerpt> sources;
  final List<FinancialRecord> financials;
  final List<ReportDocument> documents;
  final List<StudyVersion> studyVersions;
  double get principal => deposits - withdrawals;
  double get stocks => holdings.fold(0, (sum, h) => sum + h.marketValue);
  double get assets => cash + stocks;
  double? get profitRate =>
      principal > 0 ? (assets - principal) / principal : null;
  double? get stockWeight => assets > 0 ? stocks / assets : null;
  double? weight(Holding h) => assets > 0 ? h.marketValue / assets : null;
  double? stressLoss(double decline) {
    if (!decline.isFinite || decline < 0 || decline > 1) {
      throw ArgumentError('情景跌幅必须在 0 到 1 之间');
    }
    return stockWeight == null ? null : stockWeight! * decline;
  }

  Map<String, double> get industries {
    final result = <String, double>{};
    for (final h in holdings) {
      result.update(
        h.industry,
        (value) => value + h.marketValue,
        ifAbsent: () => h.marketValue,
      );
    }
    return result;
  }

  WorkspaceData copyWith({
    bool? isDemo,
    double? cash,
    double? deposits,
    double? withdrawals,
    double? lossBudget,
    String? priceDate,
    List<Holding>? holdings,
    List<Study>? studies,
    List<ReviewEntry>? reviews,
    List<WatchCompany>? watchlist,
    List<SourceExcerpt>? sources,
    List<FinancialRecord>? financials,
    List<ReportDocument>? documents,
    List<StudyVersion>? studyVersions,
  }) =>
      WorkspaceData(
        isDemo: isDemo ?? this.isDemo,
        cash: cash ?? this.cash,
        deposits: deposits ?? this.deposits,
        withdrawals: withdrawals ?? this.withdrawals,
        lossBudget: lossBudget ?? this.lossBudget,
        priceDate: priceDate ?? this.priceDate,
        holdings: holdings ?? this.holdings,
        studies: studies ?? this.studies,
        reviews: reviews ?? this.reviews,
        watchlist: watchlist ?? this.watchlist,
        sources: sources ?? this.sources,
        financials: financials ?? this.financials,
        documents: documents ?? this.documents,
        studyVersions: studyVersions ?? this.studyVersions,
      );
  Map<String, dynamic> toJson() => {
        'schemaVersion': 3,
        'isDemo': isDemo,
        'cash': cash,
        'deposits': deposits,
        'withdrawals': withdrawals,
        'lossBudget': lossBudget,
        'priceDate': priceDate,
        'holdings': holdings.map((h) => h.toJson()).toList(),
        'studies': studies.map((s) => s.toJson()).toList(),
        'reviews': reviews.map((r) => r.toJson()).toList(),
        'watchlist': watchlist.map((r) => r.toJson()).toList(),
        'sources': sources.map((r) => r.toJson()).toList(),
        'financials': financials.map((r) => r.toJson()).toList(),
        'documents': documents.map((r) => r.toJson()).toList(),
        'studyVersions': studyVersions.map((r) => r.toJson()).toList(),
      };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  factory WorkspaceData.decode(String raw) {
    if (raw.length > 8000000) {
      throw const FormatException('备份最多支持 800 万字符，请减少选页与资料长度');
    }
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic> ||
        ![1, 2, 3].contains(j['schemaVersion']) ||
        j['isDemo'] is! bool) {
      throw const FormatException('不是支持的备份格式（需要 schemaVersion 1、2 或 3）');
    }
    List<T> records<T>(String key, T Function(Map<String, dynamic>) parse) {
      final values = j[key];
      if (values is! List) throw FormatException('$key 必须是列表');
      final ids = <String>{};
      return values.map((v) {
        if (v is! Map<String, dynamic>) throw FormatException('$key 记录格式错误');
        final id = _string(v, 'id');
        if (id.isEmpty || !ids.add(id)) {
          throw FormatException('$key 的记录 ID 为空或重复');
        }
        return parse(v);
      }).toList();
    }

    final budget = _number(j, 'lossBudget');
    if (budget > 1) throw const FormatException('亏损偏好必须在 0% 到 100% 之间');
    final priceDate = _string(j, 'priceDate');
    final parsedDate = DateTime.tryParse(priceDate);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(priceDate) ||
        parsedDate == null ||
        parsedDate.toIso8601String().substring(0, 10) != priceDate) {
      throw const FormatException('估值日期无效');
    }
    final result = WorkspaceData(
      isDemo: j['isDemo'] as bool,
      cash: _number(j, 'cash'),
      deposits: _number(j, 'deposits'),
      withdrawals: _number(j, 'withdrawals'),
      lossBudget: budget,
      priceDate: priceDate,
      holdings: records('holdings', Holding.fromJson),
      studies: records('studies', Study.fromJson),
      reviews: records('reviews', ReviewEntry.fromJson),
      watchlist: j['schemaVersion'] == 1
          ? []
          : records('watchlist', WatchCompany.fromJson),
      sources: j['schemaVersion'] == 1
          ? []
          : records('sources', SourceExcerpt.fromJson),
      financials: j['schemaVersion'] == 1
          ? []
          : records('financials', FinancialRecord.fromJson),
      documents: j['schemaVersion'] == 3
          ? records('documents', ReportDocument.fromJson)
          : [],
      studyVersions: j['schemaVersion'] == 3
          ? records('studyVersions', StudyVersion.fromJson)
          : [],
    );
    if (result.isDemo && result.watchlist.isNotEmpty) {
      throw const FormatException('真实自选不可混入演示工作区');
    }
    if (result.watchlist.length > 10 ||
        result.watchlist.map((c) => c.symbol).toSet().length !=
            result.watchlist.length) {
      throw const FormatException('最多 10 家自选，且代码与交易所不可重复');
    }
    final studiesById = {for (final s in result.studies) s.id: s};
    final sourcesById = {for (final s in result.sources) s.id: s};
    final documentsById = {for (final d in result.documents) d.id: d};
    final identities = <String>{};
    final announcements = <String>{};
    for (final document in result.documents) {
      if (!studiesById.containsKey(document.studyId) ||
          !identities.add('${document.studyId}:${document.sha256}')) {
        throw const FormatException('财报无对应研究卡或相同文件重复导入');
      }
      final origin = document.origin;
      if (origin != null) {
        final matching = result.watchlist.where((c) => c.code == origin.code);
        if (studiesById[document.studyId]!.code != origin.code ||
            (matching.isNotEmpty &&
                !matching.any((c) => c.exchange == origin.exchange)) ||
            !announcements.add(
              '${document.studyId}:${origin.exchange}:${origin.code}:${origin.announcementId}',
            )) {
          throw const FormatException('公告证券与研究卡不符或相同公告重复导入');
        }
      }
    }
    for (final s in result.sources) {
      if (!studiesById.containsKey(s.studyId)) {
        throw const FormatException('资料片段没有对应研究卡');
      }
      if (s.documentId != null) {
        final document = documentsById[s.documentId];
        final pages =
            document?.pages.where((p) => p.number == s.pageNumber).toList();
        if (document == null ||
            document.studyId != s.studyId ||
            document.url != s.url ||
            document.title != s.title ||
            document.period != s.period ||
            document.disclosedAt != s.disclosedAt ||
            document.unit != s.unit ||
            pages!.length != 1 ||
            !pages.single.text.contains(s.text)) {
          throw const FormatException('原文片段与财报选页或出处不一致');
        }
      }
    }
    for (final f in result.financials) {
      final source = sourcesById[f.sourceId];
      if (!studiesById.containsKey(f.studyId) ||
          source == null ||
          source.studyId != f.studyId ||
          source.disclosedAt != f.disclosedAt ||
          source.unit != f.unit) {
        throw const FormatException('财务记录的研究卡、来源、披露日期或单位不一致');
      }
      if (source.documentId != null) {
        final doc = documentsById[source.documentId]!;
        if (doc.start != f.start || doc.end != f.end) {
          throw const FormatException('财务报告起止日期与财报不一致');
        }
      }
      for (final proof in f.evidence.values) {
        final origin = sourcesById[proof.sourceId];
        if (origin == null ||
            origin.studyId != f.studyId ||
            origin.unit != f.unit ||
            origin.disclosedAt != f.disclosedAt ||
            !proof.validFor(origin)) {
          throw const FormatException('财务逐项证据不在对应公司原文中');
        }
        if (origin.documentId != null) {
          final doc = documentsById[origin.documentId]!;
          if (doc.start != f.start || doc.end != f.end) {
            throw const FormatException('财务报告起止日期与财报不一致');
          }
        }
      }
    }
    if (!result.assets.isFinite || !result.principal.isFinite) {
      throw const FormatException('账户数值超出可计算范围');
    }
    for (final h in result.holdings) {
      if (h.code.trim().isEmpty ||
          h.name.trim().isEmpty ||
          h.industry.trim().isEmpty ||
          h.quantity != h.quantity.truncateToDouble()) {
        throw const FormatException('持仓代码、名称、行业不可为空，数量必须为整数');
      }
    }
    for (final s in result.studies) {
      if (s.code.trim().isEmpty || s.name.trim().isEmpty) {
        throw const FormatException('研究卡代码与名称不可为空');
      }
      for (final task in s.reviewTasks) {
        if (task.sourceIds.any((id) => sourcesById[id]?.studyId != s.id)) {
          throw const FormatException('复查项引用了不存在或其他公司的资料');
        }
      }
    }
    for (final version in result.studyVersions) {
      if (!studiesById.containsKey(version.study.id) ||
          version.study.reviewTasks.any(
            (t) => t.sourceIds.any(
              (id) => sourcesById[id]?.studyId != version.study.id,
            ),
          )) {
        throw const FormatException('研究历史没有对应研究卡或来源');
      }
    }
    for (final r in result.reviews) {
      if (r.company.trim().isEmpty ||
          r.text.trim().isEmpty ||
          DateTime.tryParse(r.createdAt) == null) {
        throw const FormatException('复查记录必须有对象、内容与有效日期');
      }
    }
    return result;
  }
  factory WorkspaceData.empty() => WorkspaceData(
        isDemo: false,
        cash: 0,
        deposits: 0,
        withdrawals: 0,
        lossBudget: .2,
        priceDate: dateToday(),
        holdings: const [],
        studies: const [],
        reviews: const [],
      );
  factory WorkspaceData.demo() => WorkspaceData(
        isDemo: true,
        cash: 40000,
        deposits: 100000,
        withdrawals: 0,
        lossBudget: .2,
        priceDate: dateToday(),
        holdings: const [
          Holding(
            id: 'h1',
            code: 'DEMO-A',
            name: '示例制造企业',
            industry: '制造',
            quantity: 1000,
            price: 20,
          ),
          Holding(
            id: 'h2',
            code: 'DEMO-B',
            name: '示例消费企业',
            industry: '消费',
            quantity: 500,
            price: 30,
          ),
          Holding(
            id: 'h3',
            code: 'DEMO-C',
            name: '示例服务企业',
            industry: '服务',
            quantity: 500,
            price: 40,
          ),
        ],
        studies: List.generate(
          5,
          (i) => Study(
            id: 's$i',
            code: 'DEMO-${String.fromCharCode(65 + i)}',
            name: ['示例制造企业', '示例消费企业', '示例服务企业', '示例科技企业', '示例能源企业'][i],
            business: '虚构研究卡，用于体验录入流程。尚未录入真实主营业务和财务资料。',
            thesis: '待补充：未来一年要验证的经营指标、当前估值和预期变化。',
            counterEvidence: '资料不足，无法判断盈利质量、现金流与偿债风险。',
            reviewCondition: '补齐最新财报及原始来源后复查；记录判断失效的条件。',
            source: '',
            updatedAt: dateToday(),
          ),
        ),
        reviews: const [],
      );
}

String dateToday() => DateTime.now().toIso8601String().substring(0, 10);
String newId() => DateTime.now().microsecondsSinceEpoch.toString();

WorkspaceData saveStudyVersion(WorkspaceData data, Study next, String reason) {
  final old = data.studies.where((s) => s.id == next.id).single;
  final time = DateTime.now().toIso8601String();
  return data.copyWith(
    studies: data.studies.map((s) => s.id == next.id ? next : s).toList(),
    studyVersions: [
      ...data.studyVersions,
      StudyVersion(id: newId(), study: old, createdAt: time, reason: reason),
    ],
    reviews: [
      ...data.reviews,
      ReviewEntry(
        id: newId(),
        company: old.name,
        createdAt: time,
        text: '$reason\n旧研究卡：\n${old.toJson()}\n接受的新版本：\n${next.toJson()}',
      ),
    ],
  );
}

// Apply quotes atomically, only when every holding has one unambiguous quote
// from the same completed trading date. A partial refresh never changes risk.
WorkspaceData applyPortfolioQuotes(WorkspaceData data) {
  if (data.isDemo || data.holdings.isEmpty) {
    throw const FormatException('需要真实持仓');
  }
  final prices = <Holding, WatchCompany>{};
  for (final holding in data.holdings) {
    final matches =
        data.watchlist.where((c) => c.code == holding.code).toList();
    if (matches.length != 1 ||
        matches.single.close == null ||
        matches.single.error.isNotEmpty) {
      throw FormatException('${holding.code} 缺少唯一且有效的自选行情');
    }
    prices[holding] = matches.single;
  }
  final dates = prices.values.map((c) => c.tradeDate).toSet();
  if (dates.length != 1) throw const FormatException('持仓行情的交易日期不一致，未更新账户估值');
  if (dates.single!.compareTo(data.priceDate) < 0) {
    throw const FormatException('行情早于账户当前估值日期，未回退价格');
  }
  return data.copyWith(
    priceDate: dates.single,
    holdings: data.holdings
        .map(
          (h) => Holding(
            id: h.id,
            code: h.code,
            name: h.name,
            industry: h.industry,
            quantity: h.quantity,
            price: prices[h]!.close!,
          ),
        )
        .toList(),
  );
}
