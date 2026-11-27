import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../common/api/api_client.dart';
import '../../common/format/date_time.dart';
import '../../common/theme/app_theme.dart';
import 'care_checklist_repository.dart';

/// Mở hộp thoại "Ghi nhận kết quả" (Figma 186:1703) cho [task]; `true` khi đã lưu. [reRecord]: "Ghi nhận lại" kết quả
/// đã ghi trong ca (Q-446), gửi bản đính chính kèm lý do bắt buộc.
Future<bool?> showCareResultDialog(
  BuildContext context, {
  required Map<String, dynamic> task,
  required CareChecklistRepository repository,
  required String Function() newKey,
  List<Map<String, dynamic>> resultValues = const [],
  bool quickCompletion = false,
  bool reRecord = false,
}) => showDialog<bool>(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    clipBehavior: Clip.antiAlias,
    child: CareResultForm(
      task: task,
      repository: repository,
      newKey: newKey,
      resultValues: resultValues,
      dialog: true,
      quickCompletion: quickCompletion,
      reRecord: reRecord,
    ),
  ),
);

/// Form ghi nhận kết quả của một công việc. Backend lấy giờ lúc nhận lệnh.
/// Khi đánh dấu một việc đã hoàn thành trước đó, nhân viên nhập giờ thực tế.
class CareResultForm extends StatefulWidget {
  const CareResultForm({
    super.key,
    required this.task,
    this.repository,
    required this.newKey,
    this.resultValues = const [],
    this.onRecord,
    this.commandContext = '',
    this.dialog = false,
    this.quickCompletion = false,
    this.reRecord = false,
  }) : assert(!quickCompletion || !reRecord);
  final Map<String, dynamic> task;
  final CareChecklistRepository? repository;
  final Future<void> Function(Map<String, dynamic> body, String key)? onRecord;
  final String commandContext;
  final String Function() newKey;
  final List<Map<String, dynamic>> resultValues;

  /// Trong hộp thoại: tiêu đề lớn có nút đóng; nằm trong màn khác thì tiêu đề thường, không nút đóng.
  final bool dialog;
  final bool quickCompletion;

  /// Q-446: ghi nhận lại kết quả đã ghi (đính chính): lý do bắt buộc, không gửi thời điểm thực hiện, lý do trễ.
  final bool reRecord;
  @override
  State<CareResultForm> createState() => _CareResultFormState();
}

