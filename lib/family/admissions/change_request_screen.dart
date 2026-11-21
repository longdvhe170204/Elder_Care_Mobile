import 'dart:math';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';

const _careLevels = {'BASIC': 'Cơ bản', 'REGULAR': 'Thường xuyên', 'SPECIAL': 'Đặc biệt'};
const _residenceTypes = {
  'LONG_TERM_RESIDENTIAL': 'Nội trú dài hạn',
  'SHORT_TERM_RESIDENTIAL': 'Nội trú ngắn ngày',
  'DAY_CARE': 'Bán trú',
};

// Gợi ý lý do theo nội dung thay đổi; người đại diện chạm để điền rồi sửa tiếp
const _reasonSuggestions = {
  'RESIDENCE_TYPE': ['Gia đình đổi lịch sinh hoạt', 'Gia đình muốn người thân ở lại viện qua đêm'],
};

const _reasonMax = 2000;

/// Người đại diện gửi yêu cầu thay đổi lưu trú (004 T047; US5, FR-037, FR-039): đổi loại lưu trú. Mức chăm sóc theo đánh
/// giá của Bác sĩ (FR-043j), người đại diện không chọn mức. Yêu cầu
/// được tạo ở Nháp, Hành chính được báo để hoàn thiện và gửi Quản lý viện duyệt; người đại diện không trực tiếp thay đổi.
/// Các loại khác (dịch vụ, giường, lịch đến, thời hạn) làm tại quầy. Hợp đồng lấy qua cổng người thân (api-012
/// `GET /family-portal/residents/{residentId}/contract`, chỉ người đại diện). Chỉ trực tuyến.
class ChangeRequestScreen extends StatefulWidget {
  const ChangeRequestScreen({super.key, required this.api, required this.residentId, this.today});

  final ApiClient api;
  final int residentId;

  /// Ngày hôm nay, để test cố định ngày; mặc định theo đồng hồ máy.
  final DateTime? today;

  @override
  State<ChangeRequestScreen> createState() => _ChangeRequestScreenState();
}

