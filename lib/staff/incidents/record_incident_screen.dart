import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../alerts/emergency_assist_screen.dart' show dialPhone;
import 'bf06_shared.dart';
import 'incidents_screen.dart' show IncidentDetailPage;

// Báo sự cố trên app nhân viên (luồng 2.2, 2.3 SRS; 007 FR-040 → FR-042; BF-06), bốn bước mỗi bước một việc: chọn người
// cao tuổi → chọn loại (ô lớn) → đang xảy ra hay đã xử lý xong, mức, giờ, mô tả → xem lại rồi ghi. "Đã xử lý xong" là
// ghi nhận sau (`recordedLater`): chỉ lưu hồ sơ, không báo khẩn, bắt buộc nói đã báo người nhà chưa. Nút Quay lại (và
// cử chỉ quay lại) lùi một bước, không thoát cả luồng. Ghi xong hiện ai đã được báo và việc tiếp theo; trả `true`.

const _familyMethods = [('PHONE', 'Gọi điện'), ('IN_PERSON', 'Gặp trực tiếp'), ('MESSAGE', 'Nhắn tin')];

class RecordIncidentScreen extends StatefulWidget {
  const RecordIncidentScreen({super.key, required this.api, this.residentId, this.dial = dialPhone});
  final ApiClient api;
  final int? residentId;
  final Future<bool> Function(String phone) dial;

  @override
  State<RecordIncidentScreen> createState() => _RecordIncidentScreenState();
}

class _RecordIncidentScreenState extends State<RecordIncidentScreen> {
  late final ResidentDirectory _dir = ResidentDirectory(widget.api);
  final _description = TextEditingController();
  final _lowerReason = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;

  int _step = 0;
  List<ResidentInfo>? _residents;
  List<ResidentInfo> _found = const [];
  List<Map<String, dynamic>>? _types;
  List<Map<String, dynamic>> _floors = const [];

  ResidentInfo? _resident;
  bool _noResident = false;
  Map<String, dynamic>? _type;
  String? _level;
  bool _later = false;
  late DateTime _at = DateTime.now();
  String? _familyState;
  String _familyMethod = 'PHONE';

