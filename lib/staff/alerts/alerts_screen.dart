import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../incidents/bf06_shared.dart';
import 'alert_labels.dart';
import 'emergency_assist_screen.dart' show dialPhone;

/// Cảnh báo trên app nhân viên (007 T031; US3; FR-027, FR-029, FR-033, FR-036; BR-M05-30, 31). Danh sách tự làm mới, mỗi
/// dòng có tên người cao tuổi; chi tiết mở trang riêng (nút Quay lại về danh sách). Cảnh báo từ nút SOS, nút hỗ trợ có
/// nơi đã chọn, vị trí GPS kèm "Chỉ đường", nút "Đã tới nơi" và "Gọi 115". Chuyển sự cố, kích hoạt khẩn cấp hỏi loại sự
/// cố bằng ô lớn. Lệnh khác (giao người, đổi mức) làm trên web.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({
    super.key,
    required this.api,
    this.dial = dialPhone,
    this.refreshEvery = const Duration(seconds: 10),
  });

  final ApiClient api;
  final Future<bool> Function(String phone) dial;
  final Duration refreshEvery;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  late final ResidentDirectory _residents = ResidentDirectory(widget.api);
  List<Map<String, dynamic>>? _alerts;
  final Map<int, ResidentInfo> _info = {};
  String? _error, _notice;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(widget.refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = (await widget.api.getList(
        '/alerts?status=NEW&status=ESCALATED&status=RECEIVED&status=IN_PROGRESS',
      )).cast<Map<String, dynamic>>();
      // Khẩn cấp lên đầu, rồi mới nhất trước
      rows.sort((a, b) {
        final la = levelOrder.indexOf(a['level'] as String? ?? '');
        final lb = levelOrder.indexOf(b['level'] as String? ?? '');
        if (la != lb) return la.compareTo(lb);
        return '${b['latestAt']}'.compareTo('${a['latestAt']}');
      });
      if (!mounted) return;
      setState(() {
        _alerts = rows;
        _error = null;
      });
      for (final a in rows) {
        final id = a['residentId'] as int?;
        if (id != null && !_info.containsKey(id)) {
          final info = await _residents.lookup(id);
          if (info != null && mounted) setState(() => _info[id] = info);
        }
      }
    } on Exception catch (e) {
      if (mounted && _alerts == null) setState(() => _error = backendMessage(e));
    }
  }

  Future<void> _open(Map<String, dynamic> alert) async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AlertDetailPage(
          api: widget.api,
          alertId: alert['id'] as int,
          residents: _residents,
          dial: widget.dial,
          refreshEvery: widget.refreshEvery,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _notice = message);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_notice != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_notice!, style: text.bodyLarge),
              ),
            ),
          if (_error != null) ...[
            Text(_error!, style: text.bodyMedium),
            OutlinedButton(onPressed: _load, child: const Text('Tải lại')),
          ] else if (_alerts == null)
            const Center(child: CircularProgressIndicator())
          else if (_alerts!.isEmpty)
            Text('Không có cảnh báo đang mở.', style: text.bodyLarge)
          else
            for (final a in _alerts!)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: a['level'] == 'CRITICAL' && a['arrivedAt'] == null
                      ? BorderSide(color: scheme.error, width: 2)
                      : BorderSide(color: scheme.outlineVariant),
                ),
                child: ListTile(
                  minTileHeight: 72,
                  leading: Icon(
                    a['level'] == 'CRITICAL' ? LucideIcons.siren : LucideIcons.bell,
                    color: a['level'] == 'CRITICAL' ? scheme.error : scheme.primary,
                  ),
                  title: Text(_title(a, _info[a['residentId']]), style: text.titleMedium),
                  subtitle: Text(
                    [
                      alertTypeName(a['type'] as String?),
                      if (_info[a['residentId']]?.place.isNotEmpty ?? false)
                        _info[a['residentId']]!.place
                      else if (a['floorName'] != null)
                        '${a['floorName']}',
                      alertStatusNames[a['status']] ?? '${a['status']}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => _open(a),
                ),
              ),
        ],
      ),
    );
  }
}

String _title(Map<String, dynamic> a, ResidentInfo? info) {
  if (info != null) return info.name;
  if (a['origin'] == 'ASSIST_BUTTON') return 'Nhân viên cần hỗ trợ';
  return alertTypeName(a['type'] as String?);
}

/// Chi tiết một cảnh báo, trang riêng có nút Quay lại; tự hỏi lại mỗi [refreshEvery]. Trả câu báo khi đã làm một lệnh.
class AlertDetailPage extends StatefulWidget {
  const AlertDetailPage({
    super.key,
    required this.api,
    required this.alertId,
    required this.residents,
    this.dial = dialPhone,
    this.refreshEvery = const Duration(seconds: 10),
  });

