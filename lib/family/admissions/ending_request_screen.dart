import 'dart:math';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';
import '../../common/widgets/page_body.dart';

const _cases = {'CONTRACT_EXPIRED': 'Hết hạn hợp đồng', 'CONTRACT_TERMINATION': 'Chấm dứt hợp đồng'};
const _statuses = {
  'PENDING': 'Đang chờ viện xử lý',
  'HANDLED': 'Viện đã lập hồ sơ kết thúc',
  'REJECTED': 'Viện từ chối',
  'CANCELLED': 'Đã hủy',
};

const _reasonMax = 2000;

/// Người đại diện gửi yêu cầu kết thúc lưu trú (demo 2026-11-26; api-004 tag `residency-ending`): chọn hết hạn hoặc chấm
/// dứt hợp đồng, ngày mong muốn, lý do; Hành chính được báo. Đang có yêu cầu chờ xử lý thì chỉ xem và hủy được. Chỉ trực
/// tuyến.
class EndingRequestScreen extends StatefulWidget {
  const EndingRequestScreen({super.key, required this.api, required this.residentId, this.today});

  final ApiClient api;
  final int residentId;

  /// Ngày hôm nay, để test cố định ngày; mặc định theo đồng hồ máy.
  final DateTime? today;

  @override
  State<EndingRequestScreen> createState() => _EndingRequestScreenState();
}

class _EndingRequestScreenState extends State<EndingRequestScreen> {
  final _date = TextEditingController();
  final _reason = TextEditingController();
  List<Map<String, dynamic>>? _requests;
  String? _contractEnd;
  String _key = _uuid();
  bool _submitted = false;
  bool _busy = false;
  String? _error;
  Object? _loadError;

  String get _path => '/family-portal/residents/${widget.residentId}/residency-ending-requests';

  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = (await widget.api.getList(_path)).cast<Map<String, dynamic>>();
      // Ngày hết hạn của hợp đồng Hiệu lực để biết hết hạn hay chấm dứt (demo BF-10, 2026-11-27)
      String? contractEnd;
      try {
        final body = await widget.api.get('/family-portal/residents/${widget.residentId}/contract');
        for (final c in ((body?['contracts'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
          if (c['status'] == 'ACTIVE') contractEnd = c['endDate'] as String?;
        }
      } on Exception {
        contractEnd = null;
      }
      if (!mounted) return;
      setState(() {
        _requests = rows;
        _contractEnd = contractEnd;
        _loadError = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _display(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
  static String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  // Ngày nhập dd/MM/yyyy; sai định dạng hoặc ngày không có thật (31/02) thì null
  DateTime? _parsedDate() {
    final parts = _date.text.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null || year < 1000) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  String? get _dateError {
    if (_date.text.trim().isEmpty) return 'Nhập ngày kết thúc mong muốn';
    final date = _parsedDate();
    if (date == null) return 'Ngày không hợp lệ, nhập theo dạng dd/MM/yyyy';
    if (date.isBefore(_today)) return 'Ngày kết thúc không được trước hôm nay';
    return null;
  }

  // Hết hạn khi ngày không sớm hơn ngày hết hạn hợp đồng; backend xét lại khi lưu
  String? get _endCase {
    final date = _parsedDate();
    if (date == null) return null;
    final end = _contractEnd == null ? null : DateTime.tryParse(_contractEnd!);
    return end != null && !date.isBefore(end) ? 'CONTRACT_EXPIRED' : 'CONTRACT_TERMINATION';
  }

  Future<void> _pickDate() async {
    final current = _parsedDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(_today) ? current : _today,
      firstDate: _today,
      lastDate: DateTime(_today.year + 5),
      helpText: 'Ngày kết thúc mong muốn',
    );
    if (picked != null) setState(() => _date.text = _display(picked));
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Quay lại')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _send() async {
    setState(() => _submitted = true);
    final endCase = _endCase;
    if (endCase == null || _dateError != null || _reason.text.trim().isEmpty) return;
    final date = _parsedDate()!;
    final confirmed = await _confirm(
      'Gửi yêu cầu kết thúc lưu trú?',
      '${_cases[endCase]}, ngày ${_display(date)}. Hành chính của viện sẽ liên hệ để làm thủ tục.',
      'Xác nhận gửi',
    );
    if (!confirmed || !mounted) return;
    await _command(() async {
      await widget.api.post(
        _path,
        {'endCase': endCase, 'expectedEndDate': _iso(date), 'reason': _reason.text.trim()},
        headers: {'Idempotency-Key': _key},
      );
      // Lần gửi sau (sau khi hủy hoặc bị từ chối) là yêu cầu mới
      _key = _uuid();
      _submitted = false;
      _date.clear();
      _reason.clear();
    });
  }

  Future<void> _cancel(int id) async {
    final confirmed = await _confirm(
      'Hủy yêu cầu này?',
      'Viện sẽ không xử lý yêu cầu nữa. Gia đình gửi lại được khi cần.',
      'Xác nhận hủy',
    );
    if (!confirmed || !mounted) return;
    await _command(() async {
      await widget.api.post(
        '/family-portal/residency-ending-requests/$id/cancel',
        const {},
        headers: {'Idempotency-Key': _uuid()},
      );
    });
  }

  // Chạy lệnh rồi đọc lại danh sách; lỗi cũng đọc lại vì viện có thể vừa xử lý yêu cầu
  Future<void> _command(Future<void> Function() run) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await run();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final requests = _requests;
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
    if (requests == null) return const Center(child: CircularProgressIndicator());
    final waiting = requests.any((r) => r['status'] == 'PENDING');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[
          Semantics(liveRegion: true, child: Text(_error!, style: text.bodyMedium)),
          const SizedBox(height: 12),
        ],
        if (!waiting) ..._form(text),
        if (requests.isNotEmpty) ...[
          Text('Yêu cầu đã gửi', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final r in requests) _requestCard(text, r),
        ],
      ],
    );
  }

  List<Widget> _form(TextTheme text) => [
    Text('Đề nghị kết thúc lưu trú', style: text.titleMedium),
    const SizedBox(height: 4),
    Text('Hành chính của viện nhận yêu cầu, lập hồ sơ và liên hệ gia đình để làm thủ tục.', style: text.bodySmall),
    const SizedBox(height: 16),
    Text(
      _contractEnd == null ? 'Hợp đồng không có ngày hết hạn.' : 'Hợp đồng hết hạn ngày ${formatDate(_contractEnd!)}.',
      style: text.bodyMedium,
    ),
    const SizedBox(height: 12),
    TextField(
      controller: _date,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: 'Ngày kết thúc mong muốn (dd/MM/yyyy)',
        errorText: _submitted ? _dateError : null,
        suffixIcon: IconButton(
          tooltip: 'Chọn ngày trên lịch',
          icon: const Icon(Icons.calendar_month),
          onPressed: _pickDate,
        ),
      ),
      onChanged: (_) => setState(() {}),
    ),
    // Luôn giữ chỗ dòng chú thích để các ô nhập không dịch chỗ khi đang gõ
    const SizedBox(height: 4),
    Text(switch (_endCase) {
      'CONTRACT_EXPIRED' => 'Kết thúc khi hết hạn hợp đồng: tháng cuối tính theo số ngày ở.',
      'CONTRACT_TERMINATION' =>
        'Chấm dứt trước hạn hợp đồng: nội trú dài hạn trả đủ tháng cuối; viện trao đổi phí chấm dứt sớm nếu hợp đồng có.',
      _ => '',
    }, style: text.bodySmall),
    const SizedBox(height: 12),
    TextField(
      controller: _reason,
      maxLength: _reasonMax,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: 'Lý do',
        errorText: _submitted && _reason.text.trim().isEmpty ? 'Nhập lý do' : null,
      ),
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: 12),
    FilledButton(onPressed: _busy ? null : _send, child: const Text('Gửi yêu cầu')),
    const SizedBox(height: 24),
  ];