class _ChangeRequestScreenState extends State<ChangeRequestScreen> {
  final _date = TextEditingController();
  final _reason = TextEditingController();
  final _key = _uuid();
  List<Map<String, dynamic>>? _contracts;
  int? _contractId;
  String? _type;
  String? _value;
  bool _submitted = false;
  bool _busy = false;
  String? _error;
  String? _done;
  Object? _loadError;

  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Map<String, dynamic>? get _contract {
    for (final c in _contracts ?? const <Map<String, dynamic>>[]) {
      if (c['id'] == _contractId) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
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
      final body = await widget.api.get('/family-portal/residents/${widget.residentId}/contract');
      final items = ((body?['contracts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _contracts = items.where((c) => c['status'] == 'ACTIVE').toList();
        if (_contracts!.length == 1) _contractId = _contracts!.single['id'] as int;
        _loadError = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _display(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';
  static String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static DateTime? _parseIso(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  // Ngày hiệu lực nhập dd/MM/yyyy; sai định dạng hoặc ngày không có thật (31/02) thì null
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
    if (_date.text.trim().isEmpty) return 'Nhập ngày hiệu lực mong muốn';
    final date = _parsedDate();
    if (date == null) return 'Ngày không hợp lệ, nhập theo dạng dd/MM/yyyy';
    if (date.isBefore(_today)) return 'Ngày hiệu lực không được trước hôm nay';
    final start = _parseIso(_contract?['startDate']);
    if (start != null && date.isBefore(start)) {
      return 'Ngày hiệu lực không được sớm hơn ngày bắt đầu hợp đồng (${_display(start)})';
    }
    return null;
  }

  String? get _currentValue => _contract?[_type == 'CARE_LEVEL' ? 'careLevel' : 'residenceType'] as String?;

  String? get _valueError {
    if (_value == null) return 'Chọn giá trị mới';
    if (_value == _currentValue) return 'Giá trị mới trùng giá trị hiện tại';
    return null;
  }

  String? get _reasonError {
    final reason = _reason.text.trim();
    if (reason.isEmpty) return 'Nhập lý do';
    if (reason.length < 5) return 'Lý do quá ngắn, ghi rõ hơn để Hành chính xem xét';
    return null;
  }

  Future<void> _pickDate() async {
    final start = _parseIso(_contract?['startDate']);
    final first = start != null && start.isAfter(_today) ? start : _today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _parsedDate() != null && !_parsedDate()!.isBefore(first) ? _parsedDate()! : first,
      firstDate: first,
      lastDate: DateTime(_today.year + 5),
      helpText: 'Ngày hiệu lực mong muốn',
    );
    if (picked != null) setState(() => _date.text = _display(picked));
  }

  Future<void> _send() async {
    setState(() => _submitted = true);
    if (_contractId == null || _type == null || _valueError != null || _dateError != null || _reasonError != null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post(
        '/residency-change-requests',
        {
          'contractId': _contractId,
          'changeTypes': [_type],
          'newValue': {_type == 'CARE_LEVEL' ? 'careLevel' : 'residenceType': _value},
          'requestedEffectiveDate': _iso(_parsedDate()!),
          'reason': _reason.text.trim(),
        },
        headers: {'Idempotency-Key': _key},
      );
      if (mounted) {
        setState(
          () => _done =
              'Đã gửi yêu cầu, Hành chính sẽ hoàn thiện và gửi Quản lý viện duyệt. '
              'Theo dõi ở mục "Đề nghị điều chỉnh đã gửi".',
        );
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
    if (_contracts == null) return const Center(child: CircularProgressIndicator());
    if (_done != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(liveRegion: true, child: Text(_done!, style: text.bodyMedium)),
      );
    }
    if (_contracts!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Người thân chưa có hợp đồng đang hiệu lực nên chưa gửi được yêu cầu thay đổi. Liên hệ Hành chính của viện.',
          style: text.bodyMedium,
        ),
      );
    }
    final values = _type == 'CARE_LEVEL' ? _careLevels : _residenceTypes;
    final contract = _contract;
    final current = _currentValue;
    final tomorrow = _today.add(const Duration(days: 1));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Đề nghị điều chỉnh hợp đồng', style: text.titleMedium),
        const SizedBox(height: 4),
        Text('Yêu cầu được lập ở Nháp, Hành chính hoàn thiện và gửi Quản lý viện duyệt.', style: text.bodySmall),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          initialValue: _contractId,
          decoration: InputDecoration(
            labelText: 'Hợp đồng',
            errorText: _submitted && _contractId == null ? 'Chọn hợp đồng' : null,
          ),
          items: [
            for (final c in _contracts!)
              DropdownMenuItem(value: c['id'] as int, child: Text('Hợp đồng ${c['contractNumber']}')),
          ],
          onChanged: (v) => setState(() => _contractId = v),
        ),
        if (contract != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (contract['residenceType'] != null) 'Hiện tại: ${_residenceTypes[contract['residenceType']]}',
              if (contract['careLevel'] != null) 'mức ${_careLevels[contract['careLevel']]}',
              if (_parseIso(contract['startDate']) != null) 'bắt đầu ${_display(_parseIso(contract['startDate'])!)}',
            ].join(', '),
            style: text.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: InputDecoration(
            labelText: 'Nội dung thay đổi',
            errorText: _submitted && _type == null ? 'Chọn nội dung thay đổi' : null,
          ),
          items: const [DropdownMenuItem(value: 'RESIDENCE_TYPE', child: Text('Loại lưu trú'))],
          onChanged: (v) => setState(() {
            _type = v;
            _value = null;
          }),
        ),
        if (_type != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(_type),
            initialValue: _value,
            decoration: InputDecoration(
              labelText: 'Giá trị mới',
              helperText: current != null ? 'Hiện tại: ${values[current]}' : null,
              errorText: _submitted ? _valueError : null,
            ),
            items: [
              for (final e in values.entries)
                if (e.key != current) DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _value = v),
          ),
          if (_type == 'RESIDENCE_TYPE') ...[
            const SizedBox(height: 4),
            Text(
              'Đổi sang bán trú cần lịch đến, sang nội trú cần giường, nội trú ngắn ngày cần thời hạn: Hành chính sẽ liên hệ '
              'để bổ sung.',
              style: text.bodySmall,
            ),
          ],
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _date,
          keyboardType: TextInputType.datetime,
          decoration: InputDecoration(
            labelText: 'Ngày hiệu lực mong muốn (dd/MM/yyyy)',
            helperText: 'Duyệt muộn hơn ngày này thì thay đổi tính từ ngày duyệt.',
            errorText: _submitted ? _dateError : null,
            suffixIcon: IconButton(
              tooltip: 'Chọn ngày trên lịch',
              icon: const Icon(Icons.calendar_month),
              onPressed: _pickDate,
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              label: Text('Ngày mai (${_display(tomorrow)})'),
              onPressed: () => setState(() => _date.text = _display(tomorrow)),
            ),
            ActionChip(
              label: const Text('Đầu tháng sau'),
              onPressed: () => setState(() => _date.text = _display(DateTime(_today.year, _today.month + 1))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reason,
          maxLength: _reasonMax,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: 'Lý do', errorText: _submitted ? _reasonError : null),
        ),
        if (_type != null && _reason.text.trim().isEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in _reasonSuggestions[_type]!) ActionChip(label: Text(s), onPressed: () => _reason.text = s),
            ],
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(_error!, style: text.bodySmall)),
        ],
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _send, child: const Text('Gửi yêu cầu')),
      ],
    );
  }
}

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
