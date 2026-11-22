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

/// Dòng ca dưới tiêu đề "Việc chăm sóc" (Figma "Ca ngày · 22/11 · 07:00–18:00"): tên, ngày bắt đầu, giờ.
String shiftLabel(Map<String, dynamic> shift) {
  final start = DateTime.parse(shift['startsAt'] as String);
  final end = DateTime.parse(shift['endsAt'] as String);
  return '${shiftName(shift)} · ${_dmPadded(_vn(start))} · ${formatTime(start)}–${formatTime(end)}';
}

/// Tab Checklist theo tuần (Figma "Prototype · Mobile" 98:1671 "Checklist ca · Lịch tuần"): đổi tuần, chọn ngày; mỗi ca
/// bắt đầu trong ngày có đầu nhóm ca rồi bảng "Giờ | Công việc" liệt kê thẳng công việc của ca theo giờ (tên việc, người
/// cao tuổi · phòng, trạng thái). Bấm một dòng mở chi tiết công việc đó ([openTask]) để ghi nhận.
class WeeklyChecklist extends StatefulWidget {
  const WeeklyChecklist({
    super.key,
    required this.shifts,
    required this.repository,
    required this.accountId,
    required this.openTask,
    this.clock = DateTime.now,
  });

  /// Ca đã công bố bắt đầu trong khoảng ngày Việt Nam `[from, to)`.
  final Future<List<Map<String, dynamic>>> Function(DateTime from, DateTime to) shifts;
  final CareChecklistRepository repository;
  final int accountId;
  final Future<void> Function(Map<String, dynamic> shift, Map<String, dynamic> task) openTask;
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

  Future<void> open(Map<String, dynamic> shift, Map<String, dynamic> task) async {
    await widget.openTask(shift, task);
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
            padding: const EdgeInsets.fromLTRB(20, 13, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                    body: 'Chọn ngày khác trên lịch để xem công việc.',
                  )
                else
                  for (final shift in shiftsOn(selectedDay)) ...[
                    _ShiftHeader(shift: shift),
                    const SizedBox(height: 7),
                    ..._tasks(context, shift),
                    const SizedBox(height: 13),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bảng công việc của một ca theo giờ dự kiến (Figma "Công việc theo giờ"); ca chưa có việc thì một dòng báo.
  List<Widget> _tasks(BuildContext context, Map<String, dynamic> shift) {
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
    if (tasks.isEmpty) return const [_NoteBox(text: 'Chưa có công việc trong ca này.')];
    final pending = widget.repository.pendingTaskIds;
    return [
      if (load.offline)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Đang xem bản đã tải, chưa cập nhật.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      _Table(
        children: [
          const _TableHead(),
          for (final task in tasks) ...[
            const Divider(height: 1, thickness: 1),
            _TaskRow(task: task, pending: pending.contains(task['id']), onTap: () => open(shift, task)),
          ],
        ],
      ),
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

/// Đầu bảng nền xám nhạt (Figma "Cột Giờ và Công việc"): cột Giờ rộng 64, vạch dọc, cột Công việc.
class _TableHead extends StatelessWidget {
  const _TableHead();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600);
    return ExcludeSemantics(
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 28),
          child: Row(
            children: [
              SizedBox(width: 64, child: Center(child: Text('Giờ', style: style))),
              Container(width: 1, height: 16, color: scheme.outlineVariant),
              const SizedBox(width: 9),
              Text('Công việc', style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dòng công việc theo giờ (Figma "Checklist / Dòng theo giờ · Thông thường", "· Quá hạn"): giờ dự kiến (đỏ khi quá
/// hạn), vạch dọc, tên việc, người cao tuổi · phòng, nhãn trạng thái, mũi tên.
class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.pending, required this.onTap});

  final Map<String, dynamic> task;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final status = task['status'] as String?;
    final overdue = status == 'OVERDUE';
    final card = task['residentCard'] as Map?;
    final who = [
      card?['fullName'] as String? ?? task['location'] as String? ?? 'Công việc tầng/khu',
      if (card?['roomBed'] case final String room) room,
    ].join(' · ');
    final (label, fill, ink) = switch (status) {
      'OVERDUE' => ('Quá hạn', scheme.errorContainer, scheme.error),
      'DUE' => ('Đến giờ', scheme.surfaceContainerHighest, scheme.secondary),
      'NOT_YET_DUE' => ('Sắp tới', scheme.surfaceContainerHighest, scheme.secondary),
      _ => (_doneStatus[status] ?? status ?? '', scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Material(
      color: scheme.surface,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 77),
          child: Padding(
            padding: const EdgeInsets.only(right: 11),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Center(
                    child: Text(
                      switch (task['plannedAt']) {
                        final String at => formatTime(DateTime.parse(at)),
                        _ => '—',
                      },
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: overdue ? scheme.error : scheme.onSurface,
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 48, color: scheme.outlineVariant),
                const SizedBox(width: 9),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['taskType'] as String? ?? '',
                          style: text.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(who, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            _Tag(label: label, fill: fill, ink: ink),
                            if (pending)
                              _Tag(
                                label: 'Chưa đồng bộ',
                                fill: scheme.surfaceContainerHighest,
                                ink: scheme.onSurfaceVariant,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Icon(LucideIcons.chevronRight, size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _doneStatus = {
  'COMPLETED': 'Hoàn thành',
  'COMPLETED_LATE': 'Hoàn thành trễ',
  'NOT_PERFORMED': 'Không thực hiện',
  'CANCELLED': 'Hủy',
};

/// Nhãn trạng thái nhỏ bo 7 (Figma "Nhãn trạng thái").
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.fill, required this.ink});

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.menu)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink, fontWeight: FontWeight.w600),
      ),
    ),
  );
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
