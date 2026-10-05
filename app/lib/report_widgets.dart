import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'report_import.dart';
import 'report_fetch.dart';
import 'reports.dart';
import 'services.dart';
import 'credentials.dart';
import 'report_preparation.dart';

class ReportImportDialog extends StatefulWidget {
  const ReportImportDialog({
    super.key,
    required this.study,
    required this.importer,
    required this.existingHashes,
    required this.save,
    this.initialReport,
    this.announcement,
    this.store,
    this.service,
    this.existingDocument,
    this.coverageOnly = false,
  }) : assert(announcement == null || initialReport != null);
  final Study study;
  final PdfImportService importer;
  final Set<String> existingHashes;
  final Future<bool> Function(ReportDocument, Uint8List) save;
  final ParsedReport? initialReport;
  final ReportAnnouncement? announcement;
  final CredentialStore? store;
  final DeepSeekService? service;
  final ReportDocument? existingDocument;
  final bool coverageOnly;
  @override
  State<ReportImportDialog> createState() => _ReportImportDialogState();
}

class _ReportImportDialogState extends State<ReportImportDialog> {
  ParsedReport? report;
  final selected = <int>{};
  final formKey = GlobalKey<FormState>();
  final title = TextEditingController(),
      url = TextEditingController(),
      period = TextEditingController(),
      start = TextEditingController(),
      end = TextEditingController(),
      disclosure = TextEditingController(),
      search = TextEditingController();
  String unit = '不适用', message = '';
  bool busy = false;
  bool preparing = false;
  int generation = 0;
  PreparationSuggestion? preparation;
  AiSettings settings = const AiSettings();
  double? progress;
  final fetchedAt = DateTime.now().toIso8601String();
  bool get coverageOnly => report?.bytes.isEmpty ?? widget.coverageOnly;
  @override
  void initState() {
    super.initState();
    final initial = widget.initialReport;
    if (initial != null) {
      report = initial;
      title.text = initial.fileName.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final announcement = widget.announcement;
      if (announcement != null) {
        title.text = announcement.title;
        url.text = announcement.url.toString();
        period.text = '${announcement.year} 年度';
        start.text = announcement.start.toIso8601String().substring(0, 10);
        end.text = announcement.end.toIso8601String().substring(0, 10);
        disclosure.text = announcement.disclosedAt.toIso8601String().substring(
          0,
          10,
        );
        // Do not infer the PDF's displayed currency unit from the catalogue.
        unit = '不适用';
      }
      message = '已下载并读取 ${initial.pages.length} 页，请选页并核对金额单位';
      final existing = widget.existingDocument;
      if (existing != null) {
        title.text = existing.title;
        url.text = existing.url;
        period.text = existing.period;
        start.text = existing.start;
        end.text = existing.end;
        disclosure.text = existing.disclosedAt;
        unit = existing.unit;
      }
      applyLocal();
    }
    widget.store
        ?.read()
        .then((value) {
          if (mounted) setState(() => settings = value);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    generation++;
    for (final c in [title, url, period, start, end, disclosure, search]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> choose() async {
    setState(() {
      busy = true;
      message = '';
      progress = null;
    });
    try {
      final result = await widget.importer.pick(
        progress: (done, total) {
          if (mounted) setState(() => progress = done / total);
        },
      );
      if (result != null && mounted) {
        if (widget.existingDocument != null &&
            result.hash != widget.existingDocument!.sha256) {
          throw ServiceFailure('重新准备须选择同一原 PDF；不同文件请另行导入，旧资料已保留');
        }
        if (widget.existingHashes.contains(result.hash)) {
          throw ServiceFailure('这份 PDF 已导入当前研究卡');
        }
        setState(() {
          report = result;
          selected.clear();
          title.text = result.fileName.replaceFirst(
            RegExp(r'\.pdf$', caseSensitive: false),
            '',
          );
          message = '读取 ${result.pages.length} 页，请选择需要核验的原文页';
          preparation = null;
          applyLocal();
        });
      }
    } on ServiceFailure catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (_) {
      if (mounted) setState(() => message = '文件选择或读取失败，未导入资料');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate() ||
        report == null ||
        selected.isEmpty) {
      return;
    }
    setState(() {
      busy = true;
      message = '';
    });
    try {
      final document = ReportDocument.fromJson({
        'id': newId(),
        'studyId': widget.study.id,
        'fileName': report!.fileName,
        'sha256': report!.hash,
        'title': title.text.trim(),
        'url': url.text.trim(),
        'period': period.text.trim(),
        'start': start.text.trim(),
        'end': end.text.trim(),
        'disclosedAt': disclosure.text.trim(),
        'unit': unit,
        'importedAt': DateTime.now().toIso8601String(),
        'pageCount': widget.existingDocument?.pageCount ?? report!.pages.length,
        'pages': report!.pages
            .where((p) => selected.contains(p.number))
            .map((p) => p.toJson())
            .toList(),
        if (preparation != null) 'preparation': preparation!.toJson(),
        if (widget.existingDocument != null)
          'preparedFrom': widget.existingDocument!.id,
        if (widget.announcement == null &&
            widget.existingDocument?.origin != null)
          'origin': widget.existingDocument!.origin!.toJson(),
        if (widget.announcement != null)
          'origin': ReportOrigin(
            announcementId: widget.announcement!.id,
            code: widget.announcement!.code,
            exchange: widget.announcement!.exchange,
            companyName: widget.announcement!.companyName,
            title: widget.announcement!.title,
            downloadUrl: widget.announcement!.url.toString(),
            catalogueUrl: widget.announcement!.sourceUrl,
            start: widget.announcement!.start.toIso8601String().substring(
              0,
              10,
            ),
            end: widget.announcement!.end.toIso8601String().substring(0, 10),
            disclosedAt: widget.announcement!.disclosedAt
                .toIso8601String()
                .substring(0, 10),
            fetchedAt: fetchedAt,
            isRevision: widget.announcement!.isRevision,
          ).toJson(),
      });
      if (widget.existingHashes.contains(document.sha256)) {
        throw const FormatException('这份 PDF 已导入当前研究卡');
      }
      if (document.origin != null &&
          document.origin!.code != widget.study.code) {
        throw const FormatException('公告证券与当前研究卡不符');
      }
      final ok = await widget.save(document, report!.bytes);
      if (mounted) {
        if (ok) {
          Navigator.pop(context, document);
        } else {
          setState(() => message = '保存失败，财报未加入工作区');
        }
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => message = e.message.toString());
    } catch (_) {
      if (mounted) setState(() => message = '原文件或资料保存失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void applyLocal() {
    if (report == null) return;
    final suggestion = locateReportPages(
      '${widget.study.code} ${widget.study.name}',
      report!.pages,
    );
    applySuggestion(suggestion);
  }

  void applySuggestion(PreparationSuggestion suggestion) {
    preparation = suggestion;
    if (suggestion.pages.isNotEmpty) {
      selected
        ..clear()
        ..addAll(suggestion.pages.map((p) => p.number));
    }
    if (start.text.trim().isEmpty && suggestion.start != null) {
      start.text = suggestion.start!;
    }
    if (end.text.trim().isEmpty && suggestion.end != null) {
      end.text = suggestion.end!;
    }
    if (period.text.trim().isEmpty && suggestion.periodLabel != null) {
      period.text = suggestion.periodLabel!;
    }
    if (unit == '不适用' && suggestion.unit != null) unit = suggestion.unit!;
    message = suggestion.pages.isEmpty
        ? '本次未定位到可用关键页，请搜索并人工选页'
        : '已建议 ${suggestion.pages.length} 页，保留完整表头与相邻页；可预览和调整';
  }

  List<String> get conflicts {
    final p = preparation;
    if (p == null) return [];
    final values = <String>[];
    for (final field in ['start', 'end', 'unit', 'scope']) {
      final suggestions = p.metadataEvidence
          .where((e) => e.field == field)
          .map((e) => e.value)
          .toSet();
      if (suggestions.length > 1) {
        values.add(
          '${preparationFieldLabel(field)}存在多个原文值：${suggestions.join('、')}，保持待处理',
        );
      }
    }
    if (p.start != null && start.text.isNotEmpty && start.text != p.start) {
      values.add('报告开始：当前 ${start.text}，正文建议 ${p.start}');
    }
    if (p.end != null && end.text.isNotEmpty && end.text != p.end) {
      values.add('报告结束：当前 ${end.text}，正文建议 ${p.end}');
    }
    if (p.unit != null && unit != '不适用' && unit != p.unit) {
      values.add('金额单位：当前 $unit，正文建议 ${p.unit}');
    }
    return values;
  }

  Future<void> prepare() async {
    if (busy || widget.service == null || report == null) return;
    final token = ++generation;
    final scope = report!.pages
        .where((p) => selected.contains(p.number))
        .toList();
    setState(() {
      busy = true;
      preparing = true;
      message = '正在建议选页和预填，最多一次模型请求';
    });
    try {
      final credentials = widget.store == null
          ? settings
          : await widget.store!.read();
      if (!mounted || token != generation) return;
      if (credentials.model != settings.model) {
        setState(() {
          settings = credentials;
          message = '本地模型已变更，请查看当前模型并再次主动确认发送范围；未发送请求';
        });
        return;
      }
      final result = await ReportPreparationService(widget.service!).prepare(
        key: credentials.key,
        model: credentials.model,
        company: '${widget.study.code} ${widget.study.name}',
        pages: scope,
      );
      if (!mounted || token != generation) return;
      setState(() {
        settings = credentials;
        applySuggestion(result);
      });
    } catch (e) {
      if (mounted && token == generation) {
        setState(
          () => message = e is ServiceFailure ? e.message : '准备请求失败，已保留人工输入及选页',
        );
      }
    } finally {
      if (mounted && token == generation) {
        setState(() {
          busy = false;
          preparing = false;
        });
      }
    }
  }

  Widget preparationSummary(int chars) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (coverageOnly) const Text('原 PDF 不可读取：仅处理已保存片段，无法定位片段之外的页面；可重新选择原文件。'),
      Text('发送范围：PDF 页序 ${(selected.toList()..sort()).join('、')} · $chars 字'),
      Text('模型：${settings.model} · 准备最多 1 次请求 · 按模型账户计费；不会自动追加请求'),
      Text('建议口径：${preparation?.scope ?? '待确认'} · 报告金额单位：$unit（逐表依据可展开）'),
      const Text('可展开下方页面预览完整发送文字。准备建议不代表财务值核验通过。'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: busy ? null : () => setState(applyLocal),
            child: const Text('本机建议选页（免费）'),
          ),
          FilledButton(
            onPressed:
                busy ||
                    widget.service == null ||
                    selected.isEmpty ||
                    selected.length > 25 ||
                    chars > 60000
                ? null
                : prepare,
            child: const Text('AI 选页与预填'),
          ),
          if (preparing)
            TextButton(
              onPressed: () => setState(() {
                generation++;
                busy = false;
                preparing = false;
                message = '已停止等待，迟到结果不会应用；已发请求可能已计费。';
              }),
              child: const Text('停止等待'),
            ),
        ],
      ),
      if (chars > 60000) const Text('模型最多 60000 字，请移除页面；不会静默截断表头或拆分付费请求。'),
      if (widget.store == null || settings.key.trim().isEmpty)
        const Text('未配置模型密钥时仍可使用本机建议与人工选页。'),
      if (preparation != null) ...[
        for (final warning in preparation!.warnings) Text(warning),
        for (final conflict in conflicts) Text('待处理：$conflict'),
        if (conflicts.isNotEmpty) const Text('保留当前输入，按原文更正后再保存；后续财务预核验另行检查。'),
        Wrap(
          spacing: 8,
          children: [
            if (preparation!.start != null && preparation!.end != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        start.text = preparation!.start!;
                        end.text = preparation!.end!;
                        period.text = preparation!.periodLabel!;
                        generation++;
                      }),
                child: const Text('采用正文建议期间'),
              ),
            if (preparation!.unit != null)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        unit = preparation!.unit!;
                        generation++;
                      }),
                child: const Text('采用正文建议单位'),
              ),
          ],
        ),
        ExpansionTile(
          title: const Text('选页、预填依据与逐表单位'),
          children: [
            for (final page in preparation!.pages)
              ListTile(
                title: Text('PDF 第 ${page.number} 页 · ${page.title}'),
                subtitle: Text(page.reason),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => PdfPageDialog(
                    importer: widget.importer,
                    pages: report!.pages,
                    initialPage: page.number,
                    bytes: coverageOnly ? null : report!.bytes,
                  ),
                ),
              ),
            for (final e in preparation!.metadataEvidence)
              ListTile(
                title: Text(
                  'PDF 第 ${e.page} 页 · ${preparationFieldLabel(e.field)}：${e.value}',
                ),
                subtitle: SelectableText(e.quote),
              ),
          ],
        ),
        Text(
          preparation!.usage == null
              ? '实际模型消耗：未知'
              : '实际模型消耗：${preparation!.usage}（服务返回）',
        ),
      ],
      const SizedBox(height: 12),
    ],
  );

  Widget field(
    String label,
    TextEditingController controller, {
    bool optional = false,
    bool readOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !busy,
      readOnly: readOnly,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {
        generation++;
      }),
      validator: (v) =>
          !optional && (v == null || v.trim().isEmpty) ? '请填写$label' : null,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final pages =
        report?.pages
            .where((p) => search.text.isEmpty || p.text.contains(search.text))
            .toList() ??
        [];
    final chars =
        report?.pages
            .where((p) => selected.contains(p.number))
            .fold<int>(0, (n, p) => n + p.text.length) ??
        0;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text('${widget.study.name} · 导入财报 PDF'),
        content: SizedBox(
          width: 800,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选择文字型 PDF，核对公司、期间、单位后保存需要的页。PDF 留在本机；备份携带选页原文和文件校验信息，原 PDF 需另行传输。不自动发送文件到模型。',
                  ),
                  const SizedBox(height: 12),
                  if (widget.initialReport == null)
                    OutlinedButton.icon(
                      onPressed: busy ? null : choose,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('选择 PDF 文件'),
                    ),
                  if (busy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(value: progress),
                    ),
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(message),
                    ),
                  if (report != null) ...[
                    Text(
                      '${report!.fileName} · ${(report!.bytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
                    ),
                    const SizedBox(height: 12),
                    preparationSummary(chars),
                    field('财报标题', title),
                    field(
                      '原始公告 HTTPS 网址（本地文件可留空）',
                      url,
                      optional: true,
                      readOnly: widget.announcement != null,
                    ),
                    if (widget.announcement != null) ...[
                      Text(
                        '公告证券：${widget.announcement!.companyName} · ${widget.announcement!.exchange} ${widget.announcement!.code}',
                      ),
                      Text(
                        widget.announcement!.isRevision
                            ? '修订公告：保留旧版本，新导入不会覆盖历史证据'
                            : '公告版本：原披露（请对照原文核验）',
                      ),
                      SelectableText('公告 ID：${widget.announcement!.id}'),
                      const SizedBox(height: 12),
                    ],
                    field('报告期名称（例如 2025 年度）', period),
                    field('报告开始日期 YYYY-MM-DD', start),
                    field('报告结束日期 YYYY-MM-DD', end),
                    field('披露日期 YYYY-MM-DD', disclosure),
                    DropdownButtonFormField<String>(
                      initialValue: unit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '选页原文金额单位'),
                      items: ['元', '万元', '亿元', '不适用']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              unit = v!;
                              generation++;
                            }),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: search,
                      decoration: const InputDecoration(
                        labelText: '查找页内文字（例如 合并现金流量表）',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '已选 ${selected.length} 页 · $chars 字（最多 25 页、240000 字）',
                    ),
                    for (final page in pages)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Checkbox(
                              value: selected.contains(page.number),
                              onChanged: busy || page.text.trim().isEmpty
                                  ? null
                                  : (v) => setState(() {
                                      if (v!) {
                                        selected.add(page.number);
                                      } else {
                                        selected.remove(page.number);
                                      }
                                      preparation = locateReportPages(
                                        '${widget.study.code} ${widget.study.name}',
                                        report!.pages
                                            .where(
                                              (p) =>
                                                  selected.contains(p.number),
                                            )
                                            .toList(),
                                      );
                                      generation++;
                                    }),
                            ),
                            Expanded(
                              child: Text(
                                'PDF 第 ${page.number} 页 · ${page.text.length} 字',
                              ),
                            ),
                          ],
                        ),
                        children: [
                          if (page.text.trim().isEmpty)
                            const Text('此页未提取到文字，不能加入 AI 原文'),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => showDialog<void>(
                                    context: context,
                                    builder: (_) => PdfPageDialog(
                                      importer: widget.importer,
                                      pages: report!.pages,
                                      initialPage: page.number,
                                      bytes: coverageOnly
                                          ? null
                                          : report!.bytes,
                                    ),
                                  ),
                            child: const Text('查看原页与提取文字'),
                          ),
                          SelectableText(page.text),
                        ],
                      ),
                    const Text('点击下方动作表示采用当前范围及报告信息并保存原文，不代表已逐页或逐项人工核验财务数字。'),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed:
                busy ||
                    selected.isEmpty ||
                    selected.length > 25 ||
                    chars > 240000
                ? null
                : save,
            child: const Text('采用范围并保存原文'),
          ),
        ],
      ),
    );
  }
}

