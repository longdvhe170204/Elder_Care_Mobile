import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import 'medication_labels.dart';
import 'medication_round_screen.dart';

/// Thuốc gia đình gửi trên app nhân viên (006 US5; FR-040 → FR-046; BR-M07-10, 11, 19, 30): chọn người cao tuổi, xem các
/// lô, tiếp nhận một lô kèm bốn mục kiểm tra (nhãn, hạn dùng, bao bì, đúng tên), xác nhận sử dụng, giữ hộ, hoàn trả, hủy
/// kèm người chứng kiến, ghi dùng hết, báo gia đình sắp hết. Lệnh trực tuyến, gửi `Idempotency-Key`. Không theo dõi số
/// lượng còn (Q-393). Cùng chữ với màn web.
class FamilyMedicationScreen extends StatefulWidget {
  const FamilyMedicationScreen({super.key, required this.api, this.newKey = medicationCommandKey});

  final ApiClient api;
  final String Function() newKey;

  @override
  State<FamilyMedicationScreen> createState() => _FamilyMedicationScreenState();
}

const _status = {
  'PENDING_RECONCILIATION': 'Chờ đối chiếu',
  'IN_USE': 'Được sử dụng',
  'HOLD_ONLY': 'Chỉ giữ hộ',
  'DEPLETED': 'Đã dùng hết',
  'RETURNED': 'Đã hoàn trả',
  'DISPOSED': 'Đã hủy',
};
const _disposeKind = {'FAMILY_REQUEST': 'theo yêu cầu gia đình', 'EXPIRED': 'do hết hạn dùng'};
const _checks = [
  ('labelOk', 'Nhãn thuốc'),
  ('expiryOk', 'Hạn dùng'),
  ('packagingOk', 'Bao bì'),
  ('nameOk', 'Đúng tên người cao tuổi'),
];
const _actions = {
  'PENDING_RECONCILIATION': ['USE', 'HOLD', 'RETURN', 'DISPOSE'],
  'HOLD_ONLY': ['USE', 'RETURN', 'DISPOSE'],
  'IN_USE': ['LOW', 'DEPLETED', 'STOP'],
};
const _label = {
  'USE': 'Xác nhận sử dụng',
  'HOLD': 'Chỉ giữ hộ',
  'RETURN': 'Hoàn trả',
  'DISPOSE': 'Hủy',
  'LOW': 'Báo gia đình sắp hết',
  'DEPLETED': 'Ghi dùng hết',
  'STOP': 'Ngừng sử dụng',
};

bool _failed(Map<String, dynamic> batch) {
  final checks = batch['intakeChecks'] as Map?;
  return checks != null && checks.values.any((ok) => ok == false);
}

String _name(Map<String, dynamic> batch) => batch['customName'] as String? ?? 'Thuốc #${batch['medicationId']}';

