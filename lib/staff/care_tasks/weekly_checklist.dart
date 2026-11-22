import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/format/date_time.dart';
import '../../common/theme/app_theme.dart';
import 'care_checklist_repository.dart';

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

/// Dòng ca dưới tiêu đề Checklist ca: tên, giờ, ngày bắt đầu.
String shiftLabel(Map<String, dynamic> shift) {
  final start = DateTime.parse(shift['startsAt'] as String);
  final end = DateTime.parse(shift['endsAt'] as String);
  return '${shiftName(shift)} · ${formatTime(start)}–${formatTime(end)} · ${_dmPadded(_vn(start))}';
}

/// Tab Checklist theo tuần (Figma "Prototype · Mobile" 98:1671 "Checklist ca · Lịch tuần"): đổi tuần, chọn ngày, bảng ca
/// của ngày (ca bắt đầu trong ngày đó), việc theo giờ của ca đang xem. "Xem checklist" và bấm một việc mở Checklist ca
/// đầy đủ ([openChecklist], kèm mã việc khi bấm việc) để ghi nhận.
class WeeklyChecklist extends StatefulWidget {
  const WeeklyChecklist({
    super.key,
    required this.shifts,
    required this.repository,
    required this.accountId,
    required this.openChecklist,
    this.clock = DateTime.now,
  });

