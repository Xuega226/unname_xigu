import 'package:flutter/material.dart';

import 'domain.dart';
import 'forms.dart';
import 'research.dart';

String reviewDueLabel(Study study) {
  if (study.nextReviewAt.isEmpty) return '未设置下次复查';
  final comparison = study.nextReviewAt.compareTo(dateToday());
  if (comparison < 0) return '复查已到期 · ${study.nextReviewAt}';
  if (comparison == 0) return '今日应复查';
  return '下次复查 · ${study.nextReviewAt}';
}

class ReviewPlanDialog extends StatefulWidget {
  const ReviewPlanDialog({
    super.key,
    required this.study,
    required this.sources,
  });
  final Study study;
  final List<SourceExcerpt> sources;
  @override
  State<ReviewPlanDialog> createState() => _ReviewPlanDialogState();
}

class _ReviewPlanDialogState extends State<ReviewPlanDialog> {
  late final date = TextEditingController(text: widget.study.nextReviewAt);
  late final tasks = [...widget.study.reviewTasks];
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    date.dispose();
    super.dispose();
  }

  Future<void> task([ReviewTask? old]) async {
    final result = await showDialog<ReviewTask>(
      context: context,
      builder: (_) => ReviewTaskDialog(task: old, sources: widget.sources),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (old == null) {
        tasks.add(result);
      } else {
        tasks[tasks.indexWhere((t) => t.id == old.id)] = result;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.study.name} · 复查计划'),
    content: SizedBox(
      width: 740,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('维护需要验证的经营假设，记录证据与核验状态。保存会保留编辑前的研究快照；到期时在应用内展示。'),
              const SizedBox(height: 16),
              TextFormField(
                controller: date,
                decoration: const InputDecoration(
                  labelText: '下次复查日期 YYYY-MM-DD（留空取消计划）',
                ),
                validator: (v) => InputField(
                  '复查日期',
                  '',
                  date: true,
                  optional: true,
                ).validate(v ?? ''),
              ),
              const SizedBox(height: 16),
              if (widget.study.reviewCondition.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('查看研究卡的复查条件'),
                  children: [SelectableText(widget.study.reviewCondition)],
                ),
              if (tasks.isEmpty) const Text('尚无待验证清单，可把研究卡中的关键条件逐项加入。'),
              for (final t in tasks)
                Card(
                  child: ListTile(
                    title: Text(t.text),
                    subtitle: Text(
                      '${t.status}\n${t.note}${t.sourceIds.isEmpty ? '' : '\n来源 ${t.sourceIds.join('、')}'}',
                    ),
                    trailing: IconButton(
                      tooltip: '核验复查项',
                      onPressed: () => task(t),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: tasks.length >= 30 ? null : () => task(),
                icon: const Icon(Icons.add),
                label: const Text('添加待验证条件'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              widget.study.copyWith(
                nextReviewAt: date.text.trim(),
                reviewTasks: tasks,
                updatedAt: dateToday(),
              ),
            );
          }
        },
        child: const Text('保存复查计划'),
      ),
    ],
  );
}

class ReviewTaskDialog extends StatefulWidget {
  const ReviewTaskDialog({super.key, required this.sources, this.task});
  final ReviewTask? task;
  final List<SourceExcerpt> sources;
  @override
  State<ReviewTaskDialog> createState() => _ReviewTaskDialogState();
}

class _ReviewTaskDialogState extends State<ReviewTaskDialog> {
  late final text = TextEditingController(text: widget.task?.text ?? '');
  late final note = TextEditingController(text: widget.task?.note ?? '');
  late String status = widget.task?.status ?? '待验证';
  late final ids = <String>{...?widget.task?.sourceIds};
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    text.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('待验证条件与证据'),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: text,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '具体要验证的条件'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请填写具体条件' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '人工核验状态'),
                items: ReviewTask.statuses
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => status = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '新证据、反面证据与判断依据'),
                validator: (v) =>
                    ['成立', '不成立'].contains(status) &&
                        (v == null || v.trim().isEmpty)
                    ? '确认成立或不成立时，请记录判断依据'
                    : null,
              ),
              const SizedBox(height: 12),
              const Text('可关联本公司的原文片段，状态由你判断，应用不自动认定条件成立。'),
              for (final s in widget.sources)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: ids.contains(s.id),
                    title: Text('${s.title} · ${s.page}'),
                    onChanged: (v) => setState(() {
                      if (v!) {
                        ids.add(s.id);
                      } else {
                        ids.remove(s.id);
                      }
                    }),
                  ),
                  children: [SelectableText(s.text)],
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (!form.currentState!.validate()) return;
          Navigator.pop(
            context,
            ReviewTask(
              id: widget.task?.id ?? newId(),
              text: text.text.trim(),
              status: status,
              note: note.text.trim(),
              sourceIds: ids.toList(),
            ),
          );
        },
        child: const Text('保存此条件'),
      ),
    ],
  );
}

class StudyHistoryDialog extends StatefulWidget {
  const StudyHistoryDialog({
    super.key,
    required this.study,
    required this.versions,
  });
  final Study study;
  final List<StudyVersion> versions;
  @override
  State<StudyHistoryDialog> createState() => _StudyHistoryDialogState();
}

class _StudyHistoryDialogState extends State<StudyHistoryDialog> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final versions = widget.versions.reversed.toList();
    selected ??= versions.firstOrNull?.id;
    final before = versions.where((v) => v.id == selected).firstOrNull?.study;
    Map<String, String> fields(Study s) => {
      '主营业务与财务事实': s.business,
      '一年投资假设': s.thesis,
      '反面证据': s.counterEvidence,
      '复查条件': s.reviewCondition,
      '出处': s.source,
      '下次复查日期': s.nextReviewAt,
      '待验证清单': s.reviewTasks
          .map(
            (t) =>
                '${t.text} · ${t.status}\n${t.note}\n${t.sourceIds.join('、')}',
          )
          .join('\n\n'),
    };
    final old = before == null ? <String, String>{} : fields(before),
        current = fields(widget.study);
    final changes = current.keys.where((k) => old[k] != current[k]).toList();
    return AlertDialog(
      title: Text('${widget.study.name} · 研究版本对照'),
      content: SizedBox(
        width: 1000,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (versions.isEmpty)
                const Text('尚无第三轮之后的历史快照。旧版保存的编辑记录仍可在复查日志查看。'),
              if (versions.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '选择编辑前的历史版本'),
                  items: versions
                      .map(
                        (v) => DropdownMenuItem(
                          value: v.id,
                          child: Text(
                            '${v.createdAt.substring(0, v.createdAt.length.clamp(0, 16))} · ${v.reason}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => selected = v),
                ),
                const SizedBox(height: 16),
                if (changes.isEmpty) const Text('所选版本与当前研究内容相同'),
                for (final key in changes) ...[
                  Text(
                    key,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      Widget value(String label, String text) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(text.isEmpty ? '未录入' : text),
                            ],
                          ),
                        ),
                      );
                      if (constraints.maxWidth < 600) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            value('历史版本', old[key] ?? ''),
                            value('当前版本', current[key]!),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: value('历史版本', old[key] ?? '')),
                          Expanded(child: value('当前版本', current[key]!)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ],
          ),
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
