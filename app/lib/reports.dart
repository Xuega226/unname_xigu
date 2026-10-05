import 'research.dart';

/// Immutable catalogue metadata, kept alongside the human-reviewed PDF fields.
/// Optional in schema 3 so existing workspaces need no destructive migration.
class ReportOrigin {
  const ReportOrigin({
    required this.announcementId,
    required this.code,
    required this.exchange,
    required this.companyName,
    required this.title,
    required this.downloadUrl,
    required this.catalogueUrl,
    required this.start,
    required this.end,
    required this.disclosedAt,
    required this.fetchedAt,
    required this.isRevision,
  });
  final String announcementId, code, exchange, companyName, title;
  final String downloadUrl, catalogueUrl, start, end, disclosedAt, fetchedAt;
  final bool isRevision;

  Map<String, dynamic> toJson() => {
    'announcementId': announcementId,
    'code': code,
    'exchange': exchange,
    'companyName': companyName,
    'title': title,
    'downloadUrl': downloadUrl,
    'catalogueUrl': catalogueUrl,
    'start': start,
    'end': end,
    'disclosedAt': disclosedAt,
    'fetchedAt': fetchedAt,
    'isRevision': isRevision,
  };

  factory ReportOrigin.fromJson(Map<String, dynamic> j) {
    final code = textField(j, 'code'), exchange = textField(j, 'exchange');
    final id = textField(j, 'announcementId');
    final start = dateField(j, 'start'), end = dateField(j, 'end');
    final disclosure = dateField(j, 'disclosedAt');
    final download = sourceUrl(j, 'downloadUrl');
    final catalogue = sourceUrl(j, 'catalogueUrl');
    final downloadUri = Uri.parse(download),
        catalogueUri = Uri.parse(catalogue);
    if (!validAShareSymbol(exchange, code) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id) ||
        start.compareTo(end) > 0 ||
        end.compareTo(disclosure) > 0 ||
        j['isRevision'] is! bool ||
        downloadUri.port != 443 ||
        catalogueUri.port != 443 ||
        ![
          'static.cninfo.com.cn',
          'www.cninfo.com.cn',
        ].contains(Uri.parse(download).host) ||
        Uri.parse(catalogue).host != 'www.cninfo.com.cn') {
      throw const FormatException('自动获取的公告身份、日期或出处无效');
    }
    return ReportOrigin(
      announcementId: id,
      code: code,
      exchange: exchange,
      companyName: textField(j, 'companyName'),
      title: textField(j, 'title'),
      downloadUrl: download,
      catalogueUrl: catalogue,
      start: start,
      end: end,
      disclosedAt: disclosure,
      fetchedAt: timestampField(j, 'fetchedAt'),
      isRevision: j['isRevision'] as bool,
    );
  }
}

class ReportPage {
  const ReportPage({required this.number, required this.text});
  final int number;
  final String text;
  Map<String, dynamic> toJson() => {'number': number, 'text': text};
  factory ReportPage.fromJson(Map<String, dynamic> j) {
    final number = j['number'];
    final text = textField(j, 'text');
    if (number is! int || number < 1 || number > 1000 || text.length > 64000) {
      throw const FormatException('财报页码或文字长度无效');
    }
    return ReportPage(number: number, text: text);
  }
}

