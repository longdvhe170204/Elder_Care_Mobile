import 'dart:math';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/theme/app_theme.dart';

const _rightLabels = {
  'VIEW_HEALTH': 'Xem sức khỏe',
  'VIEW_COSTS': 'Xem chi phí',
  'RECEIVE_URGENT': 'Nhận thông báo khẩn',
  'REGISTER_VISITS': 'Đăng ký thăm',
  'PICKUP_ALLOWED': 'Được phép đón',
  'REQUEST_SERVICES': 'Được yêu cầu thay đổi dịch vụ',
};

/// Câu nội dung yêu cầu, cùng cách viết với màn web (012 T017). Hợp đồng không trả tên người thân bị tác động nên ghi
/// "người thân", trừ người đón mới có họ tên trong yêu cầu.
String describeRightChangeRequest(Map<String, dynamic> request) {
  final picker = (request['newPicker'] as Map<String, dynamic>?)?['fullName'] as String?;
  final person = picker ?? 'người thân';
  final value = request['newValue'] == true ? 'Bật' : 'Tắt';
  return switch (request['type']) {
    'RIGHT' => '$value quyền ${_rightLabels[request['right']] ?? request['right']} cho $person',
    'SELF_RETURN' => '$value dấu được tự về',
    'SET_REPRESENTATIVE' => 'Đặt thêm người đại diện',
    'REMOVE_REPRESENTATIVE' => 'Thôi một người đại diện',
    _ => '${request['type']}',
  };
}

/// Yêu cầu thay đổi quyền chờ người đại diện quyết định (012 T017; US3; FR-015 a, FR-016, FR-020b). Chỉ trực tuyến:
/// lệnh không vào hàng đợi ngoại tuyến. Xác nhận làm yêu cầu có hiệu lực ngay; từ chối bắt buộc lý do. Yêu cầu trái mong
/// muốn của người cao tuổi chỉ Quản lý viện duyệt nên không có nút Xác nhận. Backend kiểm người được quyết định (người
/// đại diện, không phải người bị đặt/thôi); lỗi hiện tại thẻ. Test BF-12 C-5 (2026-11-24): thêm ngoại lệ đón Chờ xác
/// nhận (`GET /pickup-exceptions`, FR-024, FR-050), cùng thẻ, cùng chữ với cổng web; tải lỗi thì chỉ bỏ phần ngoại lệ.
class RightChangeRequestsScreen extends StatefulWidget {
  const RightChangeRequestsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<RightChangeRequestsScreen> createState() => _RightChangeRequestsScreenState();
}

/// Một việc chờ người đại diện quyết định: yêu cầu thay đổi quyền hoặc ngoại lệ đón.
class _Pending {
  const _Pending({
    required this.key,
    required this.path,
    required this.title,
    required this.lines,
    required this.canConfirm,
    required this.confirmed,
    required this.rejected,
  });

  _Pending.request(Map<String, dynamic> r)
    : this(
        key: 'right-${r['id']}',
        path: '/right-change-requests/${r['id']}',
        title: describeRightChangeRequest(r),
        lines: ['Lý do: ${r['reason']}', if (r['appliedOnCreation'] == true) 'Đã áp dụng khi lập'],
        canConfirm: r['conflictingWishId'] == null,
        confirmed: 'Đã xác nhận yêu cầu',
        rejected: 'Đã từ chối yêu cầu',
      );

  _Pending.exception(Map<String, dynamic> e)
    : this(
        key: 'pickup-exception-${e['id']}',
        path: '/pickup-exceptions/${e['id']}',
        title: 'Ngoại lệ đón: ${e['fullName']} (${e['relationship']})',
        lines: [
          'Giấy tờ: ${e['idDocumentNumber']}',
          'Lý do: ${e['reason']}',
          'Xác nhận thì người này được đón đúng một lượt trong thời hạn của ngoại lệ.',
        ],
        canConfirm: true,
        confirmed: 'Đã xác nhận ngoại lệ đón',
        rejected: 'Đã từ chối ngoại lệ đón',
      );

  final String key;
  final String path;
  final String title;
  final List<String> lines;
  final bool canConfirm;
  final String confirmed;
  final String rejected;
}

class _RightChangeRequestsScreenState extends State<RightChangeRequestsScreen> {
  List<_Pending>? _items;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final requests = (await widget.api.getList(
        '/right-change-requests?status=PENDING_CONFIRMATION',
      )).cast<Map<String, dynamic>>();
      var exceptions = const <Map<String, dynamic>>[];
      try {
        exceptions = (await widget.api.getList(
          '/pickup-exceptions?status=PENDING_CONFIRMATION',
        )).cast<Map<String, dynamic>>();
      } on Exception {
        // Không đọc được ngoại lệ đón thì vẫn hiện yêu cầu thay đổi quyền
      }
      final items = [...requests.map(_Pending.request), ...exceptions.map(_Pending.exception)];
      if (!mounted) return;
      setState(() {
        _items = items;
        _loadError = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  void _decided(_Pending item, String message) {
    setState(() => _items = _items?.where((r) => r.key != item.key).toList());
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final items = _items;
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(backendMessage(_loadError!), style: text.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tải lại')),
          ],
        ),
      );
    }
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Không có yêu cầu nào chờ xác nhận.', style: text.bodyMedium),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _RequestCard(
        key: ValueKey(items[i].key),
        api: widget.api,
        item: items[i],
        onDecided: (message) => _decided(items[i], message),
      ),
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({super.key, required this.api, required this.item, required this.onDecided});

  final ApiClient api;
  final _Pending item;
  final ValueChanged<String> onDecided;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  final _reason = TextEditingController();
  final _key = _uuid();
  bool _rejecting = false;
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send(String command, Map<String, dynamic> body, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('${widget.item.path}/$command', body, headers: {'Idempotency-Key': _key});
      widget.onDecided(done);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reject() {
    setState(() => _submitted = true);
    if (_reason.text.trim().isEmpty) return;
    _send('reject', {'reason': _reason.text.trim()}, widget.item.rejected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = theme.extension<Tones>()!;
    final item = widget.item;
    final reasonMissing = _submitted && _reason.text.trim().isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.title, style: theme.textTheme.titleSmall),
            for (final line in item.lines) ...[
              const SizedBox(height: 4),
              Text(line, style: theme.textTheme.bodyMedium),
            ],
            if (!item.canConfirm) ...[
              const SizedBox(height: 8),
              Text(
                'Trái mong muốn của người cao tuổi, chờ Quản lý viện duyệt.',
                style: theme.textTheme.bodySmall?.copyWith(color: tones.attentionInk),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: tones.attentionInk)),
              ),
            ],
            const SizedBox(height: 12),
            if (_rejecting) ...[
              TextField(
                controller: _reason,
                maxLength: 2000,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(labelText: 'Lý do từ chối', errorText: reasonMissing ? 'Nhập lý do' : null),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton(onPressed: _busy ? null : _reject, child: const Text('Xác nhận từ chối')),
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _rejecting = false;
                      _submitted = false;
                    }),
                    child: const Text('Đóng'),
                  ),
                ],
              ),
            ] else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (item.canConfirm)
                    FilledButton(
                      onPressed: _busy ? null : () => _send('confirm', const {}, item.confirmed),
                      child: const Text('Xác nhận'),
                    ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => setState(() => _rejecting = true),
                    child: const Text('Từ chối'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Khóa idempotency dạng UUID v4 cho một lần quyết định của thẻ.
String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