  Widget _requestCard(TextTheme text, Map<String, dynamic> r) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_statuses[r['status']] ?? '${r['status']}', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${_cases[r['endCase']] ?? r['endCase']}, ngày ${formatDate(r['expectedEndDate'] as String)}',
            style: text.bodyMedium,
          ),
          Text('Lý do: ${r['reason']}', style: text.bodySmall),
          if (r['decisionReason'] != null) Text('Lý do từ chối: ${r['decisionReason']}', style: text.bodyMedium),
          if (r['status'] == 'PENDING') ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _busy ? null : () => _cancel(r['id'] as int), child: const Text('Hủy yêu cầu')),
          ],
        ],
      ),
    ),
  );
}

/// Mở màn yêu cầu từ thông báo (nguồn `M02.ENDING_REQUEST`, mã là mã yêu cầu). Thông báo không mang mã người cao tuổi nên
/// tìm trong các người cao tuổi người thân là đại diện; chỉ đại diện một người thì mở luôn người đó.
class EndingRequestFromNotice extends StatefulWidget {
  const EndingRequestFromNotice({super.key, required this.api, required this.requestId});

  final ApiClient api;
  final int requestId;

  @override
  State<EndingRequestFromNotice> createState() => _EndingRequestFromNoticeState();
}

class _EndingRequestFromNoticeState extends State<EndingRequestFromNotice> {
  int? _residentId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    try {
      final residents = (await widget.api.getList('/family-portal/residents')).cast<Map<String, dynamic>>();
      final ids = [
        for (final r in residents)
          if (r['representative'] == true) r['residentId'] as int,
      ];
      int? found = ids.length == 1 ? ids.single : null;
      for (final id in ids) {
        if (found != null) break;
        final rows = await widget.api.getList('/family-portal/residents/$id/residency-ending-requests');
        if (rows.any((r) => (r as Map<String, dynamic>)['id'] == widget.requestId)) found = id;
      }
      if (!mounted) return;
      setState(() => found == null ? _error = 'Không tìm thấy yêu cầu của thông báo này.' : _residentId = found);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kết thúc lưu trú')),
    body: _residentId != null
        ? EndingRequestScreen(api: widget.api, residentId: _residentId!)
        : PageBody(child: _error == null ? const Center(child: CircularProgressIndicator()) : Text(_error!)),
  );
}

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