class _CareResultFormState extends State<CareResultForm> {
  final numeric = TextEditingController(),
      note = TextEditingController(),
      reason = TextEditingController(),
      behavior = TextEditingController(),
      performed = TextEditingController();
  String? code, occurred, error, signature, retryKey;
  bool busy = false, needsConfirmation = false, confirmed = false, completedEarlier = false;
  bool get needsPerformedAt => widget.quickCompletion && completedEarlier;
  static const labels = {
    'ML': 'Lượng nước (ml)',
    'ITEM_QUANTITY': 'Số lượng',
    'MEASURED_VALUE': 'Giá trị đo',
    'SLEEP': 'Thời gian ngủ (phút)',
  };
  Map<String, String> codes(String type) =>
      choices[type] ??
      {
        for (final row in widget.resultValues.where(
          (r) =>
              r['status'] == 'ACTIVE' &&
              r['type'] == const {'SLEEP': 'SLEEP_QUALITY', 'MOOD': 'MOOD', 'BEHAVIOR': 'BEHAVIOR'}[type],
        ))
          row['code'] as String: row['name'] as String,
      };
  bool needsCode(String type) =>
      choices.containsKey(type) || ['SLEEP', 'MOOD'].contains(type) || (type == 'BEHAVIOR' && occurred == 'yes');
  static const choices = {
    'EATING': {
      'ATE_ALL': 'Ăn hết',
      'MOST': 'Phần lớn',
      'SOME': 'Một phần',
      'NOT_EATEN': 'Không ăn',
      'SKIPPED': 'Bỏ bữa',
    },
    'MOVEMENT': {'INDEPENDENT': 'Tự thực hiện', 'ASSISTED': 'Cần hỗ trợ', 'UNABLE': 'Không thực hiện được'},
  };
  @override
  void dispose() {
    numeric.dispose();
    note.dispose();
    reason.dispose();
    behavior.dispose();
    performed.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final type = widget.task['resultType'] as String;
    final value = num.tryParse(numeric.text);
    DateTime? performedAt;
    if (needsPerformedAt) {
      final text = performed.text.trim();
      if (text.isEmpty) {
        setState(() => error = 'Nhập thời điểm thực tế đã thực hiện.');
        return;
      }
      final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4}) (\d{2}):(\d{2})$').firstMatch(text);
      performedAt = match == null
          ? null
          : DateTime.tryParse('${match[3]}-${match[2]}-${match[1]}T${match[4]}:${match[5]}:00+07:00');
      if (performedAt == null || formatDateTime(performedAt) != text) {
        setState(() => error = 'Nhập ngày giờ hợp lệ dạng dd/MM/yyyy HH:mm.');
        return;
      }
      final from = DateTime.tryParse(widget.task['windowFrom'] as String? ?? '');
      if (performedAt.isAfter(DateTime.now()) || (from != null && performedAt.isBefore(from))) {
        setState(() => error = 'Nhập giờ từ đầu khung thực hiện đến thời điểm hiện tại.');
        return;
      }
    }
    if ((labels.containsKey(type) && (value == null || !value.isFinite)) ||
        (needsCode(type) && code == null) ||
        (type == 'BEHAVIOR' && (occurred == null || (occurred == 'yes' && behavior.text.trim().isEmpty)))) {
      setState(() => error = 'Nhập đầy đủ kết quả trước khi lưu.');
      return;
    }
    if (widget.reRecord && reason.text.trim().isEmpty) {
      setState(() => error = 'Nhập lý do ghi nhận lại.');
      return;
    }
    final body = <String, dynamic>{
      if (labels.containsKey(type)) 'numericValue': value,
      if (needsCode(type) && type != 'BEHAVIOR') 'codeValue': code,
      if (type == 'BEHAVIOR')
        'jsonValue': {
          'occurred': occurred == 'yes',
          if (occurred == 'yes') ...{'behaviorCode': code, 'description': behavior.text},
        },
      if (note.text.isNotEmpty) 'note': note.text,
      if (reason.text.isNotEmpty && !widget.reRecord) 'reason': reason.text,
      if (confirmed) 'upperLimitConfirmed': true,
      if (performedAt != null) 'performedAt': performedAt.toUtc().toIso8601String(),
    };
    final nextSignature = jsonEncode({'body': body, 'context': widget.commandContext, 'reason': reason.text});
    if (signature != nextSignature) {
      signature = nextSignature;
      retryKey = widget.newKey();
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.reRecord) {
        await widget.repository!.reRecord(widget.task['id'] as int, body, reason.text.trim(), retryKey!);
        if (mounted) Navigator.pop(context, true);
      } else if (widget.onRecord != null) {
        await widget.onRecord!(body, retryKey!);
      } else {
        await widget.repository!.record(widget.task['id'] as int, body, retryKey!);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is ApiProblem ? e.detail : 'Chưa gửi được. Giữ nguyên nội dung để thử lại.';
          needsConfirmation = e is ApiProblem && e.errorCode == 'CONFIRMATION_REQUIRED';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = widget.task['resultType'] as String;
    final supported =
        labels.containsKey(type) || choices.containsKey(type) || ['PERFORMED', 'MOOD', 'BEHAVIOR'].contains(type);
    final (title, submitLabel) = switch ((widget.quickCompletion, widget.reRecord)) {
      (true, _) => ('Đánh dấu hoàn thành', 'Xác nhận hoàn thành'),
      (_, true) => ('Ghi nhận lại', 'Lưu ghi nhận lại'),
      _ => ('Ghi nhận kết quả', 'Lưu kết quả'),
    };
    Widget field(String label, Widget input) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          input,
        ],
      ),
    );
    Widget radios(String? value, ValueChanged<String?> onChanged, Map<String, String> entries) => RadioGroup<String>(
      groupValue: value,
      onChanged: (v) {
        if (!busy) onChanged(v);
      },
      child: Column(
        children: [
          for (final entry in entries.entries)
            RadioListTile<String>(
              value: entry.key,
              title: Text(entry.value),
              enabled: !busy,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: widget.dialog ? 9 : 0),
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: (widget.dialog ? theme.textTheme.headlineSmall : theme.textTheme.titleLarge)?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.dialog)
              IconButton(
                tooltip: 'Đóng',
                onPressed: busy ? null : () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHighest,
                  fixedSize: const Size.square(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: Icon(LucideIcons.x, size: 20, color: scheme.primary),
              ),
          ],
        ),
        if (!supported)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('Chưa có danh mục kết quả để ghi nhận loại công việc này.'),
          ),
        if (labels[type] case final label?)
          field(
            label,
            TextField(
              key: const ValueKey('careResult.numeric'),
              controller: numeric,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => confirmed = false),
              decoration: const InputDecoration(hintText: 'Nhập số'),
            ),
          ),
        if (type == 'BEHAVIOR')
          field(
            'Hành vi',
            radios(
              occurred,
              (v) => setState(() {
                occurred = v;
                code = null;
              }),
              const {'no': 'Không có hành vi bất thường', 'yes': 'Có hành vi bất thường'},
            ),
          ),
        if (needsCode(type)) field('Kết quả', radios(code, (v) => setState(() => code = v), codes(type))),
        if (type == 'BEHAVIOR' && occurred == 'yes')
          field(
            'Mô tả hành vi (bắt buộc)',
            TextField(
              key: const ValueKey('careResult.behavior'),
              controller: behavior,
              enabled: !busy,
              maxLength: 2000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Nhập mô tả'),
            ),
          ),
        if (supported) ...[
          if (widget.quickCompletion)
            RadioGroup<bool>(
              groupValue: completedEarlier,
              onChanged: (value) {
                if (!busy) {
                  setState(() {
                    completedEarlier = value ?? false;
                    error = null;
                  });
                }
              },
              child: Column(
                children: [
                  RadioListTile<bool>(value: false, enabled: !busy, title: const Text('Vừa hoàn thành')),
                  RadioListTile<bool>(value: true, enabled: !busy, title: const Text('Đã hoàn thành trước đó')),
                ],
              ),
            ),
          if (needsPerformedAt)
            TextField(
              controller: performed,
              enabled: !busy,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(labelText: 'Thời điểm thực hiện (dd/MM/yyyy HH:mm)'),
            ),
          field(
            'Ghi chú kết quả',
            TextField(
              key: const ValueKey('careResult.note'),
              controller: note,
              enabled: !busy,
              maxLength: 2000,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(hintText: 'Nhập ghi chú'),
            ),
          ),
          if (widget.reRecord || ['IMPORTANT', 'MANDATORY'].contains(widget.task['importance']))
            field(
              widget.reRecord ? 'Lý do ghi nhận lại (bắt buộc)' : 'Lý do hoàn thành trễ (nếu có)',
              TextField(
                key: const ValueKey('careResult.reason'),
                controller: reason,
                enabled: !busy,
                maxLength: 2000,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'Nhập lý do'),
              ),
            ),
          if (needsConfirmation)
            CheckboxListTile(
              value: confirmed,
              contentPadding: EdgeInsets.zero,
              onChanged: busy ? null : (v) => setState(() => confirmed = v ?? false),
              title: const Text('Xác nhận giá trị đã nhập vượt giới hạn hợp lý'),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(error!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error)),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.menu)),
              ),
              onPressed: busy ? null : save,
              child: Text(busy ? 'Đang lưu…' : submitLabel),
            ),
          ),
        ],
      ],
    );
    return PopScope(
      canPop: !busy,
      child: widget.dialog
          ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 20), child: content)
          : Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: content),
    );
  }
}
