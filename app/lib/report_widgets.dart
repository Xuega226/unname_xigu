import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'report_import.dart';
import 'reports.dart';
import 'services.dart';

class ReportImportDialog extends StatefulWidget {
  const ReportImportDialog({
    super.key,
    required this.study,
    required this.importer,
    required this.existingHashes,
    required this.save,
  });
  final Study study;
  final PdfImportService importer;
  final Set<String> existingHashes;
  final Future<bool> Function(ReportDocument, Uint8List) save;
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
  String unit = '元', message = '';
  bool busy = false, confirmed = false;
  double? progress;
  @override
  void dispose() {
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
        if (widget.existingHashes.contains(result.hash)) {
          throw ServiceFailure('这份 PDF 已导入当前研究卡');
        }
        setState(() {
          report = result;
          selected.clear();
          confirmed = false;
          title.text = result.fileName.replaceFirst(
            RegExp(r'\.pdf$', caseSensitive: false),
            '',
          );
          message = '读取 ${result.pages.length} 页，请选择需要核验的原文页';
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
        !confirmed ||
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
        'pageCount': report!.pages.length,
        'pages': report!.pages
            .where((p) => selected.contains(p.number))
            .map((p) => p.toJson())
            .toList(),
      });
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

  Widget field(
    String label,
    TextEditingController controller, {
    bool optional = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !busy,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() => confirmed = false),
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
    return AlertDialog(
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
                  field('财报标题', title),
                  field('原始公告 HTTPS 网址（本地文件可留空）', url, optional: true),
                  field('报告期名称（例如 2025 年度）', period),
                  field('报告开始日期 YYYY-MM-DD', start),
                  field('报告结束日期 YYYY-MM-DD', end),
                  field('披露日期 YYYY-MM-DD', disclosure),
                  DropdownButtonFormField<String>(
                    initialValue: unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '选页原文金额单位'),
                    items: ['元', '万元', '亿元', '不适用']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() {
                            unit = v!;
                            confirmed = false;
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
                  Text('已选 ${selected.length} 页 · $chars 字（最多 25 页、240000 字）'),
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
                                    confirmed = false;
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
                                    bytes: report!.bytes,
                                  ),
                                ),
                          child: const Text('查看原页与提取文字'),
                        ),
                        SelectableText(page.text),
                      ],
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => confirmed = v!),
                    title: const Text('我已核对公司、报告期、披露日期、原文页和金额单位'),
                  ),
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
                  !confirmed ||
                  selected.isEmpty ||
                  selected.length > 25 ||
                  chars > 240000
              ? null
              : save,
          child: const Text('保存选页与原文件'),
        ),
      ],
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
  });
  final PdfImportService importer;
  final List<ReportPage> pages;
  final int initialPage;
  final Uint8List? bytes;
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
              const Text('本机尚无原 PDF；已恢复选页原文。可重新选择同一文件关联。'),
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
  try {
    bytes = await files.read(document.sha256);
  } catch (_) {
    /* Original text remains available. */
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => PdfPageDialog(
      importer: importer,
      pages: document.pages,
      initialPage: pageNumber ?? document.pages.first.number,
      bytes: bytes,
    ),
  );
}
