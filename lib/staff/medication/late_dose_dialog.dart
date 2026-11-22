import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';
import 'medication_labels.dart';
import 'medication_round_repository.dart';

/// Ghi "đã dùng muộn" cho liều đã Bỏ lỡ (BR-M07-26, Q-327): Bỏ lỡ vẫn là bản ghi cuối của lịch sử, hệ thống tạo bản đính
/// chính kèm giờ dùng thực tế và lý do (api-000). Người đính chính là người ghi gốc hoặc Người phụ trách ca. Trả câu báo
/// kết quả khi đã gửi, null khi hủy. Lệnh trực tuyến, gửi `Idempotency-Key`.
Future<String?> showLateDoseDialog(
  BuildContext context, {
  required MedicationRoundRepository repository,
  required Map<String, dynamic> item,
  required String Function() newKey,
  required DateTime Function() clock,
}) => showDialog<String>(
  context: context,
  builder: (_) => _LateDoseDialog(repository: repository, item: item, key0: newKey(), now: clock()),
);

class _LateDoseDialog extends StatefulWidget {
  const _LateDoseDialog({required this.repository, required this.item, required this.key0, required this.now});
  final MedicationRoundRepository repository;
  final Map<String, dynamic> item;
  final String key0;
  final DateTime now;

  @override
  State<_LateDoseDialog> createState() => _LateDoseDialogState();
}

class _LateDoseDialogState extends State<_LateDoseDialog> {
  late final time = TextEditingController(text: formatDateTime(widget.now));
  final reason = TextEditingController();
  bool submitted = false;
  bool busy = false;
  String? error;

  DateTime? get at => parseVnDateTime(time.text);

  Future<void> save() async {
    setState(() => submitted = true);
    final when = at;
    if (when == null || when.isAfter(widget.now) || reason.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.correctLate(widget.item, when, reason.text.trim(), widget.key0);
      if (mounted) Navigator.pop(context, 'Đã ghi ${doseLine(widget.item)} đã dùng muộn.');
    } on ApiUnreachable {
      if (mounted) {
        setState(() {
          error = 'Ghi đã dùng muộn cần có mạng. Thử lại khi có kết nối.';
          busy = false;
        });
      }
    } on ApiProblem catch (problem) {
      if (mounted) {
        setState(() {
          error = backendMessage(problem);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final when = at;
    final timeError = submitted && (when == null || when.isAfter(widget.now))
        ? 'Nhập theo dạng dd/MM/yyyy HH:mm, không sau hiện tại.'
        : null;
    return AlertDialog(
      title: const Text('Ghi đã dùng muộn'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${doseLine(widget.item)}. Liều đã Bỏ lỡ; bản ghi Bỏ lỡ vẫn giữ trong lịch sử.'),
            TextField(
              controller: time,
              enabled: !busy,
              decoration: InputDecoration(labelText: 'Giờ dùng thực tế', errorText: timeError),
            ),
            TextField(
              controller: reason,
              enabled: !busy,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: 'Lý do đính chính (bắt buộc)',
                errorText: submitted && reason.text.trim().isEmpty ? 'Nhập lý do.' : null,
              ),
            ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Hủy')),
        FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Đang lưu…' : 'Ghi đã dùng muộn')),
      ],
    );
  }
}
