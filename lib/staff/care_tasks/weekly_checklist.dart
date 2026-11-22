import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/format/date_time.dart';
import '../../common/theme/app_theme.dart';
import 'care_checklist_repository.dart';
import 'care_checklist_screen.dart' show Initials, careGroupKey, openTaskStatuses;

const _weekdayShort = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
const _weekdayLong = ['Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy', 'Chủ nhật'];
const _shiftStatus = {
  'IN_PROGRESS': 'Đang diễn ra',
  'PUBLISHED': 'Đã công bố',
  'AWAITING_HANDOVER': 'Chờ bàn giao',
  'CLOSED': 'Đã đóng',
};

/// Giờ Việt Nam của một mốc UTC (ca, công việc lưu UTC).
DateTime _vn(DateTime utc) => utc.toUtc().add(const Duration(hours: 7));
DateTime _day(DateTime vn) => DateTime.utc(vn.year, vn.month, vn.day);
String _dm(DateTime day) => '${day.day}/${day.month}';
String _dmPadded(DateTime day) => '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';

/// Tên ca theo giờ bắt đầu (Figma "Ca ngày", "Ca đêm"): API ca không có tên; chỉ là nhãn hiển thị theo giờ, không suy
/// nghiệp vụ.
String shiftName(Map<String, dynamic> shift) {
  final hour = _vn(DateTime.parse(shift['startsAt'] as String)).hour;
  return hour >= 5 && hour < 17 ? 'Ca ngày' : 'Ca đêm';
}

/// Dòng ca dưới tiêu đề "Việc chăm sóc" (Figma "Ca ngày · 22/11 · 07:00–18:00"): tên, ngày bắt đầu, giờ.
String shiftLabel(Map<String, dynamic> shift) {
  final start = DateTime.parse(shift['startsAt'] as String);
  final end = DateTime.parse(shift['endsAt'] as String);
  return '${shiftName(shift)} · ${_dmPadded(_vn(start))} · ${formatTime(start)}–${formatTime(end)}';
}

/// Tab Checklist theo tuần (Figma "Prototype · Mobile" 98:1671 "Checklist ca · Lịch tuần", 105:1024 "Checklist ca · Theo
/// người cao tuổi"): đổi tuần, chọn ngày; mỗi ca bắt đầu trong ngày có đầu nhóm ca rồi danh sách người cao tuổi có việc
/// trong ca (số việc còn lại, số quá hạn). Bấm một người mở "Việc chăm sóc" của người đó ([openResident]).
class WeeklyChecklist extends StatefulWidget {
  const WeeklyChecklist({
    super.key,
    required this.shifts,
    required this.repository,
    required this.accountId,
    required this.openResident,
    this.clock = DateTime.now,
  });

  /// Ca đã công bố bắt đầu trong khoảng ngày Việt Nam `[from, to)`.
  final Future<List<Map<String, dynamic>>> Function(DateTime from, DateTime to) shifts;
  final CareChecklistRepository repository;
  final int accountId;
  final Future<void> Function(Map<String, dynamic> shift, String residentKey) openResident;
  final DateTime Function() clock;

  @override
  State<WeeklyChecklist> createState() => _WeeklyChecklistState();
}

class _WeeklyChecklistState extends State<WeeklyChecklist> {
  late DateTime today;
  late DateTime weekStart;
  late DateTime selectedDay;
  List<Map<String, dynamic>>? weekShifts;
  String? shiftError;

  /// Checklist của từng ca trong ngày đang xem: bản tải, hoặc chuỗi lỗi; chưa có khóa là đang tải.
  final Map<int, Object> checklists = {};
  int generation = 0;

  @override
  void initState() {
    super.initState();
    today = _day(_vn(widget.clock()));
    weekStart = today.subtract(Duration(days: today.weekday - 1));
    selectedDay = today;
    loadWeek(keepDay: true);
  }

  List<Map<String, dynamic>> shiftsOn(DateTime day) =>
      (weekShifts ?? []).where((s) => _day(_vn(DateTime.parse(s['startsAt'] as String))) == day).toList()
        ..sort((a, b) => (a['startsAt'] as String).compareTo(b['startsAt'] as String));

