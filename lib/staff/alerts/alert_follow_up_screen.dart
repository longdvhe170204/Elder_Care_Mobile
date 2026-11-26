import 'dart:math';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';
import '../../common/widgets/page_body.dart';
import 'alert_labels.dart';

/// Mã cảnh báo đang mở của một người cao tuổi từ `openAlerts` của checklist (005 FR-057, Q-419).
List<int> followingAlertIds(List<dynamic>? openAlerts, Object? residentId) {
  if (residentId == null || openAlerts == null) return const [];
  return [
    for (final a in openAlerts.cast<Map<String, dynamic>>())
      if (a['residentId'] == residentId && a['id'] is num) (a['id'] as num).toInt(),
  ];
}

/// "Theo dõi cảnh báo" mở từ nhãn "Đang theo dõi" trên checklist (005 FR-057; 007 FR-087, Q-419): các lần theo dõi và ô
/// ghi kết quả theo dõi cho từng cảnh báo đang mở của người cao tuổi; chỉ có ô ghi khi backend trả lệnh `follow-up`.
/// Ghi theo dõi không đổi trạng thái cảnh báo, không tạo công việc. Cùng chữ với web `alerts/AlertFollowUps.jsx`.
class AlertFollowUpScreen extends StatefulWidget {
  const AlertFollowUpScreen({super.key, required this.api, required this.alertIds});

  final ApiClient api;
  final List<int> alertIds;

  @override
  State<AlertFollowUpScreen> createState() => _AlertFollowUpScreenState();
}

class _AlertFollowUpScreenState extends State<AlertFollowUpScreen> {
  final _alerts = <int, Map<String, dynamic>>{};
  final _inputs = <int, TextEditingController>{};
  final _keys = <int, String>{};
  final _errors = <int, String>{};
  String? _loadError;
  bool _loading = true;
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      for (final id in widget.alertIds) {
        final alert = await widget.api.get('/alerts/$id');
        if (alert != null) _alerts[id] = alert;
      }
      if (mounted) setState(() => _loading = false);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = backendMessage(e);
        });
      }
    }
  }

  String _newKey() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _save(int id) async {
    final value = _inputs[id]!.text.trim();
    if (value.isEmpty) {
      setState(() => _errors[id] = 'Nhập kết quả theo dõi.');
      return;
    }
    setState(() {
      _busy = id;
      _errors.remove(id);
    });
    try {
      await widget.api.post(
        '/alerts/$id/follow-ups',
        {'content': value},
        headers: {'Idempotency-Key': _keys.putIfAbsent(id, _newKey)},
      );
      _keys.remove(id);
      _inputs[id]!.clear();
      final fresh = await widget.api.get('/alerts/$id');
      if (mounted) setState(() => _alerts[id] = fresh ?? _alerts[id]!);
    } on ApiUnreachable {
      if (mounted) setState(() => _errors[id] = 'Mất kết nối, chưa lưu. Thử lại khi có mạng.');
    } on Exception catch (e) {
      if (mounted) setState(() => _errors[id] = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_loading) return const PageBody(child: Center(child: CircularProgressIndicator()));
    if (_loadError != null) return PageBody(child: Text(_loadError!, style: text.bodyLarge));
    return PageBody(
      child: ListView(
        children: [
          for (final id in widget.alertIds)
            if (_alerts[id] case final a?) ...[
              Text('Đang theo dõi: ${alertTypeName(a['type'] as String?)}', style: text.titleMedium),
              const SizedBox(height: 4),
              if (((a['followUps'] as List?) ?? const []).isEmpty)
                Text('Chưa có lần theo dõi nào.', style: text.bodyMedium),
              for (final f in ((a['followUps'] as List?) ?? const []).cast<Map<String, dynamic>>())
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${f['at'] is String ? formatDateTime(DateTime.parse(f['at'] as String)) : ''}'
                    '${f['recordedBy'] != null ? ', ${f['recordedBy']}' : ''}: ${f['content']}',
                    style: text.bodyMedium,
                  ),
                ),
              if (((a['allowedCommands'] as List?) ?? const []).contains('follow-up')) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _inputs.putIfAbsent(id, TextEditingController.new),
                  maxLines: 2,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: 'Ghi kết quả theo dõi', errorText: _errors[id]),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: _busy == null ? () => _save(id) : null,
                    child: const Text('Lưu theo dõi'),
                  ),
                ),
              ] else if (_errors[id] != null)
                Text(_errors[id]!, style: text.bodyMedium),
              const Divider(height: 32),
            ],
        ],
      ),
    );
  }
}
