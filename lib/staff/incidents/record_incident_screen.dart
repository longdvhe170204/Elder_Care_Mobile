import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';

// Báo sự cố trên app nhân viên (luồng 2.2, 2.3 SRS; 007 FR-040 → FR-042): cùng nội dung form Ghi nhận sự cố của web.
// Chọn người cao tuổi (mở từ thẻ công việc thì chọn sẵn), loại sự cố (chọn loại thì điền mức mặc định), mức, thời điểm
// phát hiện, mô tả; chọn mức thấp hơn mức mặc định của loại thì bắt buộc lý do (FR-042). Cần trực tuyến. Trả true khi đã
// ghi. Mức Khẩn cấp mở quy trình khẩn cấp ngay khi lưu (backend).

const _levels = {'CRITICAL': 'Khẩn cấp', 'MEDIUM': 'Trung bình', 'LOW': 'Nhẹ'};
const _levelOrder = ['CRITICAL', 'MEDIUM', 'LOW'];

String _newKey() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class RecordIncidentScreen extends StatefulWidget {
  const RecordIncidentScreen({super.key, required this.api, this.residentId});
  final ApiClient api;
  final int? residentId;

  @override
  State<RecordIncidentScreen> createState() => _RecordIncidentScreenState();
}

class _RecordIncidentScreenState extends State<RecordIncidentScreen> {
  final _description = TextEditingController();
  final _lowerReason = TextEditingController();
  List<Map<String, dynamic>>? _types;
  List<Map<String, dynamic>>? _residents;
  int? _residentId;
  int? _typeId;
  String? _level;
  late DateTime _discoveredAt;
  bool _submitted = false;
  bool _busy = false;
  String? _error;
  String? _retrySignature;
  String? _retryKey;

  @override
  void initState() {
    super.initState();
    _residentId = widget.residentId;
    _discoveredAt = DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _lowerReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final types = await widget.api.getList('/incident-types');
      final residents = await widget.api.get('/residents');
      if (!mounted) return;
      setState(() {
        _types = types.map((t) => Map<String, dynamic>.from(t as Map)).where((t) => t['status'] != 'INACTIVE').toList();
        _residents = [
          for (final r in (residents?['items'] as List? ?? []).map((r) => Map<String, dynamic>.from(r as Map)))
            {
              'id': r['id'],
              'label':
                  '${(r['personalInfo'] as Map?)?['fullName'] ?? 'Người cao tuổi ${r['id']}'}'
                  '${r['profileCode'] == null ? '' : ' (${r['profileCode']})'}',
            },
        ];
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  Map<String, dynamic>? get _type => _types?.where((t) => t['id'] == _typeId).firstOrNull;
  bool get _residentRequired => _type?['allowsNoResident'] != true;
  bool get _lowerNeeded {
    final type = _type;
    if (type == null || _level == null) return false;
    return _levelOrder.indexOf(_level!) > _levelOrder.indexOf(type['defaultLevel'] as String? ?? '');
  }

  String? get _residentError => _residentRequired && _residentId == null ? 'Chọn người cao tuổi' : null;
  String? get _typeError => _type == null ? 'Chọn loại sự cố' : null;
  String? get _levelError => _level == null ? 'Chọn mức độ' : null;
  String? get _descriptionError => _description.text.trim().isEmpty ? 'Nhập mô tả' : null;
  String? get _lowerError => _lowerNeeded && _lowerReason.text.trim().isEmpty ? 'Nhập lý do hạ mức' : null;

  String _discoveredIso() {
    final vn = _discoveredAt.toUtc().add(const Duration(hours: 7));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${vn.year}-${two(vn.month)}-${two(vn.day)}T${two(vn.hour)}:${two(vn.minute)}:00+07:00';
  }

  Future<void> _pickTime() async {
    final vn = _discoveredAt.toUtc().add(const Duration(hours: 7));
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: vn.hour, minute: vn.minute),
    );
    if (picked == null || !mounted) return;
    final day = DateTime.utc(vn.year, vn.month, vn.day, picked.hour, picked.minute);
    setState(() => _discoveredAt = day.subtract(const Duration(hours: 7)));
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    if ([_residentError, _typeError, _levelError, _descriptionError, _lowerError].any((e) => e != null)) return;
    final body = <String, dynamic>{
      if (_residentId != null) 'residentId': _residentId,
      'incidentTypeId': _typeId,
      'level': _level,
      'discoveredAt': _discoveredIso(),
      'description': _description.text.trim(),
      if (_lowerNeeded) 'lowerLevelReason': _lowerReason.text.trim(),
    };
    final signature = jsonEncode(body);
    if (signature != _retrySignature) {
      _retrySignature = signature;
      _retryKey = _newKey();
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post('/incidents', body, headers: {'Idempotency-Key': _retryKey!});
      if (mounted) Navigator.of(context).pop(true);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _shown(String? error) => _submitted ? error : null;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final loading = _types == null || _residents == null;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Báo sự cố')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Mức Khẩn cấp mở quy trình khẩn cấp ngay khi lưu.', style: text.bodySmall),
            const SizedBox(height: 12),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                ),
              ),
            if (loading && _error == null)
              const Center(child: CircularProgressIndicator())
            else if (!loading) ...[
              DropdownButtonFormField<int>(
                key: const Key('incident-resident'),
                initialValue: _residents!.any((r) => r['id'] == _residentId) ? _residentId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Người cao tuổi', errorText: _shown(_residentError)),
                items: [
                  for (final r in _residents!)
                    DropdownMenuItem(value: r['id'] as int, child: Text(r['label'] as String)),
                ],
                onChanged: _busy ? null : (value) => setState(() => _residentId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const Key('incident-type'),
                initialValue: _typeId,
                isExpanded: true,
                decoration: InputDecoration(labelText: 'Loại sự cố', errorText: _shown(_typeError)),
                items: [
                  for (final t in _types!)
                    DropdownMenuItem(value: t['id'] as int, child: Text(t['name'] as String? ?? '')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _typeId = value;
                        _level ??= _type?['defaultLevel'] as String?;
                      }),
              ),
              const SizedBox(height: 12),
              Text('Mức độ', style: text.titleSmall),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in _levels.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _level == entry.key,
                      onSelected: _busy ? null : (_) => setState(() => _level = entry.key),
                    ),
                ],
              ),
              if (_shown(_levelError) case final error?)
                Text(error, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              if (_lowerNeeded) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('incident-lower-reason'),
                  controller: _lowerReason,
                  enabled: !_busy,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: 'Lý do hạ mức', errorText: _shown(_lowerError)),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Text('Phát hiện lúc ${formatDateTime(_discoveredAt)}')),
                  TextButton(onPressed: _busy ? null : _pickTime, child: const Text('Đổi giờ')),
                ],
              ),
              TextField(
                key: const Key('incident-description'),
                controller: _description,
                enabled: !_busy,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
                decoration: InputDecoration(labelText: 'Mô tả', errorText: _shown(_descriptionError)),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Đang lưu…' : 'Ghi nhận sự cố')),
            ],
            if (_error != null && loading) OutlinedButton(onPressed: _load, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