  Future<void> loadWeek({bool keepDay = false}) async {
    final token = ++generation;
    setState(() {
      weekShifts = null;
      shiftError = null;
      checklists.clear();
    });
    try {
      final rows = await widget.shifts(weekStart, weekStart.add(const Duration(days: 7)));
      if (!mounted || token != generation) return;
      setState(() => weekShifts = rows);
      if (keepDay) {
        await selectDay(selectedDay);
      } else {
        // Sang tuần khác: chọn ngày đầu tiên có ca, không có thì giữ thứ đang chọn.
        final days = [for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i))];
        await selectDay(days.firstWhere((d) => shiftsOn(d).isNotEmpty, orElse: () => days[selectedDay.weekday - 1]));
      }
    } on ApiUnreachable {
      if (mounted && token == generation) setState(() => shiftError = 'Mất kết nối, chưa tải được lịch ca.');
    } catch (e) {
      if (mounted && token == generation) {
        setState(
          () => shiftError = (e is ApiProblem ? e.detail : null) ?? 'Chưa tải được lịch ca. Kéo xuống để thử lại.',
        );
      }
    }
  }

  void changeWeek(int weeks) {
    setState(() {
      weekStart = weekStart.add(Duration(days: 7 * weeks));
      selectedDay = weekStart.add(Duration(days: selectedDay.weekday - 1));
    });
    loadWeek();
  }

  /// Tải checklist của mọi ca bắt đầu trong ngày (thường một ca ngày, một ca đêm).
  Future<void> selectDay(DateTime day) async {
    final token = ++generation;
    setState(() {
      selectedDay = day;
      checklists.clear();
    });
    await Future.wait([
      for (final shift in shiftsOn(day))
        () async {
          final id = shift['id'] as int;
          Object result;
          try {
            result = await widget.repository.load(widget.accountId, id);
          } on ApiUnreachable {
            result = 'Mất kết nối và chưa có bản tải của ca này.';
          } catch (e) {
            result = (e is ApiProblem ? e.detail : null) ?? 'Chưa tải được công việc của ca.';
          }
          if (mounted && token == generation) setState(() => checklists[id] = result);
        }(),
    ]);
  }

  Future<void> open(Map<String, dynamic> shift, String key) async {
    await widget.openResident(shift, key);
    if (mounted) await selectDay(selectedDay);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => loadWeek(keepDay: true),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _WeekStrip(
            weekStart: weekStart,
            selected: selectedDay,
            hasShift: (day) => shiftsOn(day).isNotEmpty,
            onWeek: changeWeek,
            onDay: selectDay,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Heading(
                  text: '${_weekdayLong[selectedDay.weekday - 1]}, ${_dm(selectedDay)}',
                  trailing: selectedDay == today ? const _TodayChip() : null,
                ),
                const SizedBox(height: 12),
                if (shiftError != null)
                  Text(shiftError!, style: theme.textTheme.bodyMedium)
                else if (weekShifts == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (shiftsOn(selectedDay).isEmpty)
                  const _EmptyBox(
                    icon: LucideIcons.calendar,
                    title: 'Chưa có ca đã công bố',
                    body: 'Chọn ngày khác để xem lịch và công việc.',
                  )
                else
                  for (final shift in shiftsOn(selectedDay)) ...[
                    _ShiftHeader(shift: shift),
                    const SizedBox(height: 8),
                    ..._residents(context, shift),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dòng người cao tuổi của một ca, theo giờ việc sớm nhất; ca chưa có việc thì một dòng báo.
  List<Widget> _residents(BuildContext context, Map<String, dynamic> shift) {
    final theme = Theme.of(context);
    final result = checklists[shift['id']];
    if (result == null) {
      return const [
        Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (result is String) return [_NoteBox(text: result)];
    final load = result as CareChecklistLoad;
    final tasks =
        (load.snapshot.content['tasks'] as List? ?? []).map((t) => Map<String, dynamic>.from(t as Map)).toList()
          ..sort((a, b) => (a['plannedAt'] as String? ?? '').compareTo(b['plannedAt'] as String? ?? ''));
    if (tasks.isEmpty) return const [_NoteBox(text: 'Chưa có danh sách người cao tuổi cho ca này.')];
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in tasks) {
      groups.putIfAbsent(careGroupKey(t), () => []).add(t);
    }
    return [
      if (load.offline)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Đang xem bản đã tải, chưa cập nhật.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      for (final MapEntry(:key, :value) in groups.entries) ...[
        _ResidentRow(tasks: value, onTap: () => open(shift, key)),
        const SizedBox(height: 8),
      ],
    ];
  }
}

/// Khối trắng "Lịch tuần": đổi tuần, tháng và khoảng ngày, bảy ngày (đã chọn, có ca, không có ca).
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.weekStart,
    required this.selected,
    required this.hasShift,
    required this.onWeek,
    required this.onDay,
  });

  final DateTime weekStart;
  final DateTime selected;
  final bool Function(DateTime) hasShift;
  final void Function(int) onWeek;
  final void Function(DateTime) onDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final end = weekStart.add(const Duration(days: 6));
    final range = weekStart.month == end.month
        ? '${weekStart.day}–${end.day}/${end.month}'
        : '${_dm(weekStart)}–${_dm(end)}';
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.only(top: 5, bottom: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Tuần trước',
                    onPressed: () => onWeek(-1),
                    icon: const Icon(LucideIcons.chevronLeft, size: 20),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          'Tháng ${selected.month}, ${selected.year}',
                          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(range, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tuần sau',
                    onPressed: () => onWeek(1),
                    icon: const Icon(LucideIcons.chevronRight, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: _DayCell(
                        day: weekStart.add(Duration(days: i)),
                        selected: weekStart.add(Duration(days: i)) == selected,
                        hasShift: hasShift(weekStart.add(Duration(days: i))),
                        onTap: () => onDay(weekStart.add(Duration(days: i))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.hasShift, required this.onTap});

  final DateTime day;
  final bool selected;
  final bool hasShift;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (label, fill, ink) = selected
        ? (scheme.onSurface, scheme.primary, scheme.onPrimary)
        : hasShift
        ? (scheme.secondary, scheme.surfaceContainerHighest, scheme.secondary)
        : (scheme.onSurfaceVariant, Colors.transparent, scheme.onSurfaceVariant);
    return Semantics(
      button: true,
      selected: selected,
      label: '${_weekdayLong[day.weekday - 1]}, ${_dm(day)}${hasShift ? ', có ca' : ''}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_weekdayShort[day.weekday - 1], style: theme.textTheme.labelMedium?.copyWith(color: label)),
              const SizedBox(height: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Align(
                      widthFactor: 1,
                      heightFactor: 1,
                      child: Text(
                        '${day.day}',
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: ink),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiêu đề khối 19 đậm (Figma "Chủ nhật, 22/11", "Việc trong ca ngày"), phần bên phải tùy chọn.
class _Heading extends StatelessWidget {
  const _Heading({required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 32),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _TodayChip extends StatelessWidget {
  const _TodayChip();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          'Hôm nay',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.secondary, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Khung trắng bo 12 viền mảnh chứa bảng (Figma "Ca làm việc", "Công việc theo giờ").
class _Table extends StatelessWidget {
  const _Table({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// Đầu nhóm ca (Figma "Đầu nhóm ca hiện tại", "Đầu nhóm ca khác"): ô đồng hồ, tên và giờ ca, trạng thái ở góc phải;
/// ca đang diễn ra nền xanh trời nhạt.
class _ShiftHeader extends StatelessWidget {
  const _ShiftHeader({required this.shift});

  final Map<String, dynamic> shift;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final current = shift['status'] == 'IN_PROGRESS';
    final start = DateTime.parse(shift['startsAt'] as String);
    final end = DateTime.parse(shift['endsAt'] as String);
    final endDay = _day(_vn(end));
    final hours = [
      '${formatTime(start)} – ${formatTime(end)}',
      if (endDay != _day(_vn(start))) 'Kết thúc ${_dm(endDay)}',
    ].join(' · ');
    final status = _shiftStatus[shift['status']];
    return Semantics(
      header: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: current ? scheme.secondaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: current ? scheme.secondaryContainer : scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: current ? scheme.surface : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.menu),
              ),
              child: Icon(LucideIcons.clock, size: 20, color: scheme.secondary),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shiftName(shift), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    hours,
                    style: text.labelLarge?.copyWith(color: current ? scheme.secondary : scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (status != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: current ? scheme.surface : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    status,
                    style: text.labelMedium?.copyWith(
                      color: current ? scheme.secondary : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Dòng người cao tuổi (Figma "Dòng người cao tuổi"): chữ viết tắt, họ tên, phòng, số việc còn lại và số quá hạn.
class _ResidentRow extends StatelessWidget {
  const _ResidentRow({required this.tasks, required this.onTap});

  final List<Map<String, dynamic>> tasks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final first = tasks.first;
    final card = first['residentCard'] as Map?;
    final name = card?['fullName'] as String? ?? first['location'] as String? ?? 'Công việc tầng/khu';
    final remaining = tasks.where((t) => openTaskStatuses.contains(t['status'])).length;
    final overdue = tasks.where((t) => t['status'] == 'OVERDUE').length;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 84),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Initials(name: name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                      if (card?['roomBed'] case final String room)
                        Text(
                          room,
                          style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400),
                        ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        children: [
                          Text(
                            remaining == 0 ? 'Đã xong ${tasks.length} việc' : '$remaining việc còn lại',
                            style: text.labelLarge,
                          ),
                          if (overdue > 0)
                            Text(
                              '$overdue quá hạn',
                              style: text.labelMedium?.copyWith(color: scheme.error, fontWeight: FontWeight.w600),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Khối trắng một dòng chữ xám (Figma "Ca chưa có danh sách").
class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Table(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

/// Khung trắng khi trống (Figma "Danh sách trống", "Ngày không có ca").
class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.title, required this.body, this.icon});

  final IconData? icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _Table(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[Icon(icon, size: 24, color: scheme.secondary), const SizedBox(height: 8)],
              Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
