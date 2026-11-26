import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../resident/sos/sos_button.dart' show GeolocatorLocationSource, SosLocationSource;
import '../incidents/bf06_shared.dart';

/// Mở trình quay số của máy; `false` khi máy không mở được.
Future<bool> dialPhone(String phone) async {
  try {
    return await launchUrl(Uri(scheme: 'tel', path: phone));
  } on PlatformException {
    return false;
  }
}

/// Nút hỗ trợ khẩn cấp trên app nhân viên (007 T102; US13; FR-047i, FR-047j, FR-047k; BR-M05-29, 31). Chạm nút thì đếm
/// ngược 3 giây, có nút Hủy; chạm lần nữa khi đang đếm thì gửi ngay. Gửi xong hiện trạng thái (Đã gửi, "[họ tên] đang
/// tới", "[họ tên] đã tới", hỏi lại mỗi [pollInterval]), chọn loại sự việc, nơi (mỗi trường một lần), nút "Gọi 115" ghi
/// lượt gọi rồi mở trình quay số. Chỉ trực tuyến (lệnh không vào hàng đợi ngoại tuyến); mất mạng hoặc bị từ chối thì hiện
/// số của viện và 115. Gửi vị trí GPS làm ở T096.
class EmergencyAssistScreen extends StatefulWidget {
  const EmergencyAssistScreen({
    super.key,
    required this.api,
    this.dial = dialPhone,
    this.pollInterval = const Duration(seconds: 5),
    this.location = const GeolocatorLocationSource(),
    this.autoStart = true,
  });

  /// Mở màn là bắt đầu đếm ngược (người dùng đã bấm nút Khẩn cấp ở đầu màn).
  final bool autoStart;

  final ApiClient api;
  final Future<bool> Function(String phone) dial;
  final Duration pollInterval;

  /// Nguồn vị trí GPS (FR-047h): chỉ xin quyền khi đang dùng app, gửi theo chu kỳ của backend cho tới khi 409.
  final SosLocationSource location;

  @override
  State<EmergencyAssistScreen> createState() => _EmergencyAssistScreenState();
}

/// Đếm ngược trước khi gửi, cùng số giây với nút SOS của người cao tuổi.
const assistCountdownSeconds = 5;

const _places = [
  ('ROOM', 'Phòng'),
  ('RESTROOM', 'Nhà vệ sinh'),
  ('CORRIDOR', 'Hành lang'),
  ('COMMON_ROOM', 'Sinh hoạt chung'),
  ('YARD', 'Sân'),
  ('OTHER', 'Nơi khác'),
];

String _newKey() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

class _EmergencyAssistScreenState extends State<EmergencyAssistScreen> {
  Timer? _countdown;
  Timer? _poll;
  Timer? _locationTimer;
  bool? _locationGranted;
  bool _stopLocation = false;
  int? _secondsLeft;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _contacts;
  Map<String, dynamic>? _status;
  String? _eventType;
  String? _place;
  Map<String, dynamic>? _call;
  String? _callResult;
  final String _pressKey = _newKey();
  final String _callKey = _newKey();

