import 'dart:async';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/format/date_time.dart';
import '../staff_dashboard_style.dart';

enum StaffShortcutSummary { overdueTasks, pendingDoses }

class StaffShortcut {
  const StaffShortcut(this.title, this.icon, this.tone, this.open, {this.subtitle, this.summary});

  final String title;
  final Widget icon;
  final StaffShortcutTone tone;
  final Future<void> Function() open;
  final String? subtitle;
  final StaffShortcutSummary? summary;
}

class ShiftHomeScreen extends StatefulWidget {
  const ShiftHomeScreen({
    super.key,
    required this.api,
    required this.work,
    required this.tools,
    required this.other,
    required this.urgentCount,
    required this.onOpenInbox,
    required this.refreshDashboard,
    this.showTaskSummary = false,
    this.loadMedicationCount,
    this.clock = DateTime.now,
  });

  final ApiClient api;
  final List<StaffShortcut> work;
  final List<StaffShortcut> tools;
  final List<StaffShortcut> other;
  final int urgentCount;
  final VoidCallback onOpenInbox;
  final Future<void> Function() refreshDashboard;
  final bool showTaskSummary;
  final Future<int> Function()? loadMedicationCount;
  final DateTime Function() clock;

  @override
  State<ShiftHomeScreen> createState() => _ShiftHomeScreenState();
}

