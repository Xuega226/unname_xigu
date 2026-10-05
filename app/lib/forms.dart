import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'domain.dart';

class InputField {
  const InputField(this.label, this.value,
      {this.numeric = false,
      this.multiline = false,
      this.optional = false,
      this.integer = false,
      this.date = false,
      this.signed = false,
      this.readOnly = false,
      this.readOnlyMessage = '公司已有资料关联，请为其他公司新建研究卡',
      this.max});
  final String label, value;
  final String readOnlyMessage;
  final bool numeric, multiline, optional, integer, date, signed, readOnly;
  final double? max;
  String? validate(String raw) {
    final value = raw.trim();
    if (readOnly) {
      return value == this.value.trim() ? null : readOnlyMessage;
    }
    if (value.isEmpty) return optional ? null : '请填写$label';
    if (numeric) {
      final number = double.tryParse(value);
      if (number == null || !number.isFinite || (!signed && number < 0)) {
        return signed ? '请输入有限数值' : '请输入非负的有限数值';
      }
      if (integer && number != number.truncateToDouble()) return '股数请输入整数';
      if (number.abs() > 1e12) return '数值过大，请核对单位';
      if (max != null && number > max!) return '不能超过 $max';
    }
    if (date) {
      final parsed = DateTime.tryParse(value);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != value) {
        return '请输入有效日期，如 2026-09-30';
      }
    }
    return null;
  }
}

class DataFormDialog extends StatefulWidget {
  const DataFormDialog(
      {super.key,
      required this.title,
      required this.fields,
      required this.note});
  final String title, note;
  final List<InputField> fields;
  @override
  State<DataFormDialog> createState() => _DataFormDialogState();
}

class _DataFormDialogState extends State<DataFormDialog> {
  final key = GlobalKey<FormState>();
  late final controllers =
      widget.fields.map((f) => TextEditingController(text: f.value)).toList();
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                  child: Form(
                      key: key,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.note),
                        const SizedBox(height: 20),
                        for (var i = 0; i < widget.fields.length; i++)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: TextFormField(
                                  controller: controllers[i],
                                  readOnly: widget.fields[i].readOnly,
                                  decoration: InputDecoration(
                                      labelText: widget.fields[i].label),
                                  minLines: widget.fields[i].multiline ? 3 : 1,
                                  maxLines: widget.fields[i].multiline ? 6 : 1,
                                  keyboardType: widget.fields[i].numeric
                                      ? TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: widget.fields[i].signed)
                                      : widget.fields[i].multiline
                                          ? TextInputType.multiline
                                          : TextInputType.text,
                                  validator: (value) =>
                                      widget.fields[i].validate(value ?? ''))),
                      ])))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: () {
                  if (key.currentState!.validate()) {
                    Navigator.pop(context,
                        controllers.map((v) => v.text.trim()).toList());
                  }
                },
                child: const Text('保存'))
          ]);
}

class BackupDialog extends StatefulWidget {
  const BackupDialog(
      {super.key,
      required this.data,
      required this.importing,
      required this.onCopied});
  final WorkspaceData data;
  final bool importing;
  final VoidCallback onCopied;
  @override
  State<BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<BackupDialog> {
  late final controller =
      TextEditingController(text: widget.importing ? '' : widget.data.encode());
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.importing ? '导入备份' : '导出备份'),
          content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.importing
                    ? '粘贴另一端导出的 JSON。导入会替换当前工作区，包括研究、持仓、量化参数、历史行情和资金流水，建议先备份。'
                    : '复制 JSON 后保存到文本文件，或在另一端粘贴导入。备份包含研究、持仓、量化参数、历史行情和资金流水，请自行妥善保存。'),
                const SizedBox(height: 16),
                TextField(
                    controller: controller,
                    readOnly: !widget.importing,
                    minLines: 8,
                    maxLines: 14,
                    decoration: InputDecoration(
                        border: const OutlineInputBorder(), errorText: error)),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭')),
            if (!widget.importing)
              FilledButton(
                  onPressed: () async {
                    try {
                      await Clipboard.setData(
                          ClipboardData(text: controller.text));
                      widget.onCopied();
                    } catch (e) {
                      if (mounted) setState(() => error = '复制失败：$e');
                    }
                  },
                  child: const Text('复制备份')),
            if (widget.importing)
              FilledButton(
                  onPressed: () {
                    try {
                      if (controller.text.length > 8000000) {
                        throw const FormatException('备份过大，最多支持 800 万字符');
                      }
                      final parsed = WorkspaceData.decode(controller.text);
                      Navigator.pop(context, parsed);
                    } catch (e) {
                      setState(() => error = '导入未应用：$e');
                    }
                  },
                  child: const Text('检查并导入')),
          ]);
}
