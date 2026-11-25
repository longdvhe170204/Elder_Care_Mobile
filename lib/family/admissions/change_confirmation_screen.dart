import 'dart:math';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';
import '../../common/widgets/page_body.dart';

const _path = '/family-portal/residency-change-confirmations';

const _careLevels = {'BASIC': 'Cơ bản', 'REGULAR': 'Thường xuyên', 'SPECIAL': 'Đặc biệt'};
const _residenceTypes = {
  'LONG_TERM_RESIDENTIAL': 'Nội trú dài hạn',
  'SHORT_TERM_RESIDENTIAL': 'Nội trú ngắn ngày',
  'DAY_CARE': 'Bán trú',
};

String _idempotencyKey() {
  final r = Random.secure();
  String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
}

String _money(Object? value) {
  if (value is! num) return 'chưa có';
  final digits = value.round().toString();
  final grouped = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$grouped đ';
}

String _costItem(Object? item) {
  final code = item as String? ?? '';
  if (code == 'CARE_SERVICE') return 'Dịch vụ chăm sóc';
  if (code == 'RESIDENCY_FEE') return 'Phí lưu trú';
  if (code.startsWith('SERVICE:')) return 'Dịch vụ mã ${code.substring('SERVICE:'.length)}';
  return code;
}

/// Một dòng nội dung theo loại thay đổi: giá trị trước → giá trị mới.
String _changeLine(String type, Map<String, dynamic> before, Map<String, dynamic> after) {
  String pair(String label, Map<String, String> names, String key) {
    final from = names[before[key]] ?? before[key] as String?;
    final to = names[after[key]] ?? after[key] as String? ?? '—';
    return from == null ? '$label: $to' : '$label: $from → $to';
  }

  switch (type) {
    case 'CARE_LEVEL':
      return pair('Mức chăm sóc', _careLevels, 'careLevel');
    case 'RESIDENCE_TYPE':
      return pair('Loại lưu trú', _residenceTypes, 'residenceType');
    case 'DURATION':
      final to = after['endDate'] as String?;
      return 'Thời hạn: đến ${to == null ? '—' : formatDate(to)}';
    case 'BED':
      return 'Giường: chuyển sang giường mã ${after['newBedId'] ?? '—'}';
    case 'SERVICE':
      final lines = (after['services'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
      final added = lines.where((l) => l['action'] == 'ADD').length;
      final removed = lines.where((l) => l['action'] == 'REMOVE').length;
      return 'Dịch vụ: thêm $added, bớt $removed dịch vụ';
    case 'ARRIVAL_SCHEDULE':
      return 'Lịch đến: ${(after['arrivalSchedule'] as List<dynamic>? ?? const []).length} buổi mỗi tuần';
    default:
      return type;
  }
}

/// Người đại diện xem và trả lời đề nghị xác nhận thay đổi lưu trú (004 T120; FR-043c; api-004 `GET /family-portal/
/// residency-change-confirmations`, `POST …/{id}/accept`, `…/{id}/decline`), mở từ thông báo
/// `RESIDENCY_CHANGE_CONFIRMATION_REQUESTED` (nguồn `M02.CHANGE_CONFIRMATION`) hoặc từ danh sách ở màn người cao tuổi.
/// Màn đọc danh sách đề nghị đang chờ rồi lấy đề nghị theo mã; người đại diện thấy nội dung kèm chi phí trước khi trả lời.
/// Không đồng ý bắt buộc lý do (DESIGN.md 2.3). Chỉ trực tuyến.
class ChangeConfirmationScreen extends StatefulWidget {
  const ChangeConfirmationScreen({super.key, required this.api, required this.confirmationId});

  final ApiClient api;
  final int confirmationId;

  @override
  State<ChangeConfirmationScreen> createState() => _ChangeConfirmationScreenState();
}

class _ChangeConfirmationScreenState extends State<ChangeConfirmationScreen> {
  final _reason = TextEditingController();
  final _keys = {'accept': _idempotencyKey(), 'decline': _idempotencyKey()};
  bool _declining = false;
  bool _busy = false;
  bool _loading = true;
  bool _answered = false;
  String? _reasonError;
  String? _message;
  String? _loadError;
  Map<String, dynamic>? _item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.api.getList(_path);
      final match = rows.cast<Map<String, dynamic>>().where((r) => r['id'] == widget.confirmationId);
      if (!mounted) return;
      setState(() {
        _item = match.isEmpty ? null : match.first;
        if (_item == null) {
          _loadError = 'Đề nghị này không còn chờ xác nhận (đã trả lời hoặc viện đã sửa nội dung).';
        }
      });
    } on ApiUnreachable {
      if (mounted) setState(() => _loadError = 'Cần có mạng để xem đề nghị. Kiểm tra kết nối rồi thử lại.');
    } on Exception catch (e) {
      if (mounted) setState(() => _loadError = backendMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(String command) async {
    if (command == 'decline' && _reason.text.trim().isEmpty) {
      setState(() => _reasonError = 'Nhập lý do không đồng ý.');
      return;
    }
    setState(() {
      _busy = true;
      _reasonError = null;
      _message = null;
    });
    try {
      await widget.api.requestJson(
        'POST',
        '$_path/${widget.confirmationId}/$command',
        headers: {'Idempotency-Key': _keys[command]!},
        body: command == 'decline' ? {'reason': _reason.text.trim()} : const <String, dynamic>{},
      );
      setState(() {
        _answered = true;
        _message = command == 'accept'
            ? 'Đã gửi đồng ý. Viện sẽ trình Quản lý viện duyệt. Viện sẽ hẹn bạn ký phụ lục.'
            : 'Đã gửi không đồng ý. Viện sẽ xem lý do và liên hệ lại.';
      });
    } on ApiUnreachable {
      setState(() => _message = 'Cần có mạng để gửi trả lời. Kiểm tra kết nối rồi thử lại.');
    } on Exception catch (e) {
      setState(() => _message = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _content(TextTheme text) {
    final item = _item!;
    final before = item['previousValue'] as Map<String, dynamic>? ?? const {};
    final after = item['newValue'] as Map<String, dynamic>? ?? const {};
    final costs = (item['costImpact'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
    final date = item['requestedEffectiveDate'] as String?;
    return [
      Text('Nội dung thay đổi', style: text.titleSmall),
      const SizedBox(height: 4),
      for (final type in (item['changeTypes'] as List<dynamic>? ?? const []).cast<String>())
        Text(_changeLine(type, before, after)),
      if (date != null) Text('Từ ngày ${formatDate(date)}'),
      if (costs.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('Chi phí thay đổi', style: text.titleSmall),
        const SizedBox(height: 4),
        for (final c in costs)
          Text('${_costItem(c['item'])}: ${_money(c['previousUnitPrice'])} → ${_money(c['newUnitPrice'])}'),
      ],
      if (item['reason'] != null) ...[const SizedBox(height: 12), Text('Lý do: ${item['reason']}')],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Xác nhận điều chỉnh hợp đồng')),
      body: PageBody(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_loadError != null) Semantics(liveRegion: true, child: Text(_loadError!)),
              if (_item != null) ...[
                const Text(
                  'Viện đề nghị điều chỉnh hợp đồng của người thân. Bạn là người đại diện nên xác nhận có đồng ý hay không.',
                ),
                const SizedBox(height: 12),
                ..._content(text),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(liveRegion: true, child: Text(_message!)),
                ),
              if (_item != null && !_answered) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : () => _send('accept'), child: const Text('Đồng ý')),
                const SizedBox(height: 12),
                if (!_declining)
                  OutlinedButton(
                    onPressed: _busy ? null : () => setState(() => _declining = true),
                    child: const Text('Không đồng ý'),
                  )
                else ...[
                  TextField(
                    key: const Key('decline-reason'),
                    controller: _reason,
                    maxLength: 2000,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: 'Lý do không đồng ý', errorText: _reasonError),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : () => _send('decline'),
                    child: const Text('Gửi không đồng ý'),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Đề nghị xác nhận đang chờ của một người cao tuổi (FR-043c), lối vào ở màn người cao tuổi của người đại diện.
class ChangeConfirmationList extends StatefulWidget {
  const ChangeConfirmationList({super.key, required this.api, required this.residentId});

  final ApiClient api;
  final int residentId;

  @override
  State<ChangeConfirmationList> createState() => _ChangeConfirmationListState();
}

class _ChangeConfirmationListState extends State<ChangeConfirmationList> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.api.getList(_path);
      if (!mounted) return;
      setState(() {
        _rows = rows.cast<Map<String, dynamic>>().where((r) => r['residentId'] == widget.residentId).toList();
        _error = null;
      });
    } on ApiUnreachable {
      if (mounted) setState(() => _error = 'Cần có mạng để xem đề nghị. Kiểm tra kết nối rồi thử lại.');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return PageBody(child: Text(_error!));
    if (_rows == null) return const Center(child: CircularProgressIndicator());
    if (_rows!.isEmpty) return const PageBody(child: Text('Không có đề nghị nào đang chờ bạn xác nhận.'));
    return ListView(
      children: [
        for (final r in _rows!)
          ListTile(
            title: Text(
              (r['changeTypes'] as List<dynamic>? ?? const [])
                  .cast<String>()
                  .map((t) => _changeLine(t, const {}, r['newValue'] as Map<String, dynamic>? ?? const {}))
                  .join('; '),
            ),
            subtitle: Text('Gửi lúc ${formatDateTime(DateTime.parse(r['sentAt'] as String))}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ChangeConfirmationScreen(api: widget.api, confirmationId: r['id'] as int),
                ),
              );
              await _load();
            },
          ),
      ],
    );
  }
}