class ReportDocument {
  const ReportDocument({
    required this.id,
    required this.studyId,
    required this.fileName,
    required this.sha256,
    required this.title,
    required this.url,
    required this.period,
    required this.start,
    required this.end,
    required this.disclosedAt,
    required this.unit,
    required this.importedAt,
    required this.pageCount,
    required this.pages,
    this.origin,
  });
  final String id, studyId, fileName, sha256, title, url, period, start, end;
  final String disclosedAt, unit, importedAt;
  final int pageCount;
  final List<ReportPage> pages;
  final ReportOrigin? origin;
  String? get announcementId => origin?.announcementId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'studyId': studyId,
    'fileName': fileName,
    'sha256': sha256,
    'title': title,
    'url': url,
    'period': period,
    'start': start,
    'end': end,
    'disclosedAt': disclosedAt,
    'unit': unit,
    'importedAt': importedAt,
    'pageCount': pageCount,
    'pages': pages.map((p) => p.toJson()).toList(),
    if (origin != null) 'origin': origin!.toJson(),
  };
  factory ReportDocument.fromJson(Map<String, dynamic> j) {
    final hash = textField(j, 'sha256');
    final pageCount = j['pageCount'];
    final rawPages = j['pages'];
    final start = dateField(j, 'start'), end = dateField(j, 'end');
    final disclosure = dateField(j, 'disclosedAt');
    final url = textField(j, 'url', optional: true);
    if (url.isNotEmpty) sourceUrl(j, 'url');
    final rawOrigin = j['origin'];
    if (rawOrigin != null && rawOrigin is! Map<String, dynamic>) {
      throw const FormatException('公告出处格式无效');
    }
    final origin = rawOrigin == null
        ? null
        : ReportOrigin.fromJson(rawOrigin as Map<String, dynamic>);
    if (origin != null && url != origin.downloadUrl) {
      throw const FormatException('财报网址与下载出处不一致');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        pageCount is! int ||
        pageCount < 1 ||
        pageCount > 1000 ||
        rawPages is! List ||
        rawPages.isEmpty ||
        rawPages.length > 25 ||
        start.compareTo(end) > 0 ||
        end.compareTo(disclosure) > 0) {
      throw const FormatException('财报文件信息或报告日期无效');
    }
    final pages = rawPages.map((p) {
      if (p is! Map<String, dynamic>) throw const FormatException('财报页格式无效');
      return ReportPage.fromJson(p);
    }).toList();
    if (pages.map((p) => p.number).toSet().length != pages.length ||
        pages.any((p) => p.number > pageCount) ||
        pages.fold<int>(0, (n, p) => n + p.text.length) > 240000) {
      throw const FormatException('选页重复、越界或总文字超过 240000 字');
    }
    final unit = textField(j, 'unit');
    if (!['元', '万元', '亿元', '不适用'].contains(unit)) {
      throw const FormatException('原文单位无效');
    }
    return ReportDocument(
      id: textField(j, 'id'),
      studyId: textField(j, 'studyId'),
      fileName: textField(j, 'fileName'),
      sha256: hash,
      title: textField(j, 'title'),
      url: url,
      period: textField(j, 'period'),
      start: start,
      end: end,
      disclosedAt: disclosure,
      unit: unit,
      importedAt: timestampField(j, 'importedAt'),
      pageCount: pageCount,
      pages: pages,
      origin: origin,
    );
  }
  List<SourceExcerpt> excerpts() {
    final result = <SourceExcerpt>[];
    for (final page in pages) {
      for (var offset = 0; offset < page.text.length;) {
        var end = (offset + 24000).clamp(0, page.text.length);
        if (end < page.text.length &&
            page.text.codeUnitAt(end - 1) >= 0xD800 &&
            page.text.codeUnitAt(end - 1) <= 0xDBFF &&
            page.text.codeUnitAt(end) >= 0xDC00 &&
            page.text.codeUnitAt(end) <= 0xDFFF) {
          end--;
        }
        final text = page.text.substring(offset, end);
        final chunkStart = offset;
        offset = end;
        if (text.trim().isEmpty) continue;
        result.add(
          SourceExcerpt(
            id: '$id-p${page.number}-$chunkStart',
            studyId: studyId,
            title: title,
            url: url,
            period: period,
            disclosedAt: disclosedAt,
            page: 'PDF 第 ${page.number} 页 · 字符 ${chunkStart + 1}–$end',
            unit: unit,
            text: text,
            documentId: id,
            pageNumber: page.number,
          ),
        );
      }
    }
    return result;
  }
}
