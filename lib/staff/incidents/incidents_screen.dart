import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../alerts/emergency_assist_screen.dart' show dialPhone;
import 'bf06_shared.dart';
import 'record_incident_screen.dart';
import 'transfer_out_screen.dart';

/// Sự cố trên app nhân viên (007 T037, T042; US4, US5; FR-045, FR-047, FR-048, FR-049; BF-06). Danh sách có tên người cao
/// tuổi, loại, mức; chi tiết mở trang riêng: diễn biến và ghi nhanh một chạm, thẻ thông tin khẩn cấp (gọi người liên hệ
/// chính), Gọi 115, Chuyển viện (từ sự cố, kèm phiếu tóm tắt PDF), Đóng. Giao người, đổi mức, đính chính làm trên web.
class IncidentsScreen extends StatefulWidget {
  const IncidentsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<IncidentsScreen> createState() => _IncidentsScreenState();
}

class _IncidentsScreenState extends State<IncidentsScreen> {
  late final ResidentDirectory _dir = ResidentDirectory(widget.api);
  List<Map<String, dynamic>>? _incidents;
  Map<int, Map<String, dynamic>> _types = const {};
  final Map<int, ResidentInfo> _info = {};
  String? _error, _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_types.isEmpty) {
        _types = {for (final t in await loadIncidentTypes(widget.api)) t['id'] as int: t};
      }
      final rows = (await widget.api.getList(
        '/incidents?status=NEW&status=IN_PROGRESS&status=MONITORING',
      )).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _incidents = rows;
        _error = null;
      });
      for (final i in rows) {
        final id = (i['content'] as Map?)?['residentId'] as int?;
        if (id != null && !_info.containsKey(id)) {
          final info = await _dir.lookup(id);
          if (info != null && mounted) setState(() => _info[id] = info);
        }
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  Future<void> _report() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => RecordIncidentScreen(api: widget.api)));
    if (saved == true && mounted) {
      setState(() => _notice = 'Đã ghi nhận sự cố.');
    }
    await _load();
  }

  Future<void> _open(Map<String, dynamic> incident) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => IncidentDetailPage(api: widget.api, incidentId: incident['id'] as int, residents: _dir),
      ),
    );
    if (!mounted) return;
    setState(() => _notice = message);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _report,
              icon: const Icon(LucideIcons.plus),
              label: const Text('Báo sự cố'),
            ),
          ),
          if (_notice != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_notice!, style: text.bodyLarge),
              ),
            ),
          const SizedBox(height: 12),
          if (_error != null) ...[
            Text(_error!, style: text.bodyMedium),
            OutlinedButton(onPressed: _load, child: const Text('Tải lại')),
          ] else if (_incidents == null)
            const Center(child: CircularProgressIndicator())
          else if (_incidents!.isEmpty)
            Text('Không có sự cố đang xử lý.', style: text.bodyLarge)
          else
            for (final i in _incidents!)
              Builder(
                builder: (context) {
                  final content = (i['content'] as Map?) ?? const {};
                  final info = _info[content['residentId']];
                  final type = _types[i['currentTypeId'] ?? content['incidentTypeId']];
                  return Card(
                    child: ListTile(
                      minTileHeight: 72,
                      leading: Icon(typeIcon(type?['code'] as String?)),
                      title: Text(
                        info == null ? (content['residentId'] == null ? 'Không gắn cụ' : 'Người cao tuổi') : info.name,
                        style: text.titleMedium,
                      ),
                      subtitle: Text(
                        [
                          if (type != null) typeShortName(type),
                          hhmm(content['discoveredAt'] as String?),
                          incidentStatusNames[i['status']] ?? '${i['status']}',
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: LevelPill(i['level'] as String?),
                      onTap: () => _open(i),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

/// Chi tiết một sự cố, trang riêng có nút Quay lại; trả câu báo khi đã làm lệnh thay đổi trạng thái.
class IncidentDetailPage extends StatefulWidget {
  const IncidentDetailPage({
    super.key,
    required this.api,
    required this.incidentId,
    this.residents,
    this.dial = dialPhone,
  });

  final ApiClient api;
  final int incidentId;
  final ResidentDirectory? residents;
  final Future<bool> Function(String phone) dial;

  @override
  State<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends State<IncidentDetailPage> {
  late final ResidentDirectory _dir = widget.residents ?? ResidentDirectory(widget.api);
  Map<String, dynamic>? _i;
  ResidentInfo? _info;
  Map<int, Map<String, dynamic>> _types = const {};
  List<Map<String, dynamic>> _progressionTypes = const [];
  final _keys = <String, String>{};
  Map<String, dynamic>? _call;
  String? _callResult, _error, _done;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_types.isEmpty) {
        _types = {for (final t in await loadIncidentTypes(widget.api)) t['id'] as int: t};
        _progressionTypes = (await widget.api.getList('/progression-types')).cast<Map<String, dynamic>>();
      }
      final i = await widget.api.get('/incidents/${widget.incidentId}');
      if (!mounted || i == null) return;
      setState(() => _i = i);
      final residentId = (i['content'] as Map?)?['residentId'] as int?;
      if (_info == null && residentId != null) {
        final info = await _dir.lookup(residentId);
        if (mounted) setState(() => _info = info);
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  List<String> get _commands => ((_i?['allowedCommands'] as List?) ?? const []).cast<String>();

  Future<bool> _post(String path, Map<String, dynamic> body, String key) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.post(path, body, headers: {'Idempotency-Key': _keys.putIfAbsent(key, newIdempotencyKey)});
      _keys.remove(key);
      return true;
    } on ApiUnreachable {
      if (mounted) setState(() => _error = 'Mất kết nối, lệnh chưa được gửi. Thử lại khi có mạng.');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  int? _progressionId(String code) =>
      _progressionTypes.where((t) => t['code'] == code).map((t) => t['id'] as int).firstOrNull;

  Future<void> _quick(String code, String content) async {
    final typeId = _progressionId(code);
    if (typeId == null) return;
    if (await _post('/incidents/${widget.incidentId}/progressions', {
      'progressionTypeId': typeId,
      'content': content,
    }, 'p:$content')) {
      setState(() => _done = 'Đã ghi: $content.');
      await _load();
    }
  }

  Future<void> _note() async {
    final content = await askText(context, title: 'Ghi diễn biến', label: 'Đã làm gì, thấy gì');
    if (content != null) await _quick('OTHER_ACTION', content);
  }

  Future<void> _close() async {
    final resolution = await askText(context, title: 'Đóng sự cố', label: 'Kết quả xử lý', action: 'Đóng sự cố');
    if (resolution == null || !mounted) return;
    if (await _post('/incidents/${widget.incidentId}/close', {'resolution': resolution}, 'close') && mounted) {
      Navigator.of(context).pop('Đã đóng sự cố.');
    }
  }

  Future<void> _simple(String command, String done, [Map<String, dynamic> body = const {}]) async {
    if (await _post('/incidents/${widget.incidentId}/$command', body, command)) {
      setState(() => _done = done);
      await _load();
    }
  }

  Future<void> _reopen() async {
    final reason = await askText(context, title: 'Mở lại xử lý', label: 'Lý do', action: 'Mở lại');
    if (reason != null) await _simple('reopen', 'Đã mở lại xử lý.', {'reason': reason});
  }

  Future<void> _transfer() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransferOutScreen(api: widget.api, incidentId: widget.incidentId, residentName: _info?.name),
      ),
    );
    if (done == true && mounted) {
      setState(() => _done = 'Đã chuyển viện.');
      await _load();
    }
  }

  Future<void> _call115() async {
    if (_call == null) {
      try {
        final call = await widget.api.post(
          '/incidents/${widget.incidentId}/call-115',
          {},
          headers: {'Idempotency-Key': _keys.putIfAbsent('call-115', newIdempotencyKey)},
        );
        if (mounted) setState(() => _call = call);
      } catch (_) {
        // Không ghi được lượt gọi vẫn quay số
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
      await _load();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  void _openCard() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EmergencyCardSheet(api: widget.api, incidentId: widget.incidentId, dial: widget.dial),
  );

  @override
  Widget build(BuildContext context) {
    final i = _i;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.of(context).pop(_done),
        ),
        title: Text('Sự cố #${widget.incidentId}'),
      ),
      body: i == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : RefreshIndicator(onRefresh: _load, child: _body(context, i)),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> i) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final content = (i['content'] as Map?) ?? const {};
    final type = _types[i['currentTypeId'] ?? content['incidentTypeId']];
    final progressions = ((i['progressions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final c = _commands;
    final open = i['status'] != 'CLOSED' && i['status'] != 'VOIDED';
    final critical = i['level'] == 'CRITICAL' || i['wasEmergency'] == true;
    final transferred =
        progressions.any((p) => p['typeCode'] == 'TRANSFERRED_OUT') &&
        !progressions.any((p) => p['typeCode'] == 'RETURNED_FROM_HOSPITAL');
    String pName(Object? id) =>
        _progressionTypes.where((t) => t['id'] == id).map((t) => '${t['name']}').firstOrNull ?? 'Diễn biến';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _info?.name ?? (content['residentId'] == null ? 'Không gắn cụ' : 'Người cao tuổi'),
                  style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (_info?.place.isNotEmpty ?? false) Text(_info!.place, style: text.bodyLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LevelPill(i['level'] as String?),
                    Text(incidentStatusNames[i['status']] ?? '${i['status']}', style: text.titleSmall),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (type != null) typeShortName(type),
                    hhmm(content['discoveredAt'] as String?),
                    if (i['assignee'] != null) 'phụ trách ${i['assignee']}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: text.bodyMedium,
                ),
                if ('${content['description'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${content['description']}', style: text.bodyLarge),
                ],
              ],
            ),
          ),
        ),
        if (transferred) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(10)),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Cụ đang ở bệnh viện. Khi cụ về, trưởng tầng ghi nhận ở hồ sơ cụ; không cần mở lại sự cố.'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Diễn biến', style: text.titleMedium),
                const SizedBox(height: 4),
                if (progressions.isEmpty) Text('Chưa ghi diễn biến.', style: text.bodyMedium),
                for (final p in progressions.reversed.take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 52, child: Text(hhmm(p['occurredAt'] as String?), style: text.bodyMedium)),
                        Expanded(
                          child: Text(
                            // Ghi nhanh, ghi chú: chỉ hiện nội dung, bỏ tên loại "Xử lý khác (ghi rõ)"
                            p['typeCode'] == 'OTHER_ACTION' && '${p['content'] ?? ''}'.isNotEmpty
                                ? '${p['content']}'
                                : '${pName(p['progressionTypeId'])}${'${p['content'] ?? ''}'.isEmpty ? '' : ' · ${p['content']}'}',
                            style: text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (open && c.contains('progressions')) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Đã tới nơi'),
                        onPressed: _busy ? null : () => _quick('OTHER_ACTION', 'Đã tới nơi'),
                      ),
                      ActionChip(
                        label: const Text('Đã sơ cứu'),
                        onPressed: _busy ? null : () => _quick('FIRST_AID', 'Đã sơ cứu tại chỗ'),
                      ),
                      ActionChip(
                        label: const Text('Đã báo bác sĩ'),
                        onPressed: _busy ? null : () => _quick('CALL_SUPPORT', 'Đã báo bác sĩ'),
                      ),
                      ActionChip(label: const Text('Ghi chú…'), onPressed: _busy ? null : _note),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_done != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_done!, style: text.titleSmall),
            ),
          ),
        // Một nút chính: chưa tiếp nhận thì Tiếp nhận, sau đó mới tới Chuyển viện
        if (open && c.contains('receive')) _primary('Tiếp nhận xử lý', () => _simple('receive', 'Đã tiếp nhận.')),
        if (open && c.contains('transfer-out') && !transferred)
          c.contains('receive') ? _secondary('Chuyển viện', _transfer) : _primary('Chuyển viện', _transfer),
        if (open && critical && !transferred) ...[
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
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (critical) Expanded(child: _secondary('Thẻ khẩn cấp', _openCard)),
            if (critical && open && c.contains('close')) const SizedBox(width: 8),
            if (open && c.contains('close')) Expanded(child: _secondary('Đóng sự cố', _close)),
          ],
        ),
        if (open && c.contains('move-to-monitoring'))
          TextButton(
            onPressed: _busy ? null : () => _simple('move-to-monitoring', 'Đã chuyển sang theo dõi.'),
            child: const Text('Chuyển sang theo dõi'),
          ),
        if (c.contains('reopen')) TextButton(onPressed: _busy ? null : _reopen, child: const Text('Mở lại xử lý')),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: text.bodyLarge?.copyWith(color: scheme.error)),
            ),
          ),
      ],
    );
  }

  Widget _primary(String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(
      height: 56,
      child: FilledButton(onPressed: _busy ? null : onPressed, child: Text(label)),
    ),
  );

  Widget _secondary(String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: SizedBox(
      height: 52,
      child: OutlinedButton(onPressed: _busy ? null : onPressed, child: Text(label)),
    ),
  );
}