class PdfPageDialog extends StatefulWidget {
  const PdfPageDialog({
    super.key,
    required this.importer,
    required this.pages,
    required this.initialPage,
    this.bytes,
    this.originalError,
  });
  final PdfImportService importer;
  final List<ReportPage> pages;
  final int initialPage;
  final Uint8List? bytes;
  final String? originalError;
  @override
  State<PdfPageDialog> createState() => _PdfPageDialogState();
}

class _PdfPageDialogState extends State<PdfPageDialog> {
  late int page = widget.initialPage;
  late bool original = widget.bytes != null;
  Future<Uint8List>? rendering;
  @override
  void initState() {
    super.initState();
    render();
  }

  void render() {
    if (widget.bytes != null) {
      rendering = widget.importer.renderPage(widget.bytes!, page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.pages.singleWhere((p) => p.number == page).text;
    return AlertDialog(
      title: const Text('核对财报原页'),
      content: SizedBox(
        width: 900,
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            DropdownButtonFormField<int>(
              initialValue: page,
              isExpanded: true,
              items: widget.pages
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.number,
                      child: Text('PDF 第 ${p.number} 页'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                page = v!;
                render();
              }),
            ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: widget.bytes == null
                      ? null
                      : () => setState(() => original = true),
                  child: const Text('原页'),
                ),
                TextButton(
                  onPressed: () => setState(() => original = false),
                  child: const Text('提取文字'),
                ),
              ],
            ),
            if (widget.bytes == null)
              Text(widget.originalError ?? '本机尚无原 PDF；已恢复选页原文。可重新选择同一文件关联。'),
            Expanded(
              child: original
                  ? FutureBuilder<Uint8List>(
                      future: rendering,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Center(child: Text('原页显示失败，可核对提取文字'));
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return InteractiveViewer(
                          minScale: .5,
                          maxScale: 5,
                          child: Image.memory(snapshot.data!),
                        );
                      },
                    )
                  : SingleChildScrollView(
                      child: SelectableText(text.isEmpty ? '未提取到文字' : text),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

Future<void> readReport(
  BuildContext context,
  ReportDocument document,
  ReportFileStore files,
  PdfImportService importer, {
  int? pageNumber,
}) async {
  Uint8List? bytes;
  String? originalError;
  try {
    bytes = await files.read(document.sha256);
  } catch (_) {
    originalError = '本机原 PDF 读取或校验失败；已保存选页原文仍可阅读。原文件已保留，请检查本地文件。';
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => PdfPageDialog(
      importer: importer,
      pages: document.pages,
      initialPage: pageNumber ?? document.pages.first.number,
      bytes: bytes,
      originalError: originalError,
    ),
  );
}