class _ShiftHomeScreenState extends State<ShiftHomeScreen> {
  Map<String, dynamic>? _shift;
  String? _shiftName;
  int? _overdue;
  int? _medicationCount;
  bool _loaded = false;
  bool _shiftError = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(ShiftHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showTaskSummary != oldWidget.showTaskSummary ||
        (widget.loadMedicationCount == null) != (oldWidget.loadMedicationCount == null)) {
      unawaited(_load());
    }
  }

  static String _day(DateTime vn) => vn.toIso8601String().substring(0, 10);

  Future<void> _load() async {
    final request = ++_request;
    final now = widget.clock();
    final today = now.toUtc().add(const Duration(hours: 7));
    final from = _day(today.subtract(const Duration(days: 1)));
    final to = _day(today.add(const Duration(days: 2)));
    final medication = _optional(widget.loadMedicationCount);
    Map<String, dynamic>? shift;
    var shiftError = false;
    try {
      final rows = await widget.api.getList('/me/shifts?from=$from&to=$to');
      final upcoming =
          rows.whereType<Map<String, dynamic>>().where((row) {
            final end = DateTime.tryParse('${row['endsAt']}');
            return !const {'CANCELLED', 'CLOSED', 'DRAFT'}.contains(row['status']) &&
                DateTime.tryParse('${row['startsAt']}') != null &&
                end != null &&
                end.isAfter(now);
          }).toList()..sort(
            (a, b) => DateTime.parse(a['startsAt'] as String).compareTo(DateTime.parse(b['startsAt'] as String)),
          );
      shift = upcoming.firstOrNull;
    } on Exception {
      shiftError = true;
    }
    final shiftName = _optional(() => _loadShiftName(shift?['shiftTemplateId']));
    final overdue = _optional(() => _loadOverdue(shift?['id']));
    final name = await shiftName;
    final late = await overdue;
    final doses = await medication;
    if (!mounted || request != _request) return;
    setState(() {
      _shift = shift;
      _shiftName = name;
      _overdue = late;
      _medicationCount = doses;
      _loaded = true;
      _shiftError = shiftError;
    });
  }

  Future<T?> _optional<T>(Future<T?> Function()? fetch) async {
    try {
      return await fetch?.call();
    } on Exception {
      return null;
    }
  }

  Future<String?> _loadShiftName(Object? templateId) async {
    if (templateId == null) return null;
    final templates = await widget.api.getList('/shift-templates');
    return templates.whereType<Map<String, dynamic>>().where((row) => row['id'] == templateId).firstOrNull?['name']
        as String?;
  }

  Future<int?> _loadOverdue(Object? shiftId) async {
    if (!widget.showTaskSummary || shiftId == null) return null;
    final checklist = await widget.api.get('/checklist?shiftId=$shiftId');
    final tasks = (checklist?['tasks'] as List?)?.whereType<Map<String, dynamic>>();
    return tasks?.where((task) => task['status'] == 'OVERDUE').length;
  }

  Future<void> _open(StaffShortcut shortcut) async {
    await shortcut.open();
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: RefreshIndicator(
        onRefresh: () => Future.wait([_load(), widget.refreshDashboard()]),
        child: ListView(
          key: const PageStorageKey('staff-home'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _shiftCard(context),
            if (widget.urgentCount > 0) ...[
              const SizedBox(height: 10),
              _UrgentAlert(count: widget.urgentCount, onTap: widget.onOpenInbox),
            ],
            const SizedBox(height: 16),
            if (widget.work.isNotEmpty) _section(context, 'Công việc trong ca', widget.work),
            if (widget.tools.isNotEmpty) ...[const SizedBox(height: 24), _section(context, 'Tiện ích', widget.tools)],
            if (widget.other.isNotEmpty) ...[
              const SizedBox(height: 24),
              _section(context, 'Nghiệp vụ khác', widget.other),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _section(BuildContext context, String title, List<StaffShortcut> shortcuts) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      const SizedBox(height: 8),
      for (var i = 0; i < shortcuts.length; i += 2) ...[
        if (i > 0) const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _tile(shortcuts[i])),
              const SizedBox(width: 10),
              Expanded(child: i + 1 < shortcuts.length ? _tile(shortcuts[i + 1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _tile(StaffShortcut shortcut) {
    final subtitle = switch (shortcut.summary) {
      StaffShortcutSummary.overdueTasks when widget.showTaskSummary && (_overdue ?? 0) > 0 => '$_overdue việc quá hạn',
      StaffShortcutSummary.pendingDoses when widget.loadMedicationCount != null && (_medicationCount ?? 0) > 0 =>
        '$_medicationCount liều chờ ghi nhận',
      _ => shortcut.subtitle,
    };
    return _ShortcutCard(shortcut: shortcut, subtitle: subtitle, onTap: () => _open(shortcut));
  }

  Widget _shiftCard(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final shift = _shift;
    if (!_loaded) {
      return staffDashboardCard(
        context,
        const SizedBox(height: 64, child: Center(child: CircularProgressIndicator())),
        radius: 14,
      );
    }
    if (shift == null) {
      return staffDashboardCard(
        context,
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(
            _shiftError ? 'Chưa tải được ca. Kéo xuống để tải lại.' : 'Chưa có ca trong hôm nay và ngày mai.',
            style: text.bodySmall,
          ),
        ),
        radius: 14,
      );
    }
    final start = DateTime.parse(shift['startsAt'] as String);
    final end = DateTime.parse(shift['endsAt'] as String);
    final current = !start.isAfter(widget.clock());
    final startLabel = current ? formatTime(start) : formatDateTime(start);
    return staffDashboardCard(
      context,
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_shiftName ?? (current ? 'Ca đang làm' : 'Ca tiếp theo'), style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      '$startLabel–${formatTime(end)}',
                      style: text.labelMedium?.copyWith(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: DecoratedBox(
                  decoration: ShapeDecoration(color: scheme.secondaryContainer, shape: const StadiumBorder()),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 100, minHeight: 28),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Text(
                        current ? 'Đang diễn ra' : 'Sắp diễn ra',
                        textAlign: TextAlign.center,
                        style: text.labelMedium?.copyWith(
                          fontSize: 11,
                          height: 16 / 11,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      radius: 14,
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.shortcut, required this.subtitle, required this.onTap});

  final StaffShortcut shortcut;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return staffDashboardCard(
      context,
      InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 117),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: shortcut.tone.background(scheme),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: IconTheme(
                      data: IconThemeData(size: 22, color: scheme.secondary),
                      child: shortcut.icon,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  shortcut.title,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                if (subtitle case final label?) ...[
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UrgentAlert extends StatelessWidget {
  const _UrgentAlert({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  StaffDashboardIcon('warning', color: scheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$count cảnh báo khẩn cấp',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  StaffDashboardIcon('chevron_red', color: scheme.onErrorContainer),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