  final ApiClient api;
  final int alertId;
  final ResidentDirectory residents;
  final Future<bool> Function(String phone) dial;
  final Duration refreshEvery;

  @override
  State<AlertDetailPage> createState() => _AlertDetailPageState();
}

class _AlertDetailPageState extends State<AlertDetailPage> {
  Map<String, dynamic>? _a;
  ResidentInfo? _info;
  List<Map<String, dynamic>>? _types;
  final _keys = <String, String>{};
  Map<String, dynamic>? _call;
  String? _callResult, _error, _done;
  bool _busy = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(widget.refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await widget.api.get('/alerts/${widget.alertId}');
      if (!mounted || a == null) return;
      setState(() => _a = a);
      if (_info == null && a['residentId'] != null) {
        final info = await widget.residents.lookup(a['residentId'] as int);
        if (mounted) setState(() => _info = info);
      }
    } on Exception catch (e) {
      if (mounted && _a == null) setState(() => _error = backendMessage(e));
    }
  }

  List<String> get _commands => ((_a?['allowedCommands'] as List?) ?? const []).cast<String>();

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

  Future<void> _command(String command, String done, [Map<String, dynamic> body = const {}]) async {
    if (await _post('/alerts/${widget.alertId}/$command', body, command)) {
      setState(() => _done = done);
      await _load();
    }
  }

  Future<void> _toIncident(String command) async {
    _types ??= await loadIncidentTypes(widget.api);
    if (!mounted) return;
    final type = await pickIncidentType(context, _types!);
    if (type == null || !mounted) return;
    final body = <String, dynamic>{'incidentTypeId': type['id']};
    if (_a?['residentId'] == null) {
      final picked = await _pickResident();
      if (picked == null) return;
      body['residentId'] = picked.id;
    }
    if (await _post('/alerts/${widget.alertId}/$command', body, command) && mounted) {
      Navigator.of(context).pop(
        command == 'activate-emergency'
            ? 'Đã kích hoạt khẩn cấp và tạo sự cố.'
            : 'Đã chuyển thành sự cố ${typeShortName(type).toLowerCase()}.',
      );
    }
  }

  Future<ResidentInfo?> _pickResident() => showModalBottomSheet<ResidentInfo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ResidentSearch(residents: widget.residents),
  );

  Future<void> _close() async {
    final resolution = await askText(context, title: 'Đóng cảnh báo', label: 'Kết quả xử lý', action: 'Đóng cảnh báo');
    if (resolution == null || !mounted) return;
    if (await _post('/alerts/${widget.alertId}/close', {'resolution': resolution}, 'close') && mounted) {
      Navigator.of(context).pop('Đã đóng cảnh báo.');
    }
  }

  Future<void> _followUp() async {
    final content = await askText(context, title: 'Ghi theo dõi', label: 'Kết quả theo dõi');
    if (content == null || !mounted) return;
    if (await _post('/alerts/${widget.alertId}/follow-ups', {'content': content}, 'follow-up')) {
      setState(() => _done = 'Đã ghi theo dõi.');
      await _load();
    }
  }

  Future<void> _call115() async {
    if (_call == null) {
      try {
        final call = await widget.api.post(
          '/alerts/${widget.alertId}/call-115',
          {},
          headers: {'Idempotency-Key': _keys.putIfAbsent('call-115', newIdempotencyKey)},
        );
        if (mounted) setState(() => _call = call);
      } catch (_) {
        // Không ghi được lượt gọi vẫn mở trình quay số: gọi cấp cứu không chờ máy chủ.
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
    final a = _a;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.of(context).pop(_done),
        ),
        title: Text(
          a == null
              ? 'Cảnh báo'
              : (a['origin'] == 'SOS'
                    ? 'Cụ gọi khẩn cấp'
                    : (a['origin'] == 'ASSIST_BUTTON' ? 'Cần hỗ trợ' : 'Cảnh báo')),
        ),
      ),
      body: a == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : _body(context, a),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> a) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pressed = a['origin'] == 'SOS' || a['origin'] == 'ASSIST_BUTTON';
    final critical = a['level'] == 'CRITICAL';
    final sources = ((a['sources'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final helpers = ((a['helpers'] as List?) ?? const []).cast<Object>();
    final location = a['latestLocation'] as Map<String, dynamic>?;
    final c = _commands;
    final onColor = critical ? scheme.onError : scheme.onSurface;
    final headline = [
      if (_info?.place.isNotEmpty ?? false) _info!.place else if (a['floorName'] != null) '${a['floorName']}',
    ].join();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Ai, ở đâu: điều nhân viên cần trước tiên
        DecoratedBox(
          decoration: BoxDecoration(
            color: critical ? scheme.error : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: critical ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _info?.name ??
                      (a['origin'] == 'ASSIST_BUTTON' ? 'Nhân viên cần hỗ trợ' : alertTypeName(a['type'] as String?)),
                  style: text.headlineSmall?.copyWith(color: onColor, fontWeight: FontWeight.w700),
                ),
                if (headline.isNotEmpty) Text(headline, style: text.bodyLarge?.copyWith(color: onColor)),
                if (a['pressedBy'] != null)
                  Text('Người bấm: ${a['pressedBy']}', style: text.bodyLarge?.copyWith(color: onColor)),
                const SizedBox(height: 8),
                if (pressed)
                  Text(
                    a['chosenPlace'] != null
                        ? 'Nơi đã chọn: ${placeNames[a['chosenPlace']] ?? a['chosenPlace']}'
                        : 'Chưa chọn nơi',
                    style: text.titleMedium?.copyWith(color: onColor),
                  ),
                if (a['eventType'] != null)
                  Text(
                    assistEvents.where((e) => e.$1 == a['eventType']).map((e) => e.$2).firstOrNull ??
                        '${a['eventType']}',
                    style: text.titleMedium?.copyWith(color: onColor),
                  ),
                Text(
                  sources.length > 1
                      ? 'Báo ${sources.length} lần, gần nhất ${hhmm(a['latestAt'] as String?)}'
                      : 'Lúc ${hhmm((a['firstAt'] ?? a['latestAt']) as String?)}',
                  style: text.bodyMedium?.copyWith(color: onColor),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (location != null && location['latitude'] != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Row(
                children: [
                  Icon(LucideIcons.mapPin, color: scheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vị trí GPS · sai số ${(location['accuracyMeters'] as num? ?? 0).round()} m',
                          style: text.titleSmall,
                        ),
                        Text(
                          '${hhmm(location['measuredAt'] as String?)}'
                          '${location['isPrimary'] == true ? '' : ' · trong viện chỉ để tham khảo'}',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => openDirections(
                      (location['latitude'] as num).toDouble(),
                      (location['longitude'] as num).toDouble(),
                    ),
                    icon: const Icon(LucideIcons.navigation),
                    label: const Text('Chỉ đường'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          [
            alertStatusNames[a['status']] ?? '${a['status']}',
            if (a['arrivedAt'] != null) 'đã tới lúc ${hhmm(a['arrivedAt'] as String?)}',
            if (helpers.isNotEmpty)
              'đang đến: ${helpers.join(', ')}'
            else if (a['assignee'] != null)
              'phụ trách: ${a['assignee']}',
          ].join(' · '),
          style: text.bodyLarge,
        ),
        const SizedBox(height: 16),
        if (_done != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_done!, style: text.titleSmall),
            ),
          ),
        // Mỗi lúc chỉ một nút chính theo thứ tự việc thật: nhận việc → tới nơi (SOS, nút hỗ trợ) → bắt đầu xử lý
        if (c.contains('receive'))
          _primary('Tiếp nhận', () => _command('receive', 'Đã tiếp nhận.'))
        else if (c.contains('mark-arrived') && a['arrivedAt'] == null) ...[
          _primary('Đã tới nơi', () => _command('mark-arrived', 'Đã ghi tới nơi.')),
          if (c.contains('start-handling'))
            _secondary('Bắt đầu xử lý', () => _command('start-handling', 'Đã bắt đầu xử lý.')),
        ] else if (c.contains('start-handling'))
          _primary('Bắt đầu xử lý', () => _command('start-handling', 'Đã bắt đầu xử lý.')),
        if (c.contains('call-115')) ...[
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
        if (c.contains('activate-emergency')) _secondary('Kích hoạt khẩn cấp', () => _toIncident('activate-emergency')),
        if (c.contains('convert-to-incident'))
          _secondary('Chuyển thành sự cố', () => _toIncident('convert-to-incident')),
        if (c.contains('follow-up')) _secondary('Ghi theo dõi', _followUp),
        if (c.contains('close')) _secondary('Đóng cảnh báo', _close),
        if (c.isEmpty) Text('Bạn chỉ xem được cảnh báo này.', style: text.bodyMedium),
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

/// Tìm người cao tuổi khi cảnh báo chưa gắn ai (nút hỗ trợ của nhân viên).
class _ResidentSearch extends StatefulWidget {
  const _ResidentSearch({required this.residents});
  final ResidentDirectory residents;

  @override
  State<_ResidentSearch> createState() => _ResidentSearchState();
}

class _ResidentSearchState extends State<_ResidentSearch> {
  List<ResidentInfo> _found = const [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final found = await widget.residents.search(q);
      if (mounted) setState(() => _found = found);
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sự việc xảy ra với ai?', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tìm tên hoặc phòng', prefixIcon: Icon(LucideIcons.search)),
          onChanged: _search,
        ),
        for (final r in _found)
          ListTile(
            minTileHeight: 56,
            title: Text(r.name),
            subtitle: Text(r.place),
            onTap: () => Navigator.of(context).pop(r),
          ),
      ],
    ),
  );
}
