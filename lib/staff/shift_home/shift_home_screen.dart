import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/format/date_time.dart';
import '../../common/notifications/notification_api.dart';
import '../staff_navigation.dart';

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

/// Tab "Ca của tôi" (Figma "03 · App nhân viên" node 5:5; spec 2026-11-20 điều hướng theo vai trò mục 5.1): thẻ ca hiện
/// tại hoặc ca tiếp theo (`GET /me/shifts`), "Cần làm ngay" có số cảnh báo khẩn cấp chưa xác nhận và nút Báo sự cố,
/// "Công việc trong ca" mở Checklist ca (tab 2), Bàn giao ca, Lịch ca và đơn. [open] dựng màn theo tên: `incident`,
/// `handover`, `schedule`.
class ShiftHomeScreen extends StatefulWidget {
  const ShiftHomeScreen({
    super.key,
    required this.api,
    required this.showChecklist,
    required this.showHandover,
    required this.showSchedule,
    required this.onSelectTab,
    required this.open,
    this.clock = DateTime.now,
  });

  final ApiClient api;
  final bool showChecklist;
  final bool showHandover;

  /// Có quyền xem lịch ca (`SHIFT_SCHEDULE:VIEW`, 008 FR-054).
  final bool showSchedule;
  final void Function(StaffTab) onSelectTab;
  final Widget Function(String name) open;
  final DateTime Function() clock;

  @override
  State<ShiftHomeScreen> createState() => _ShiftHomeScreenState();
}

class _ShiftHomeScreenState extends State<ShiftHomeScreen> {
  Map<String, dynamic>? _shift;
  bool _loaded = false;
  bool _shiftError = false;
  int _urgent = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime get _vnNow => widget.clock().toUtc().add(const Duration(hours: 7));

  static String _day(DateTime vn) =>
      '${vn.year}-${vn.month.toString().padLeft(2, '0')}-${vn.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final now = widget.clock();
    final today = _vnNow;
    Map<String, dynamic>? shift;
    var shiftError = false;
    try {
      final rows = (await widget.api.getList(
        '/me/shifts?from=${_day(today)}&to=${_day(today.add(const Duration(days: 2)))}',
      )).cast<Map<String, dynamic>>();
      final upcoming =
          rows.where((r) => r['status'] != 'CANCELLED' && DateTime.parse(r['endsAt'] as String).isAfter(now)).toList()
            ..sort((a, b) => (a['startsAt'] as String).compareTo(b['startsAt'] as String));
      shift = upcoming.firstOrNull;
    } on Object {
      shiftError = true;
    }
    var urgent = 0;
    try {
      urgent = (await NotificationApi(widget.api).page()).urgentCount;
    } on Object {
      // Không tải được thì không hiện dòng khẩn cấp; tab Thông báo vẫn có huy hiệu.
    }
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _shiftError = shiftError;
      _urgent = urgent;
      _loaded = true;
    });
  }

  void _push(String name, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: widget.open(name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vn = _vnNow;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${_weekdays[vn.weekday - 1]}, ${formatDate(_day(vn))}',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (!_loaded) const Center(child: CircularProgressIndicator()) else _shiftCard(context),
          const SizedBox(height: 24),
          Text('Cần làm ngay', style: text.titleMedium),
          const SizedBox(height: 8),
          _Group(
            rows: [
              if (_urgent > 0)
                _Row(
                  icon: LucideIcons.triangleAlert,
                  title: '$_urgent cảnh báo khẩn cấp',
                  subtitle: 'Mở hộp thông báo để tiếp nhận',
                  danger: true,
                  onTap: () => widget.onSelectTab(StaffTab.inbox),
                ),
              _Row(
                icon: LucideIcons.siren,
                title: 'Báo sự cố',
                subtitle: 'Ghi nhận sự cố khi chăm sóc',
                onTap: () => _push('incident', 'Báo sự cố'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Công việc trong ca', style: text.titleMedium),
          const SizedBox(height: 8),
          _Group(
            rows: [
              if (widget.showChecklist)
                _Row(
                  icon: LucideIcons.listChecks,
                  title: 'Checklist ca',
                  subtitle: 'Việc chăm sóc và liều thuốc trong ca',
                  onTap: () => widget.onSelectTab(StaffTab.primary),
                ),
              if (widget.showHandover)
                _Row(
                  icon: LucideIcons.arrowLeftRight,
                  title: 'Bàn giao ca',
                  subtitle: 'Nhận đầu ca, lập cuối ca',
                  onTap: () => _push('handover', 'Bàn giao ca'),
                ),
              if (widget.showSchedule)
                _Row(
                  icon: LucideIcons.calendarDays,
                  title: 'Lịch ca và đơn',
                  subtitle: 'Lịch ca, đổi ca, xin nghỉ',
                  onTap: () => _push('schedule', 'Lịch ca và đơn'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shiftCard(BuildContext context) {
    final theme = Theme.of(context);
    final shift = _shift;
    if (_shiftError) {
      return _Group(
        rows: [
          _Row(icon: LucideIcons.clock, title: 'Chưa tải được ca', subtitle: 'Kéo xuống để tải lại'),
        ],
      );
    }
    if (shift == null) {
      return _Group(
        rows: [
          _Row(icon: LucideIcons.clock, title: 'Chưa có ca trong hôm nay và ngày mai.'),
        ],
      );
    }
    final start = DateTime.parse(shift['startsAt'] as String);
    final end = DateTime.parse(shift['endsAt'] as String);
    final now = widget.clock();
    final current = !start.isAfter(now);
    final left = end.difference(now);
    final progress = current ? now.difference(start).inSeconds / end.difference(start).inSeconds : 0.0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.clock),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(current ? 'Ca đang làm' : 'Ca tiếp theo', style: theme.textTheme.titleMedium),
                      Text(
                        current
                            ? '${formatTime(start)}–${formatTime(end)} · Còn ${left.inHours} giờ '
                                  '${left.inMinutes % 60} phút'
                            : '${formatDateTime(start)}–${formatTime(end)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (current) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progress.clamp(0.0, 1.0)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Khối dòng trắng bo góc (Figma "Danh sách").
class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(children: ListTile.divideTiles(context: context, tiles: rows).toList()),
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.onTap, this.danger = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      minTileHeight: 64,
      leading: Icon(icon, color: color),
      title: Text(title, style: color == null ? null : TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: onTap == null ? null : const Icon(LucideIcons.chevronRight),
      onTap: onTap,
    );
  }
}