class _FamilyMedicationScreenState extends State<FamilyMedicationScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _residents;
  Map<String, dynamic>? _resident;
  List<Map<String, dynamic>>? _batches;
  List<Map<String, dynamic>> _prescriptions = const [];
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadResidents();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadResidents() async {
    final q = _search.text.trim();
    try {
      final page = await widget.api.get('/residents${q.isEmpty ? '' : '?q=${Uri.encodeQueryComponent(q)}'}');
      if (mounted) {
        setState(() {
          _residents = (page?['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  Future<void> _loadBatches() async {
    final id = _resident!['id'] as int;
    try {
      final batches = (await widget.api.getList('/residents/$id/family-medications')).cast<Map<String, dynamic>>();
      final prescriptions = (await widget.api.getList('/residents/$id/prescriptions?status=ACTIVE&status=SUSPENDED'))
          .cast<Map<String, dynamic>>()
          .where((p) => p['medicationSource'] == 'FAMILY_SENT')
          .toList();
      if (mounted) {
        setState(() {
          _batches = batches;
          _prescriptions = prescriptions;
          _error = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  Future<void> _sheet(Widget Function(BuildContext) builder) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: builder,
    );
    if (message == null || !mounted) return;
    setState(() => _message = message);
    await _loadBatches();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_resident == null ? 'Thuốc gia đình gửi' : _residentName())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
          if (_message != null) Semantics(liveRegion: true, child: Text(_message!)),
          if (_resident == null) ..._pickResident(theme) else ..._batchList(theme),
        ],
      ),
    );
  }

  String _residentName() =>
      (_resident!['personalInfo'] as Map?)?['fullName'] as String? ?? 'Người cao tuổi #${_resident!['id']}';

  List<Widget> _pickResident(ThemeData theme) => [
    TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _loadResidents(),
      decoration: InputDecoration(
        labelText: 'Tìm người cao tuổi',
        suffixIcon: IconButton(icon: const Icon(Icons.search), tooltip: 'Tìm', onPressed: _loadResidents),
      ),
    ),
    if (_residents == null && _error == null) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
    for (final r in _residents ?? const <Map<String, dynamic>>[])
      ListTile(
        title: Text((r['personalInfo'] as Map?)?['fullName'] as String? ?? 'Người cao tuổi #${r['id']}'),
        subtitle: Text('Mã ${r['id']}'),
        onTap: () {
          setState(() {
            _resident = r;
            _batches = null;
            _message = null;
          });
          _loadBatches();
        },
      ),
  ];

  List<Widget> _batchList(ThemeData theme) => [
    Row(
      children: [
        TextButton(
          onPressed: () => setState(() {
            _resident = null;
            _batches = null;
          }),
          child: const Text('Đổi người cao tuổi'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => _sheet(
            (_) => _ReceiveSheet(api: widget.api, residentId: _resident!['id'] as int, newKey: widget.newKey),
          ),
          child: const Text('Tiếp nhận lô mới'),
        ),
      ],
    ),
    if (_batches == null && _error == null) const LinearProgressIndicator(),
    if (_batches != null && _batches!.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có lô thuốc gia đình gửi.')),
    for (final b in _batches ?? const <Map<String, dynamic>>[])
      Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name(b), style: theme.textTheme.titleMedium),
              Text(
                '${b['concentration']}, lúc nhận ${b['quantity']} ${b['unit']}; hạn ${b['expiryDate']}',
                style: theme.textTheme.bodySmall,
              ),
              Text(
                '${_status[b['status']] ?? b['status']}${b['status'] == 'DISPOSED' && b['disposeKind'] != null ? ' ${_disposeKind[b['disposeKind']]}' : ''}',
                style: theme.textTheme.labelLarge,
              ),
              if (b['intakeChecks'] case final Map<String, dynamic> checks)
                Text(
                  'Kiểm tra tiếp nhận: ${_checks.map((c) => '${c.$2} ${checks[c.$1] == true ? 'đạt' : 'không đạt'}').join('; ')}',
                  style: theme.textTheme.bodySmall,
                )
              else
                Text('Lô cũ chưa kiểm tra khi tiếp nhận.', style: theme.textTheme.bodySmall),
              if (b['witness'] != null) Text('Người chứng kiến: ${b['witness']}', style: theme.textTheme.bodySmall),
              Wrap(
                spacing: 8,
                children: [
                  for (final action in _actions[b['status']] ?? const <String>[])
                    OutlinedButton(
                      onPressed: action == 'USE' && _failed(b)
                          ? null
                          : () => _sheet(
                              (_) => _ActionSheet(
                                api: widget.api,
                                action: action,
                                batch: b,
                                prescriptions: _prescriptions,
                                newKey: widget.newKey,
                              ),
                            ),
                      child: Text(_label[action]!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
  ];
}

TextField _field(TextEditingController c, String label, {TextInputType? keyboard, String? error, int lines = 1}) =>
    TextField(
      controller: c,
      keyboardType: keyboard,
      maxLines: lines,
      decoration: InputDecoration(labelText: label, errorText: error),
    );

class _ReceiveSheet extends StatefulWidget {
  const _ReceiveSheet({required this.api, required this.residentId, required this.newKey});
  final ApiClient api;
  final int residentId;
  final String Function() newKey;

  @override
  State<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends State<_ReceiveSheet> {
  final name = TextEditingController();
  final concentration = TextEditingController();
  final quantity = TextEditingController();
  final unit = TextEditingController(text: 'viên');
  final expiry = TextEditingController();
  final packaging = TextEditingController();
  final deliverer = TextEditingController();
  final relationship = TextEditingController();
  bool hasPrescription = false;
  final ok = {for (final c in _checks) c.$1: true};
  bool submitted = false;
  bool busy = false;
  String? error;
  late final String key = widget.newKey();

  bool get missing =>
      name.text.trim().isEmpty ||
      concentration.text.trim().isEmpty ||
      (double.tryParse(quantity.text.trim().replaceAll(',', '.')) ?? 0) <= 0 ||
      DateTime.tryParse(expiry.text.trim()) == null ||
      packaging.text.trim().isEmpty ||
      deliverer.text.trim().isEmpty;

  Future<void> save() async {
    setState(() => submitted = true);
    if (missing) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.post(
        '/residents/${widget.residentId}/family-medications',
        {
          'customName': name.text.trim(),
          'concentration': concentration.text.trim(),
          'quantity': double.parse(quantity.text.trim().replaceAll(',', '.')),
          'unit': unit.text.trim(),
          'expiryDate': expiry.text.trim(),
          'packagingCondition': packaging.text.trim(),
          'hasPrescription': hasPrescription,
          'deliverer': {
            'type': 'FAMILY_MEMBER',
            'fullName': deliverer.text.trim(),
            if (relationship.text.trim().isNotEmpty) 'relationship': relationship.text.trim(),
          },
          'receivedAt': vnIso(DateTime.now()),
          'intakeChecks': ok,
        },
        headers: {'Idempotency-Key': key},
      );
      if (mounted) Navigator.pop(context, 'Đã tiếp nhận thuốc ${name.text.trim()}.');
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          error = backendMessage(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Tiếp nhận thuốc gia đình gửi', style: Theme.of(context).textTheme.titleLarge),
          _field(name, 'Tên thuốc'),
          _field(concentration, 'Hàm lượng'),
          _field(quantity, 'Số lượng lúc nhận', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          _field(unit, 'Đơn vị'),
          _field(expiry, 'Hạn dùng (yyyy-MM-dd)', keyboard: TextInputType.datetime),
          _field(packaging, 'Tình trạng bao bì'),
          _field(deliverer, 'Người giao'),
          _field(relationship, 'Quan hệ'),
          SwitchListTile(
            value: hasPrescription,
            onChanged: busy ? null : (v) => setState(() => hasPrescription = v),
            title: const Text('Có toa hoặc đơn kèm theo'),
            contentPadding: EdgeInsets.zero,
          ),
          const Text('Kiểm tra khi tiếp nhận (bật = Đạt)'),
          for (final c in _checks)
            SwitchListTile(
              value: ok[c.$1]!,
              onChanged: busy ? null : (v) => setState(() => ok[c.$1] = v),
              title: Text('${c.$2} đạt'),
              contentPadding: EdgeInsets.zero,
            ),
          if (submitted && missing)
            Text(
              'Nhập đủ tên thuốc, hàm lượng, số lượng, hạn dùng, bao bì, người giao.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (error != null) Semantics(liveRegion: true, child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 12),
          FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Đang lưu…' : 'Lưu tiếp nhận')),
        ],
      ),
    ),
  );
}

class _ActionSheet extends StatefulWidget {
  const _ActionSheet({
    required this.api,
    required this.action,
    required this.batch,
    required this.prescriptions,
    required this.newKey,
  });
  final ApiClient api;
  final String action;
  final Map<String, dynamic> batch;
  final List<Map<String, dynamic>> prescriptions;
  final String Function() newKey;

  @override
  State<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends State<_ActionSheet> {
  final reason = TextEditingController();
  final note = TextEditingController();
  final quantity = TextEditingController();
  final recipient = TextEditingController();
  final relationship = TextEditingController();
  final witness = TextEditingController();
  final representative = TextEditingController();
  final method = TextEditingController();
  final selected = <int>{};
  bool packagingRecognizable = true;
  String kind = 'FAMILY_REQUEST';
  bool submitted = false;
  bool busy = false;
  String? error;
  late final String key = widget.newKey();

  Map<String, dynamic> get batch => widget.batch;
  bool get _expiredNow {
    final expiry = DateTime.tryParse(batch['expiryDate'] as String? ?? '');
    return expiry != null && expiry.isBefore(DateTime.now().subtract(const Duration(days: 1)));
  }

  bool get invalid {
    final count = double.tryParse(quantity.text.trim().replaceAll(',', '.'));
    return switch (widget.action) {
      'USE' => selected.isEmpty || _failed(batch),
      'HOLD' || 'STOP' => reason.text.trim().isEmpty,
      'RETURN' => count == null || recipient.text.trim().isEmpty || witness.text.trim().isEmpty,
      'DISPOSE' =>
        count == null ||
            witness.text.trim().isEmpty ||
            reason.text.trim().isEmpty ||
            (kind == 'FAMILY_REQUEST' && (int.tryParse(representative.text.trim()) == null || method.text.trim().isEmpty)),
      _ => false,
    };
  }

  Future<void> save() async {
    setState(() => submitted = true);
    if (invalid) return;
    setState(() {
      busy = true;
      error = null;
    });
    final id = batch['id'];
    final headers = {'Idempotency-Key': key};
    final count = double.tryParse(quantity.text.trim().replaceAll(',', '.'));
    try {
      switch (widget.action) {
        case 'USE':
          await widget.api.post('/family-medications/$id/confirm-use', {
            'prescriptionIds': selected.toList(),
            'packagingRecognizable': packagingRecognizable,
            if (batch['medicationId'] == null)
              'medicationId': widget.prescriptions.firstWhere((p) => p['id'] == selected.first)['medicationId'],
          }, headers: headers);
        case 'HOLD':
          await widget.api.post('/family-medications/$id/hold-only', {'reason': reason.text.trim()}, headers: headers);
        case 'STOP':
          await widget.api.post('/family-medications/$id/stop-use', {'reason': reason.text.trim()}, headers: headers);
        case 'LOW':
          await widget.api.post('/family-medications/$id/notify-running-low', {
            if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
          }, headers: headers);
        case 'DEPLETED':
          await widget.api.post('/family-medications/$id/mark-depleted', <String, dynamic>{}, headers: headers);
        case 'RETURN':
          await widget.api.post('/family-medications/$id/return', {
            'quantity': count,
            'recipient': {
              'type': 'FAMILY_MEMBER',
              'fullName': recipient.text.trim(),
              if (relationship.text.trim().isNotEmpty) 'relationship': relationship.text.trim(),
            },
            'returnedAt': vnIso(DateTime.now()),
            'witness': witness.text.trim(),
          }, headers: headers);
        case 'DISPOSE':
          await widget.api.post('/family-medications/$id/dispose', {
            'quantity': count,
            'kind': kind,
            if (kind == 'FAMILY_REQUEST') ...{
              'representativeId': int.parse(representative.text.trim()),
              'requestMethod': method.text.trim(),
            },
            'witness': witness.text.trim(),
            'reason': reason.text.trim(),
          }, headers: headers);
      }
      if (mounted) Navigator.pop(context, '${_label[widget.action]}: ${_name(batch)}.');
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          error = backendMessage(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final err = TextStyle(color: theme.colorScheme.error);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_label[widget.action]!, style: theme.textTheme.titleLarge),
            Text('${_name(batch)}, lô #${batch['id']}', style: theme.textTheme.bodySmall),
            if (widget.action == 'USE') ...[
              if (_failed(batch)) Text('Lô có mục kiểm tra khi tiếp nhận Không đạt, không dùng được.', style: err),
              const Text('Đơn nguồn gia đình gửi cùng thuốc'),
              if (widget.prescriptions.isEmpty) const Text('Người cao tuổi chưa có đơn nguồn gia đình gửi.'),
              for (final p in widget.prescriptions)
                CheckboxListTile(
                  value: selected.contains(p['id']),
                  onChanged: busy
                      ? null
                      : (v) => setState(() => v == true ? selected.add(p['id'] as int) : selected.remove(p['id'])),
                  title: Text('Đơn #${p['id']}, liều ${p['dosage']}'),
                  contentPadding: EdgeInsets.zero,
                ),
              SwitchListTile(
                value: packagingRecognizable,
                onChanged: busy ? null : (v) => setState(() => packagingRecognizable = v),
                title: const Text('Bao bì nhận diện được thuốc'),
                contentPadding: EdgeInsets.zero,
              ),
              if (submitted && selected.isEmpty) Text('Chọn ít nhất một đơn.', style: err),
            ],
            if (widget.action == 'HOLD' || widget.action == 'STOP') _field(reason, 'Lý do', lines: 3),
            if (widget.action == 'LOW') _field(note, 'Ghi chú gửi gia đình (không bắt buộc)', lines: 2),
            if (widget.action == 'DEPLETED') const Text('Lô chuyển Đã dùng hết và gỡ liên kết đơn.'),
            if (widget.action == 'RETURN') ...[
              _field(quantity, 'Số lượng đếm thực tế lúc trả', keyboard: const TextInputType.numberWithOptions(decimal: true)),
              _field(recipient, 'Người nhận'),
              _field(relationship, 'Quan hệ'),
              _field(witness, 'Người chứng kiến'),
            ],
            if (widget.action == 'DISPOSE') ...[
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Loại hủy'),
                items: [
                  const DropdownMenuItem(value: 'FAMILY_REQUEST', child: Text('Theo yêu cầu gia đình')),
                  DropdownMenuItem(value: 'EXPIRED', enabled: _expiredNow, child: const Text('Do hết hạn dùng')),
                ],
                onChanged: busy ? null : (v) => setState(() => kind = v ?? kind),
              ),
              if (kind == 'FAMILY_REQUEST') ...[
                _field(representative, 'Mã người đại diện yêu cầu', keyboard: TextInputType.number),
                _field(method, 'Hình thức yêu cầu'),
              ],
              _field(quantity, 'Số lượng đếm thực tế', keyboard: const TextInputType.numberWithOptions(decimal: true)),
              _field(witness, 'Người chứng kiến'),
              _field(reason, 'Lý do', lines: 2),
            ],
            if (submitted && invalid && widget.action != 'USE') Text('Nhập đủ các ô bắt buộc.', style: err),
            if (error != null) Semantics(liveRegion: true, child: Text(error!, style: err)),
            const SizedBox(height: 12),
            FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Đang lưu…' : _label[widget.action]!)),
          ],
        ),
      ),
    );
  }
}
