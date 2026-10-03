import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'report_fetch.dart';
import 'report_import.dart';
import 'report_widgets.dart';
import 'reports.dart';
import 'services.dart';

/// Downloads stay in memory until the user reviews and saves selected PDF pages.
class ReportFetchDialog extends StatefulWidget {
  const ReportFetchDialog({
    super.key,
    required this.study,
    required this.exchange,
    required this.service,
    required this.importer,
    required this.existingDocuments,
    required this.save,
  });
  final Study study;
  final String exchange;
  final ReportFetchService service;
  final PdfImportService importer;
  final List<ReportDocument> existingDocuments;
  final Future<bool> Function(ReportDocument, Uint8List) save;

  @override
  State<ReportFetchDialog> createState() => _ReportFetchDialogState();
}

class _ReportFetchDialogState extends State<ReportFetchDialog> {
  ReportSearchResult? result;
  final selected = <String>{};
  final statuses = <String, String>{};
  final saved = <ReportDocument>[];
  int generation = 0;
  bool busy = false;
  String message = '', activity = '';
  double? progress;

  Iterable<ReportDocument> get documents => [
    ...widget.existingDocuments.where((d) => d.studyId == widget.study.id),
    ...saved,
  ];
  bool alreadyImported(ReportAnnouncement item) => documents.any(
    (d) => d.announcementId == item.id || d.url == item.url.toString(),
  );
  bool active(int token) => mounted && generation == token;

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  void close() {
    generation++;
    Navigator.pop(context, List<ReportDocument>.unmodifiable(saved));
  }

  void cancel() {
    generation++;
    setState(() {
      busy = false;
      activity = '';
      progress = null;
      message = '已停止本次操作；已保存 ${saved.length} 份财报。可以重新查询或重试未完成项。';
      for (final id in selected) {
        if (statuses[id] == '正在下载' || statuses[id] == '正在解析') {
          statuses[id] = '已停止，可重试';
        }
      }
    });
  }

  Future<void> search() async {
    final token = ++generation;
    setState(() {
      busy = true;
      result = null;
      selected.clear();
      statuses.clear();
      message = '';
      activity = '正在查询最近三年的年度报告';
      progress = null;
    });
    try {
      final found = await widget.service.search(
        widget.exchange,
        widget.study.code,
        years: 3,
      );
      if (!active(token)) return;
      if (found.code != widget.study.code ||
          found.exchange != widget.exchange ||
          found.reports.any(
            (r) => r.code != widget.study.code || r.exchange != widget.exchange,
          )) {
        throw ServiceFailure('返回的公告与当前研究卡代码不一致，请重新查询');
      }
      setState(() {
        result = found;
        message = found.reports.isEmpty ? '没有找到可下载的年度报告，可继续手动导入 PDF。' : '';
      });
    } on ServiceFailure catch (e) {
      if (active(token)) setState(() => message = e.message);
    } catch (_) {
      if (active(token)) setState(() => message = '财报查询失败，请稍后重试或手动导入 PDF。');
    } finally {
      if (active(token)) {
        setState(() {
          busy = false;
          activity = '';
          progress = null;
        });
      }
    }
  }

