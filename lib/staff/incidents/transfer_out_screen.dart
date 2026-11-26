import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../alerts/emergency_assist_screen.dart' show dialPhone;
import 'bf06_shared.dart';

/// Chuyển viện từ sự cố trên app nhân viên (007 FR-049, FR-050; BR-M05-14; api-007 `POST /incidents/{id}/transfer-out`).
/// Ít ô: chuyển đến, người đi cùng, nhân viên bàn giao; hỏi người liên hệ chính khi phiếu điều trị yêu cầu hỏi trước.
/// Xong thì gửi phiếu tóm tắt PDF qua bảng chia sẻ của máy (cùng tệp backend dựng như bản trên web); trả `true`.
class TransferOutScreen extends StatefulWidget {
  const TransferOutScreen({
    super.key,
    required this.api,
    required this.incidentId,
    this.residentName,
    this.dial = dialPhone,
    this.share = sharePdf,
  });

  final ApiClient api;
  final int incidentId;
  final String? residentName;
  final Future<bool> Function(String phone) dial;
  final Future<void> Function(Uint8List bytes, String name) share;

  @override
  State<TransferOutScreen> createState() => _TransferOutScreenState();
}

class _TransferOutScreenState extends State<TransferOutScreen> {
  final _unit = TextEditingController();
  final _companion = TextEditingController();
  final _reason = TextEditingController();
  final _key = newIdempotencyKey();
  Map<String, dynamic>? _info;
  List<Map<String, dynamic>> _staff = const [];
  int? _handoverStaffId;
  bool? _reached;
  bool _includeWishes = false, _busy = false, _submitted = false;
  String? _error;
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _unit.dispose();
    _companion.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await widget.api.get('/incidents/${widget.incidentId}/transfer-out/info');
      List<Map<String, dynamic>> staff = const [];
      try {
        staff = (await widget.api.getList('/staff?status=WORKING')).cast<Map<String, dynamic>>();
      } on Exception {
        // Danh sách trống: bỏ ô nhân viên bàn giao
      }
      if (mounted) {
        setState(() {
          _info = info ?? const {};
          _staff = staff;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  bool get _mustAsk => _info?['mustAskFirst'] == true;
  bool get _emergency => _info?['isEmergency'] == true;
  bool get _hasWish {
    final eol = _info?['endOfLifeWish'] as Map?;
    return _info?['treatmentWish'] != null || (eol != null && eol['notRecorded'] != true);
  }

  String? get _formError {
    if (_unit.text.trim().isEmpty) return 'Nhập nơi chuyển đến';
    if (_companion.text.trim().isEmpty) return 'Nhập người đi cùng';
    if (_mustAsk && _reached == null) return 'Chọn đã liên hệ người nhà chưa';
    if (_mustAsk && _reached == false && !_emergency && _reason.text.trim().isEmpty) return 'Nhập lý do chưa hỏi được';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if (_formError != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final summary = await widget.api.post(
        '/incidents/${widget.incidentId}/transfer-out',
        {
          'transferUnit': _unit.text.trim(),
          'companion': _companion.text.trim(),
          if (_handoverStaffId != null) 'handoverStaffId': _handoverStaffId,
          if (_mustAsk) 'requiredContactReached': _reached,
          if (_mustAsk && _reached == false && _reason.text.trim().isNotEmpty)
            'notAskedFirstReason': _reason.text.trim(),
          if (_hasWish) 'includeWishes': _includeWishes,
        },
        headers: {'Idempotency-Key': _key},
      );
      if (mounted) setState(() => _summary = summary ?? const {});
    } on ApiUnreachable {
      if (mounted) setState(() => _error = 'Mất kết nối, chưa chuyển viện. Thử lại khi có mạng.');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf() async {
    final id = _summary?['id'];
    if (id == null) return;
    setState(() => _error = null);
    try {
      final bytes = await widget.api.getBytes('/transfer-summaries/$id/document');
      await widget.share(bytes, 'phieu-chuyen-vien-$id.pdf');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Quay lại',
        icon: const Icon(LucideIcons.chevronLeft),
        onPressed: () => Navigator.of(context).pop(_summary != null),
      ),
      title: Text(_summary == null ? 'Chuyển viện' : 'Đã chuyển viện'),
    ),
    body: _info == null
        ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
        : (_summary == null ? _form(context) : _done(context)),
  );

  Widget _form(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _submitted ? _formError : null;
    Widget seg(String label, bool on, VoidCallback onTap) => Expanded(
      child: SizedBox(
        height: 52,
        child: on
            ? FilledButton(onPressed: onTap, child: Text(label))
            : OutlinedButton(onPressed: onTap, child: Text(label)),
      ),
    );
    final contact = _info?['primaryContact'] as Map?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (widget.residentName != null) Text(widget.residentName!, style: text.headlineSmall),
        Text('Từ sự cố #${widget.incidentId}', style: text.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _unit,
          decoration: const InputDecoration(labelText: 'Chuyển đến (bệnh viện)'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _companion,
          decoration: const InputDecoration(labelText: 'Người đi cùng (họ tên, chức danh)'),
          onChanged: (_) => setState(() {}),
        ),
        if (_staff.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _handoverStaffId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nhân viên bàn giao'),
            items: [
              for (final s in _staff)
                DropdownMenuItem(value: s['id'] as int, child: Text('${s['fullName']} · ${s['position'] ?? ''}')),
            ],
            onChanged: (v) => setState(() => _handoverStaffId = v),
          ),
        ],
        if (_mustAsk) ...[
          const SizedBox(height: 16),
          Text(
            'Phiếu điều trị yêu cầu hỏi người nhà trước${contact == null ? '' : ' (${contact['fullName']})'}. Đã liên hệ được chưa?',
            style: text.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              seg('Đã liên hệ', _reached == true, () => setState(() => _reached = true)),
              const SizedBox(width: 8),
              seg('Chưa được', _reached == false, () => setState(() => _reached = false)),
            ],
          ),
          if (contact?['phoneNumber'] != null)
            TextButton.icon(
              onPressed: () => widget.dial('${contact['phoneNumber']}'),
              icon: const Icon(LucideIcons.phone),
              label: Text('Gọi ${contact!['fullName']}'),
            ),
          if (_reached == false && !_emergency)
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Lý do chưa hỏi được'),
              onChanged: (_) => setState(() {}),
            ),
        ],
        if (_hasWish)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _includeWishes,
            onChanged: (v) => setState(() => _includeWishes = v ?? false),
            title: const Text('In kèm nguyện vọng điều trị trên phiếu'),
          ),
        if (error != null || _error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(error ?? _error!, style: text.bodyLarge?.copyWith(color: scheme.error)),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 60,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Đang gửi…' : 'Xác nhận chuyển viện'),
          ),
        ),
      ],
    );
  }

  Widget _done(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final contact = _info?['primaryContact'] as Map?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(LucideIcons.circleCheck, size: 64, color: scheme.primary),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            '${widget.residentName ?? 'Cụ'} đã chuyển đến ${_unit.text.trim()}',
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Phiếu tóm tắt đã lập. Cùng một phiếu PDF với bản trên máy tính; in nhiều bản thì in ở máy tính.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _sharePdf,
            icon: const Icon(LucideIcons.share2),
            label: const Text('Gửi phiếu tóm tắt (PDF)'),
          ),
        ),
        if (contact?['phoneNumber'] != null) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => widget.dial('${contact['phoneNumber']}'),
              icon: const Icon(LucideIcons.phone),
              label: Text('Gọi người nhà: ${contact!['fullName']}'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: OutlinedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xong')),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: text.bodyMedium?.copyWith(color: scheme.error)),
          ),
      ],
    );
  }
}