/// Thẻ thông tin khẩn cấp (BR-M05-13): dị ứng, thuốc, bệnh nền, nguyện vọng cuối đời (xác nhận đã xem), gọi người liên
/// hệ chính. Chỉ có khi sự cố đã kích hoạt khẩn cấp; người không có quyền xem sức khỏe chỉ thấy nhận dạng.
class _EmergencyCardSheet extends StatefulWidget {
  const _EmergencyCardSheet({required this.api, required this.incidentId, required this.dial});
  final ApiClient api;
  final int incidentId;
  final Future<bool> Function(String phone) dial;

  @override
  State<_EmergencyCardSheet> createState() => _EmergencyCardSheetState();
}

const _wishChoices = {
  'TRANSFER_TO_HOSPITAL': 'Chuyển bệnh viện điều trị tích cực',
  'RETURN_HOME': 'Đưa về nhà',
  'STAY_PALLIATIVE': 'Ở lại viện chăm sóc giảm nhẹ',
};

class _EmergencyCardSheetState extends State<_EmergencyCardSheet> {
  Map<String, dynamic>? _card;
  String? _error, _done;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final card = await widget.api.get('/incidents/${widget.incidentId}/emergency-card');
      if (mounted) setState(() => _card = card);
    } on ApiUnreachable {
      if (mounted) setState(() => _error = 'Mất kết nối, chưa mở được thẻ khẩn cấp.');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  Future<void> _confirmWish() async {
    try {
      await widget.api.post(
        '/incidents/${widget.incidentId}/confirm-wish-check',
        {},
        headers: {'Idempotency-Key': newIdempotencyKey()},
      );
      if (mounted) setState(() => _done = 'Đã ghi: đã xem nguyện vọng.');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  String _items(String key) => ((_card?[key] as List?) ?? const [])
      .map((e) {
        if (e is! Map) return '$e';
        return '${e['name'] ?? e['substanceName'] ?? e['medicationName'] ?? e['title'] ?? e['description'] ?? ''}';
      })
      .where((s) => s.isNotEmpty)
      .join(' · ');

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final card = _card;
    if (card == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!, style: text.bodyLarge)),
      );
    }
    final id = (card['identification'] as Map?) ?? const {};
    final wish = card['endOfLifeWish'] as Map?;
    final contact = card['primaryContact'] as Map?;
    Widget row(String label, String value, {bool alert = false}) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 96, child: Text(label, style: text.bodySmall)),
                Expanded(
                  child: Text(value, style: text.titleSmall?.copyWith(color: alert ? scheme.error : null)),
                ),
              ],
            ),
          );
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Text('Thẻ khẩn cấp', style: text.titleLarge),
        Text('${id['fullName'] ?? ''}${id['roomBed'] != null ? ' · ${id['roomBed']}' : ''}', style: text.titleMedium),
        const SizedBox(height: 8),
        row(
          'Dị ứng',
          _items('allergies').isEmpty ? 'Chưa ghi nhận' : _items('allergies'),
          alert: _items('allergies').isNotEmpty,
        ),
        row('Thuốc đang dùng', _items('currentMedications')),
        row('Bệnh nền', _items('chronicConditions')),
        if (card['careNotes'] != null) row('Ghi chú', '${card['careNotes']}'),
        if (wish != null) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Nguyện vọng cuối đời', style: text.bodySmall),
                  Text(
                    wish['notRecorded'] == true
                        ? 'Chưa có nguyện vọng'
                        : (_wishChoices[wish['choice']] ?? '${wish['choice'] ?? 'Đã ghi'}'),
                    style: text.titleMedium,
                  ),
                  if (wish['notRecorded'] != true) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _done == null ? _confirmWish : null,
                      child: const Text('Tôi đã xem nguyện vọng'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (contact != null) ...[
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minTileHeight: 56,
            title: Text('${contact['fullName']}', style: text.titleMedium),
            subtitle: const Text('Người liên hệ chính'),
            trailing: contact['phoneNumber'] == null
                ? null
                : FilledButton.icon(
                    onPressed: () => widget.dial('${contact['phoneNumber']}'),
                    icon: const Icon(LucideIcons.phone),
                    label: const Text('Gọi'),
                  ),
          ),
        ],
        if (_done != null) Text(_done!, style: text.titleSmall),
        if (_error != null) Text(_error!, style: text.bodyMedium?.copyWith(color: scheme.error)),
      ],
    );
  }
}