  Future<void> download(List<ReportAnnouncement> queue) async {
    if (queue.isEmpty || busy) return;
    final token = ++generation;
    setState(() {
      busy = true;
      message = '';
      progress = null;
    });
    for (final item in queue) {
      if (!active(token)) return;
      if (alreadyImported(item)) {
        setState(() {
          statuses[item.id] = '已导入，已跳过';
          selected.remove(item.id);
        });
        continue;
      }
      try {
        setState(() {
          activity = '${item.year} 年度 · 下载 PDF';
          statuses[item.id] = '正在下载';
          progress = null;
        });
        final bytes = await widget.service.download(
          item,
          progress: (done, total) {
            if (active(token)) {
              setState(
                () => progress = total == null || total <= 0
                    ? null
                    : (done / total).clamp(0.0, 1.0),
              );
            }
          },
        );
        if (!active(token)) return;
        setState(() {
          activity = '${item.year} 年度 · 读取原文';
          statuses[item.id] = '正在解析';
          progress = null;
        });
        final parsed = await widget.importer.parse(
          bytes,
          item.fileName,
          progress: (done, total) {
            if (active(token)) setState(() => progress = done / total);
          },
        );
        if (!active(token)) return;
        if (documents.any((d) => d.sha256 == parsed.hash)) {
          setState(() {
            statuses[item.id] = '原文件相同，已跳过';
            selected.remove(item.id);
          });
          continue;
        }
        setState(() {
          activity = '${item.year} 年度 · 等待选页与人工核对';
          statuses[item.id] = '等待核对';
          progress = 1;
        });
        if (!mounted) return;
        final document = await showDialog<ReportDocument>(
          context: context,
          barrierDismissible: false,
          builder: (_) => ReportImportDialog(
            study: widget.study,
            importer: widget.importer,
            existingHashes: documents.map((d) => d.sha256).toSet(),
            initialReport: parsed,
            announcement: item,
            save: (document, data) async {
              if (!active(token) ||
                  documents.any(
                    (d) =>
                        d.sha256 == document.sha256 ||
                        d.announcementId == item.id,
                  )) {
                return false;
              }
              final ok = await widget.save(document, data);
              // Record successful writes before the confirmation dialog closes.
              if (ok) saved.add(document);
              return ok;
            },
          ),
        );
        if (!active(token)) return;
        if (document == null) {
          setState(() {
            statuses[item.id] = '未确认保存，可重试';
            message = '已停止余下队列；已保存 ${saved.length} 份。当前 PDF 尚未导入。';
          });
          break;
        }
        setState(() {
          statuses[item.id] = '已保存';
          selected.remove(item.id);
        });
      } on ServiceFailure catch (e) {
        if (!active(token)) return;
        setState(() => statuses[item.id] = '失败：${e.message}');
      } catch (_) {
        if (!active(token)) return;
        setState(() => statuses[item.id] = '下载或解析失败，可重试');
      }
    }
    if (active(token)) {
      setState(() {
        busy = false;
        activity = '';
        progress = null;
        if (message.isEmpty) message = '本次操作结束，已保存 ${saved.length} 份；失败项可单独重试。';
      });
    }
  }

  String date(DateTime value) => value.toIso8601String().substring(0, 10);

  Widget announcement(ReportAnnouncement item) {
    final imported = alreadyImported(item);
    final status = statuses[item.id];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  key: ValueKey('select-report-${item.id}'),
                  value: selected.contains(item.id),
                  onChanged: busy || imported
                      ? null
                      : (v) => setState(() {
                          if (v!) {
                            selected.add(item.id);
                          } else {
                            selected.remove(item.id);
                          }
                        }),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
            Text('${item.companyName} · ${item.exchange}:${item.code}'),
            Text('报告期 ${date(item.start)} 至 ${date(item.end)}'),
            Text(
              '披露日期 ${date(item.disclosedAt)}${item.isRevision ? ' · 修订版，请核对差异' : ''}',
            ),
            const SizedBox(height: 6),
            const Text('巨潮资讯公告详情'),
            SelectableText(item.sourceUrl),
            const SizedBox(height: 4),
            const Text('PDF 来源'),
            SelectableText(item.url.toString()),
            if (imported || status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(status ?? '已导入当前研究卡'),
              ),
            if (!imported && !busy && status != null && status != '原文件相同，已跳过')
              TextButton.icon(
                key: ValueKey('retry-report-${item.id}'),
                onPressed: () => download([item]),
                icon: const Icon(Icons.refresh),
                label: const Text('重试此份'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<List<ReportDocument>>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: AlertDialog(
      title: const Text('自动获取年度财报'),
      content: SizedBox(
        width: 800,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前研究卡：${widget.study.name} · ${widget.exchange}:${widget.study.code}',
              ),
              const SizedBox(height: 8),
              const Text('查找最近三年年报。逐份选页并核对公司、期间和单位后保存；修订版需自行选择，下载不会自动发送至 AI。'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : search,
                icon: const Icon(Icons.search),
                label: const Text('查询近三年年报'),
              ),
              if (busy) ...[
                const SizedBox(height: 12),
                Text(activity),
                LinearProgressIndicator(value: progress),
              ],
              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(message),
                ),
              if (result != null) ...[
                const SizedBox(height: 12),
                Text(
                  '来源公司：${result!.companyName} · ${result!.exchange}:${result!.code}',
                ),
                if (result!.missingYears.isNotEmpty)
                  Text('缺少年度：${result!.missingYears.join('、')}；可稍后重试或手动补充。'),
                for (final warning in result!.warnings) Text('查询提示：$warning'),
                Text('已选 ${selected.length} 份 · 已保存 ${saved.length} 份'),
                for (final item in result!.reports) announcement(item),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: close,
          child: Text(saved.isEmpty ? '关闭' : '完成（已保存 ${saved.length} 份）'),
        ),
        if (busy) TextButton(onPressed: cancel, child: const Text('停止当前操作')),
        FilledButton(
          onPressed: busy || selected.isEmpty
              ? null
              : () => download(
                  result!.reports
                      .where((r) => selected.contains(r.id))
                      .toList(),
                ),
          child: const Text('下载并逐份核对'),
        ),
      ],
    ),
  );
}