  bool _busy = false, _submitted = false;
  String? _error, _key;
  int? _existingId;
  Map<String, dynamic>? _saved;
  Map<String, dynamic>? _call;
  String? _callResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    _lowerReason.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final types = await loadIncidentTypes(widget.api);
      var residents = const <ResidentInfo>[];
      try {
        residents = await _dir.inScope();
      } on Exception {
        // Không lấy được danh sách gợi ý: vẫn tìm theo tên được
      }
      List<Map<String, dynamic>> floors = const [];
      try {
        floors = (await widget.api.getList('/incident-floors')).cast<Map<String, dynamic>>();
      } on Exception {
        // Chỉ cần khi ghi sự cố không gắn người cao tuổi
      }
      ResidentInfo? preset;
      if (widget.residentId != null) {
        // Mở từ công việc của một cụ: cụ đã chọn sẵn, vào thẳng bước chọn loại
        preset = await _dir.lookup(widget.residentId) ?? ResidentInfo(id: widget.residentId!, name: 'Người cao tuổi');
      }
      if (!mounted) return;
      setState(() {
        _types = types;
        _residents = residents;
        _floors = floors;
        if (preset != null) {
          _resident = preset;
          _step = 1;
        }
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final found = await _dir.search(q);
        if (mounted) setState(() => _found = found);
      } on Exception {
        // Giữ danh sách cũ
      }
    });
  }

  bool get _lowerNeeded {
    final def = _type?['defaultLevel'] as String?;
    if (def == null || _level == null || _later) return false;
    return levelOrder.indexOf(_level!) > levelOrder.indexOf(def);
  }

  void _pickResident(ResidentInfo? r) => setState(() {
    _resident = r;
    _noResident = r == null;
    if (_type != null && _noResident && _type!['allowsNoResident'] != true) _type = null;
    _step = 1;
  });

  void _pickType(Map<String, dynamic> t) => setState(() {
    _type = t;
    _level = t['defaultLevel'] as String?;
    _step = 2;
  });

  String? _step2Error() {
    if (_level == null) return 'Chọn mức độ';
    if (_lowerNeeded && _lowerReason.text.trim().isEmpty) return 'Nhập lý do chọn mức thấp hơn';
    if (_at.isAfter(DateTime.now().add(const Duration(minutes: 1)))) return 'Giờ không được ở tương lai';
    if (_later && _familyState == null) return 'Chọn đã báo người nhà hay chưa';
    if (_type?['code'] == 'OTHER_HEALTH_CARE' && _description.text.trim().isEmpty) return 'Loại "Khác" cần mô tả';
    return null;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    setState(() => _at = DateTime(now.year, now.month, now.day, picked.hour, picked.minute));
  }

  Future<void> _submit({bool despiteOpen = false}) async {
    final type = _type!;
    final description = _description.text.trim().isEmpty
        ? '${type['name']}${_resident == null ? '' : ', ${_resident!.name}'}'
        : _description.text.trim();
    final floor = _floors.where((f) => f['current'] == true).firstOrNull ?? _floors.firstOrNull;
    final body = <String, dynamic>{
      if (_resident != null) 'residentId': _resident!.id,
      if (_noResident && floor != null) 'floorAreaId': floor['id'],
      'incidentTypeId': type['id'],
      'level': _level,
      'discoveredAt': vietnamIso(_at),
      'description': description,
      if (_lowerNeeded) 'lowerLevelReason': _lowerReason.text.trim(),
      if (despiteOpen) 'createDespiteOpen': true,
      if (_later) ...{
        'recordedLater': true,
        'familyNotice': _familyState == 'INFORMED'
            ? {'state': 'INFORMED', 'method': _familyMethod, 'at': vietnamIso(DateTime.now())}
            : {'state': 'NOT_YET'},
      },
    };
    _key ??= newIdempotencyKey();
    setState(() {
      _busy = true;
      _error = null;
      _existingId = null;
    });
    try {
      final result = await widget.api.post('/incidents', body, headers: {'Idempotency-Key': _key!});
      if (!mounted) return;
      setState(() => _saved = (result?['incident'] as Map<String, dynamic>?) ?? result ?? const {});
    } on ApiProblem catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.errorCode == 'OPEN_EMERGENCY_INCIDENT_EXISTS' && e.properties['incidentId'] != null) {
          _existingId = (e.properties['incidentId'] as num).toInt();
        } else {
          _error = backendMessage(e);
        }
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restart() => setState(() {
    _step = 0;
    _resident = null;
    _noResident = false;
    _type = null;
    _level = null;
    _later = false;
    _at = DateTime.now();
    _familyState = null;
    _description.clear();
    _lowerReason.clear();
    _saved = null;
    _call = null;
    _callResult = null;
    _key = null;
    _submitted = false;
  });

  Future<void> _call115() async {
    final id = _saved?['id'];
    if (id != null && _call == null) {
      try {
        final call = await widget.api.post(
          '/incidents/$id/call-115',
          {},
          headers: {'Idempotency-Key': newIdempotencyKey()},
        );
        if (mounted) setState(() => _call = call);
      } catch (_) {
        // Không ghi được lượt gọi vẫn quay số: gọi cấp cứu không chờ máy chủ
      }
    }
    await widget.dial('115');
  }

  Future<void> _callResultTap(String result) async {
    final id = _call?['id'];
    if (id == null) return;
    try {
      await widget.api.post('/call-115-attempts/$id/result', {'result': result});
      if (mounted) setState(() => _callResult = result);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final body = saved != null
        ? _done(context, saved)
        : (_types == null
              ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
              : _stepBody(context));
    // Lùi một bước thay vì thoát cả luồng; bước đầu (hoặc đã ghi) thì đóng màn
    return PopScope(
      canPop: _step == 0 || saved != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) setState(() => _step -= 1);
      },
      child: Scaffold.maybeOf(context) != null
          ? body
          : Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  tooltip: 'Quay lại',
                  icon: const Icon(LucideIcons.chevronLeft),
                  onPressed: () => Navigator.of(context).maybePop(saved == null ? null : true),
                ),
                title: Text(saved == null ? 'Báo sự cố' : 'Đã ghi sự cố'),
              ),
              body: body,
            ),
    );
  }

  Widget _progress(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Bước ${_step + 1} trên 4',
      child: Row(
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  color: i <= _step ? scheme.primary : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final who = _resident?.name ?? 'Không gắn với cụ nào';
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        minTileHeight: 56,
        title: Text(_type == null ? who : '$who · ${typeShortName(_type!)}', style: text.titleMedium),
        subtitle: _resident?.place.isNotEmpty ?? false ? Text(_resident!.place) : null,
        trailing: TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Đổi')),
      ),
    );
  }

  Widget _stepBody(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final children = <Widget>[_progress(context), const SizedBox(height: 16)];
    switch (_step) {
      case 0:
        final list = _search.text.trim().length >= 2 ? _found : (_residents ?? const <ResidentInfo>[]);
        children.addAll([
          Text('Sự cố xảy ra với ai?', style: text.headlineSmall),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: const InputDecoration(labelText: 'Tìm tên hoặc phòng', prefixIcon: Icon(LucideIcons.search)),
            onChanged: _onSearch,
          ),
          const SizedBox(height: 8),
          for (final r in list)
            Card(
              child: ListTile(
                minTileHeight: 60,
                leading: CircleAvatar(child: Text(r.name.trim().split(' ').last.characters.first)),
                title: Text(r.name, style: text.titleMedium),
                subtitle: r.place.isEmpty ? null : Text(r.place),
                onTap: () => _pickResident(r),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: () => _pickResident(null),
              child: const Text('Không gắn với cụ nào (đồ đạc, cơ sở vật chất)'),
            ),
          ),
        ]);
      case 1:
        final types = _noResident ? _types!.where((t) => t['allowsNoResident'] == true).toList() : _types!;
        children.addAll([
          _summary(context),
          const SizedBox(height: 16),
          Text('Chuyện gì đã xảy ra?', style: text.headlineSmall),
          const SizedBox(height: 12),
          ChoiceGrid(
            children: [
              for (final t in types)
                ChoiceTile(
                  icon: typeIcon(t['code'] as String?),
                  label: typeShortName(t),
                  selected: _type?['id'] == t['id'],
                  onTap: () => _pickType(t),
                ),
            ],
          ),
        ]);
      case 2:
        children.addAll(_step2(context));
      default:
        children.addAll(_review(context));
    }
    return ListView(padding: const EdgeInsets.all(16), children: children);
  }

  List<Widget> _step2(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final error = _submitted ? _step2Error() : null;
    Widget seg(String label, bool on, VoidCallback onTap) => Expanded(
      child: SizedBox(
        height: 52,
        child: on
            ? FilledButton(onPressed: onTap, child: Text(label))
            : OutlinedButton(onPressed: onTap, child: Text(label)),
      ),
    );
    return [
      _summary(context),
      const SizedBox(height: 12),
      Row(
        children: [
          seg('Đang xảy ra', !_later, () => setState(() => _later = false)),
          const SizedBox(width: 8),
          seg('Đã xử lý xong', _later, () => setState(() => _later = true)),
        ],
      ),
      if (_later)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _Note(
            text: 'Chỉ lưu hồ sơ, không báo khẩn cho bác sĩ, trưởng tầng, quản lý.',
            tone: scheme.secondaryContainer,
          ),
        ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: Text('Mức độ', style: text.titleMedium)),
          TextButton(onPressed: () => _showLevels(context), child: const Text('Mức nào là gì?')),
        ],
      ),
      Row(
        children: [
          for (final l in levelOrder) ...[
            if (l != levelOrder.first) const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 52,
                child: _level == l
                    ? FilledButton(
                        style: l == 'CRITICAL'
                            ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
                            : null,
                        onPressed: () {},
                        child: FittedBox(child: Text(levelNames[l]!, maxLines: 1)),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                        onPressed: () => setState(() => _level = l),
                        child: FittedBox(child: Text(levelNames[l]!, maxLines: 1)),
                      ),
              ),
            ),
          ],
        ],
      ),
      if (_level != null && !_later)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _Note(
            text: levelMeaning[_level]!,
            tone: _level == 'CRITICAL' ? scheme.errorContainer : scheme.secondaryContainer,
          ),
        ),
      if (_lowerNeeded) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _lowerReason,
          decoration: const InputDecoration(labelText: 'Lý do chọn mức thấp hơn gợi ý'),
          onChanged: (_) => setState(() {}),
        ),
      ],
      const SizedBox(height: 16),
      Text(_later ? 'Xảy ra lúc' : 'Lúc nào?', style: text.titleMedium),
      const SizedBox(height: 6),
      Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          minTileHeight: 52,
          title: Text(
            '${!_later && DateTime.now().difference(_at).inMinutes.abs() < 2 ? 'Vừa xong' : 'Hôm nay'} · '
            '${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}',
            style: text.titleMedium,
          ),
          trailing: TextButton(onPressed: _pickTime, child: const Text('Đổi giờ')),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _description,
        minLines: 2,
        maxLines: 5,
        maxLength: 2000,
        decoration: InputDecoration(labelText: _later ? 'Mô tả và đã xử lý thế nào' : 'Mô tả ngắn (không bắt buộc)'),
        onChanged: (_) => setState(() {}),
      ),
      if (_later) ...[
        Text('Đã báo người nhà chưa?', style: text.titleMedium),
        const SizedBox(height: 6),
        Row(
          children: [
            seg('Đã báo', _familyState == 'INFORMED', () => setState(() => _familyState = 'INFORMED')),
            const SizedBox(width: 8),
            seg('Chưa báo', _familyState == 'NOT_YET', () => setState(() => _familyState = 'NOT_YET')),
          ],
        ),
        if (_familyState == 'INFORMED') ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in _familyMethods)
                ChoiceChip(
                  label: Text(label),
                  selected: _familyMethod == value,
                  onSelected: (_) => setState(() => _familyMethod = value),
                ),
            ],
          ),
        ],
      ],
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(error, style: text.bodyLarge?.copyWith(color: scheme.error)),
        ),
      const SizedBox(height: 16),
      SizedBox(
        height: 56,
        child: FilledButton(
          onPressed: () {
            setState(() => _submitted = true);
            if (_step2Error() == null) setState(() => _step = 3);
          },
          child: const Text('Tiếp'),
        ),
      ),
    ];
  }

  List<Widget> _review(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget row(String label, String value, int step) => ListTile(
      minTileHeight: 52,
      title: Text(label, style: text.bodySmall),
      subtitle: Text(value, style: text.titleMedium),
      trailing: TextButton(onPressed: () => setState(() => _step = step), child: const Text('Sửa')),
    );
    final hhmmAt = '${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}';
    final notice = _later
        ? 'Chỉ lưu hồ sơ, báo cho điều dưỡng phụ trách, trưởng tầng; không báo khẩn.'
        : _level == 'CRITICAL'
        ? 'Ghi xong hệ thống báo ngay bác sĩ trực, trưởng tầng, quản lý, người liên hệ chính.'
        : 'Ghi xong hệ thống báo người phụ trách theo mức.';
    return [
      Text('Kiểm tra rồi ghi', style: text.headlineSmall),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            row(
              'Cụ',
              [
                _resident?.name ?? 'Không gắn với cụ nào',
                _resident?.place ?? '',
              ].where((s) => s.isNotEmpty).join(' · '),
              0,
            ),
            row('Loại · mức', '${typeShortName(_type!)} · ${levelNames[_level]}', 1),
            row(_later ? 'Đã xử lý xong, xảy ra lúc' : 'Lúc', '$hhmmAt hôm nay', 2),
            if (_description.text.trim().isNotEmpty) row('Mô tả', _description.text.trim(), 2),
            if (_later)
              row(
                'Người nhà',
                _familyState == 'INFORMED'
                    ? 'Đã báo (${_familyMethods.firstWhere((m) => m.$1 == _familyMethod).$2.toLowerCase()})'
                    : 'Chưa báo',
                2,
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Text(notice, style: text.bodyMedium),
      if (_existingId != null) ...[
        const SizedBox(height: 12),
        _Note(
          text: 'Cụ đang có sự cố Khẩn cấp chưa đóng (#$_existingId). Cùng vụ thì ghi diễn biến vào sự cố đó.',
          tone: scheme.errorContainer,
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => IncidentDetailPage(api: widget.api, incidentId: _existingId!),
            ),
          ),
          child: Text('Mở sự cố #$_existingId'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _submit(despiteOpen: true),
          child: const Text('Vụ khác, vẫn ghi riêng'),
        ),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: text.bodyLarge?.copyWith(color: scheme.error)),
        ),
      const SizedBox(height: 16),
      SizedBox(
        height: 60,
        child: FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Đang ghi…' : (_later ? 'Ghi nhận' : 'Ghi sự cố')),
        ),
      ),
    ];
  }

  Widget _done(BuildContext context, Map<String, dynamic> saved) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final id = saved['id'];
    final critical = _level == 'CRITICAL' && !_later;
    final who = _later
        ? 'Đã lưu hồ sơ, báo điều dưỡng phụ trách và trưởng tầng.'
        : critical
        ? 'Hệ thống đã báo bác sĩ trực, trưởng tầng, quản lý viện và người liên hệ chính.'
        : 'Hệ thống đã báo người phụ trách theo mức.';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Icon(LucideIcons.circleCheck, size: 64, color: scheme.primary),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            _later ? 'Đã ghi nhận sau' : 'Đã ghi sự cố${id == null ? '' : ' #$id'}',
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [_resident?.name ?? 'Không gắn cụ', typeShortName(_type!), levelNames[_level]].join(' · '),
          textAlign: TextAlign.center,
          style: text.titleMedium,
        ),
        const SizedBox(height: 12),
        _Note(text: who, tone: scheme.secondaryContainer),
        const SizedBox(height: 16),
        if (critical) ...[
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error, width: 1.5),
              ),
              onPressed: _call115,
              icon: const Icon(LucideIcons.phone),
              label: const Text('Gọi cấp cứu 115'),
            ),
          ),
          if (_call != null && _callResult == null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(onPressed: () => _callResultTap('CONNECTED'), child: const Text('Đã gọi được')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _callResultTap('NOT_CONNECTED'),
                    child: const Text('Không gọi được'),
                  ),
                ),
              ],
            ),
          ],
          if (_callResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_callResult == 'CONNECTED' ? 'Đã ghi: đã gọi được 115.' : 'Đã ghi: không gọi được 115.'),
            ),
          const SizedBox(height: 8),
        ],
        if (id != null)
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => IncidentDetailPage(api: widget.api, incidentId: id as int),
                ),
              ),
              child: const Text('Xem sự cố'),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: 52,
          child: OutlinedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xong')),
        ),
        TextButton(onPressed: _restart, child: const Text('Báo thêm một sự cố khác')),
        if (_error != null) Text(_error!, style: text.bodyMedium?.copyWith(color: scheme.error)),
      ],
    );
  }

  void _showLevels(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Mức nào là gì?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('Chọn theo việc cần làm ngay, không theo mức tổn thương.'),
        for (final (l, example) in const [
          ('CRITICAL', 'Ví dụ: ngã, mất ý thức, khó thở, sặc nghẹn · tiếp nhận ngay'),
          ('MEDIUM', 'Ví dụ: chỉ số bất thường, từ chối thuốc · trong 15 phút'),
          ('LOW', 'Ví dụ: bỏ bữa, khó ngủ · trong ca'),
        ])
          ListTile(minTileHeight: 64, leading: LevelPill(l), title: Text(levelMeaning[l]!), subtitle: Text(example)),
        const Text('Chọn thấp hơn gợi ý thì ghi lý do. Hạ khỏi Khẩn cấp về sau chỉ bác sĩ làm.'),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.tone});
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(10)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}