  /// Ca đã công bố bắt đầu trong khoảng ngày Việt Nam `[from, to)`.
  final Future<List<Map<String, dynamic>>> Function(DateTime from, DateTime to) shifts;
  final CareChecklistRepository repository;
  final int accountId;
  final Future<void> Function(Map<String, dynamic> shift, {int? taskId}) openChecklist;
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
  int? selectedShift;
  CareChecklistLoad? tasks;
  String? taskError;
  bool tasksLoading = false;
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
      selectedShift = null;
      tasks = null;
      taskError = null;
    });
    try {
      final rows = await widget.shifts(weekStart, weekStart.add(const Duration(days: 7)));
      if (!mounted || token != generation) return;
      setState(() => weekShifts = rows);
      if (!keepDay) {
        // Sang tuần khác: chọn ngày đầu tiên có ca, không có thì giữ thứ đang chọn.
        final days = [for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i))];
        selectDay(days.firstWhere((d) => shiftsOn(d).isNotEmpty, orElse: () => days[selectedDay.weekday - 1]));
      } else {
        selectDay(selectedDay);
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

  void selectDay(DateTime day) {
    final rows = shiftsOn(day);
    final current = rows.where((s) => s['status'] == 'IN_PROGRESS').firstOrNull ?? rows.firstOrNull;
    setState(() => selectedDay = day);
    selectShift(current);
  }

  Future<void> selectShift(Map<String, dynamic>? shift) async {
    final token = ++generation;
    setState(() {
      selectedShift = shift?['id'] as int?;
      tasks = null;
      taskError = null;
      tasksLoading = shift != null;
    });
    if (shift == null) return;
    try {
      final load = await widget.repository.load(widget.accountId, shift['id'] as int);
      if (mounted && token == generation) setState(() => tasks = load);
    } on ApiUnreachable {
      if (mounted && token == generation) setState(() => taskError = 'Mất kết nối và chưa có bản tải của ca này.');
    } catch (e) {
      if (mounted && token == generation) {
        setState(() => taskError = (e is ApiProblem ? e.detail : null) ?? 'Chưa tải được công việc của ca.');
      }
    } finally {
      if (mounted && token == generation) setState(() => tasksLoading = false);
    }
  }

  Future<void> open(Map<String, dynamic> shift, {int? taskId}) async {
    await widget.openChecklist(shift, taskId: taskId);
    if (mounted) await selectShift(shift);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shift = (weekShifts ?? []).where((s) => s['id'] == selectedShift).firstOrNull;
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
                const SizedBox(height: 5),
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
                else ...[
                  _ShiftTable(shifts: shiftsOn(selectedDay), selected: selectedShift, onSelect: selectShift),
                  if (shift != null) ...[
                    const SizedBox(height: 12),
                    _Heading(
                      text: 'Việc trong ${shiftName(shift).toLowerCase()}',
                      trailing: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          foregroundColor: theme.colorScheme.secondary,
                          textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        onPressed: () => open(shift),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Xem checklist'),
                            SizedBox(width: 3),
                            Icon(LucideIcons.chevronRight, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (tasksLoading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (taskError != null)
                      Text(taskError!, style: theme.textTheme.bodyMedium)
                    else if (tasks != null)
                      _TaskTable(
                        tasks: (tasks!.snapshot.content['tasks'] as List? ?? [])
                            .map((t) => Map<String, dynamic>.from(t as Map))
                            .toList(),
                        offline: tasks!.offline,
                        onTask: (id) => open(shift, taskId: id),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
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

/// Một dòng hai cột: cột giờ rộng 81, vạch dọc, nội dung.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.height,
    required this.time,
    required this.child,
    this.background,
    this.onTap,
    this.trailing,
  });

  final double height;
  final Widget time;
  final Widget child;
  final Color? background;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: background ?? scheme.surface,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: [
                SizedBox(width: 81, child: Center(child: time)),
                Container(width: 1, height: height - 18, color: scheme.outlineVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: child),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShiftTable extends StatelessWidget {
  const _ShiftTable({required this.shifts, required this.selected, required this.onSelect});

  final List<Map<String, dynamic>> shifts;
  final int? selected;
  final void Function(Map<String, dynamic>) onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final head = text.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600);
    return _Table(
      children: [
        ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: SizedBox(
            height: 32,
            child: Row(
              children: [
                SizedBox(
                  width: 81,
                  child: Center(child: Text('Giờ', style: head)),
                ),
                Container(width: 1, height: 18, color: scheme.outlineVariant),
                const SizedBox(width: 12),
                Text('Ca làm việc', style: head),
              ],
            ),
          ),
        ),
        for (final (i, shift) in shifts.indexed) ...[
          if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
          _shiftRow(context, shift),
        ],
      ],
    );
  }

  Widget _shiftRow(BuildContext context, Map<String, dynamic> shift) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final isSelected = shift['id'] == selected;
    final start = DateTime.parse(shift['startsAt'] as String);
    final end = DateTime.parse(shift['endsAt'] as String);
    final endDay = _day(_vn(end));
    final status = [
      ?_shiftStatus[shift['status']],
      if (endDay != _day(_vn(start)) && shift['status'] != 'IN_PROGRESS') 'Kết thúc ${_dm(endDay)}',
    ].join(' · ');
    final accent = isSelected ? scheme.secondary : null;
    return Semantics(
      selected: isSelected,
      button: true,
      child: _TimeRow(
        height: 66,
        background: isSelected ? scheme.secondaryContainer : null,
        onTap: () => onSelect(shift),
        time: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatTime(start),
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: accent ?? scheme.onSurface),
            ),
            const SizedBox(height: 3),
            Text(
              formatTime(end),
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        trailing: isSelected
            ? DecoratedBox(
                decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.menu)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  child: Text(
                    'Đang xem',
                    style: text.labelSmall?.copyWith(color: scheme.secondary, fontWeight: FontWeight.w600),
                  ),
                ),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shiftName(shift), style: text.titleMedium),
            const SizedBox(height: 4),
            Text(status, style: text.labelLarge?.copyWith(color: accent ?? scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// "Công việc theo giờ": nhóm Quá hạn (nền đỏ nhạt, đếm việc), Đến giờ, Sắp tới, Đã xong; mỗi việc có giờ dự kiến bên trái.
class _TaskTable extends StatelessWidget {
  const _TaskTable({required this.tasks, required this.offline, required this.onTask});

  final List<Map<String, dynamic>> tasks;
  final bool offline;
  final void Function(int id) onTask;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    if (tasks.isEmpty) {
      return const _EmptyBox(
        title: 'Chưa có công việc để hiển thị',
        body: 'Checklist của ca sẽ hiện tại đây khi có công việc.',
      );
    }
    final sorted = [...tasks]
      ..sort((a, b) => (a['plannedAt'] as String? ?? '').compareTo(b['plannedAt'] as String? ?? ''));
    List<Map<String, dynamic>> of(bool Function(Object?) test) => sorted.where((t) => test(t['status'])).toList();
    final overdue = of((s) => s == 'OVERDUE');
    final groups = [
      ('Quá hạn · ${overdue.length} việc', scheme.errorContainer, scheme.error, overdue),
      ('Đến giờ', scheme.surfaceContainerHighest, scheme.primary, of((s) => s == 'DUE')),
      ('Sắp tới', scheme.surfaceContainerHighest, scheme.primary, of((s) => s == 'NOT_YET_DUE')),
      (
        'Đã xong',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        of((s) => !const {'OVERDUE', 'DUE', 'NOT_YET_DUE'}.contains(s)),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Đang xem bản đã tải, chưa cập nhật.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        _Table(
          children: [
            for (final (label, fill, ink, rows) in groups)
              if (rows.isNotEmpty) ...[
                ColoredBox(
                  color: fill,
                  child: SizedBox(
                    height: 30,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          style: text.labelMedium?.copyWith(color: ink, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
                for (final (i, task) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  _taskRow(context, task),
                ],
              ],
          ],
        ),
      ],
    );
  }

  Widget _taskRow(BuildContext context, Map<String, dynamic> task) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final card = task['residentCard'] as Map?;
    final at = task['plannedAt'] as String?;
    final where = [
      card?['fullName'] as String? ?? task['location'] as String? ?? 'Công việc tầng/khu',
      if (card?['roomBed'] case final String roomBed) roomBed,
    ].join(' · ');
    return _TimeRow(
      height: 58,
      onTap: () => onTask(task['id'] as int),
      time: Text(
        at == null ? '—' : formatTime(DateTime.parse(at)),
        style: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: task['status'] == 'OVERDUE' ? scheme.error : scheme.onSurface,
        ),
      ),
      trailing: Icon(LucideIcons.chevronRight, size: 18, color: scheme.onSurfaceVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task['taskType'] as String? ?? '', style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(where, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
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