  @override
  void initState() {
    super.initState();
    // Bấm nút Khẩn cấp ở đầu màn là đã kích hoạt: đếm ngược ngay, chỉ còn việc Hủy nếu bấm nhầm (như nút SOS)
    if (widget.autoStart) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _tapButton() : null);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _poll?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  void _tapButton() {
    if (_secondsLeft != null) {
      _send();
      return;
    }
    setState(() => _secondsLeft = assistCountdownSeconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = (_secondsLeft ?? 1) - 1;
      if (left <= 0) {
        _send();
      } else {
        setState(() => _secondsLeft = left);
      }
    });
  }

  void _cancel() {
    _countdown?.cancel();
    setState(() => _secondsLeft = null);
  }

  Future<void> _send() async {
    _countdown?.cancel();
    setState(() {
      _secondsLeft = null;
      _busy = true;
      _error = null;
      _contacts = null;
    });
    try {
      final status = await widget.api.post('/emergency-assist', {}, headers: {'Idempotency-Key': _pressKey});
      if (!mounted) return;
      setState(() => _status = status);
      _poll = Timer.periodic(widget.pollInterval, (_) => _refresh());
      unawaited(_startLocation());
    } on ApiProblem catch (problem) {
      if (!mounted) return;
      setState(() {
        _error = problem.detail ?? backendMessage(problem);
        _contacts = problem.properties['contacts'] as Map<String, dynamic>?;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = backendMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startLocation() async {
    if (_status?['sendLocation'] != true) return;
    _locationGranted ??= await widget.location.requestPermission();
    if (_locationGranted != true || !mounted) return;
    await _sendLocation();
    final seconds = _status?['locationIntervalSeconds'] as int? ?? 30;
    if (!_stopLocation && mounted) {
      _locationTimer = Timer.periodic(Duration(seconds: seconds), (_) => _sendLocation());
    }
  }

  Future<void> _sendLocation() async {
    final pressId = _status?['pressId'];
    if (_stopLocation || pressId == null) return;
    try {
      final position = await widget.location.current();
      if (position == null) return;
      await widget.api.requestJson('POST', '/emergency-assist/$pressId/location', body: position.toJson());
    } on ApiProblem {
      // 409 STOP_SENDING_LOCATION hoặc cảnh báo đã đóng, đã tới nơi: dừng gửi
      _stopLocation = true;
      _locationTimer?.cancel();
    } on Exception {
      // Mất kết nối: lần sau gửi lại
    }
  }

  Future<void> _refresh() async {
    try {
      final status = await widget.api.get('/emergency-assist/current');
      if (!mounted) return;
      setState(() => _status = status ?? _status);
      if (status == null) _poll?.cancel();
      if (status != null && status['sendLocation'] != true) _locationTimer?.cancel();
    } catch (_) {
      // Giữ trạng thái cũ; lần hỏi sau thử lại.
    }
  }

  Future<void> _details(String field, String value) async {
    final alertId = _status?['alertId'];
    if (alertId == null) return;
    setState(() => _error = null);
    try {
      await widget.api.post('/emergency-assist/$alertId/details', {field: value});
      if (!mounted) return;
      setState(() => field == 'eventType' ? _eventType = value : _place = value);
    } catch (error) {
      if (mounted) setState(() => _error = backendMessage(error));
    }
  }

  Future<void> _call115() async {
    final alertId = _status?['alertId'];
    if (alertId != null && _call == null) {
      try {
        final call = await widget.api.post('/alerts/$alertId/call-115', {}, headers: {'Idempotency-Key': _callKey});
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
    } catch (error) {
      if (mounted) setState(() => _error = backendMessage(error));
    }
  }

  String _statusText(Map<String, dynamic> status) {
    final name = status['receiverName'] as String?;
    return switch (status['status']) {
      'RECEIVED' => '${name ?? 'Người tiếp nhận'} đang tới',
      'ARRIVED' => '${name ?? 'Người tiếp nhận'} đã tới',
      _ => 'Đã gửi, đang chờ người tiếp nhận',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (status == null) ...[
          if (_secondsLeft != null) ...[
            const SizedBox(height: 24),
            Semantics(
              liveRegion: true,
              child: Text('Gửi yêu cầu hỗ trợ sau', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            ),
            Text('$_secondsLeft', textAlign: TextAlign.center, style: theme.textTheme.displayLarge),
            Text('Chạm Hủy nếu bấm nhầm', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            // Một nút duy nhất và to: bấm nhầm thì chỉ có việc hủy; hết giờ tự gửi
            SizedBox(
              height: 96,
              child: FilledButton.icon(
                onPressed: _cancel,
                icon: const Icon(LucideIcons.x, size: 32),
                label: Text('Hủy', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onPrimary)),
              ),
            ),
          ] else
            SizedBox(
              height: 96,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
                onPressed: _busy ? null : _tapButton,
                child: Text(
                  _busy ? 'Đang gửi…' : 'Gọi hỗ trợ khẩn cấp',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onError),
                ),
              ),
            ),
        ] else ...[
          Card(
            child: ListTile(
              minTileHeight: 64,
              leading: Icon(LucideIcons.circleCheck, color: theme.colorScheme.primary, size: 32),
              title: Text('Đã gửi', style: theme.textTheme.titleMedium),
              subtitle: Text(
                _statusText(status).replaceFirst('Đã gửi, đang', 'Đang'),
                semanticsLabel: _statusText(status),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Chuyện gì xảy ra?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ChoiceGrid(
            columns: 2,
            children: [
              for (final (value, label, icon) in assistEvents)
                ChoiceTile(
                  icon: icon,
                  label: label,
                  selected: _eventType == value,
                  // Mỗi trường đặt một lần: đã chọn thì khóa (FR-047i)
                  onTap: _eventType == null ? () => _details('eventType', value) : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Bạn ở đâu?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ChoiceGrid(
            children: [
              for (final (value, label) in _places)
                ChoiceTile(
                  icon: placeIcons[value]!,
                  label: label,
                  minHeight: 76,
                  selected: _place == value,
                  onTap: _place == null ? () => _details('place', value) : null,
                ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (_contacts?['facilityPhone'] != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => widget.dial(_contacts!['facilityPhone'] as String),
            child: Text('Gọi số của viện ${_contacts!['facilityPhone']}'),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 56,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error, width: 1.5),
            ),
            onPressed: _call115,
            icon: const Icon(LucideIcons.phone),
            label: const Text('Gọi cấp cứu 115'),
          ),
        ),
        if (_call != null && _callResult == null) ...[
          const SizedBox(height: 12),
          const Text('Sau cuộc gọi, chọn kết quả:'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(onPressed: () => _callResultTap('CONNECTED'), child: const Text('Đã gọi được')),
              OutlinedButton(onPressed: () => _callResultTap('NOT_CONNECTED'), child: const Text('Không gọi được')),
            ],
          ),
        ],
        if (_callResult != null) ...[
          const SizedBox(height: 12),
          Text(_callResult == 'CONNECTED' ? 'Đã ghi: đã gọi được cấp cứu 115.' : 'Đã ghi: không gọi được 115.'),
        ],
      ],
    );
  }
}
