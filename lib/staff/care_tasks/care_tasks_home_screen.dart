import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/offline/offline_queue.dart';
import '../../common/widgets/page_body.dart';
import '../handover/handover_screen.dart';
import '../incidents/record_incident_screen.dart';
import '../medication/medication_round_repository.dart';
import 'ad_hoc_care_recording_screen.dart';
import 'care_api_gateways.dart';
import 'care_checklist_cache.dart';
import 'care_checklist_gateway.dart';
import 'care_checklist_links.dart';
import 'care_checklist_repository.dart';
import 'care_checklist_screen.dart';
import 'care_offline_recording.dart';
import 'care_plans_screen.dart';
import 'day_care_attendance_screen.dart';
import 'overdue_tasks_screen.dart';
import 'shift_task_planning_screen.dart';
import 'weekly_checklist.dart';

/// T026/T031/T040/T046: lối vào màn005; quyền lấy từ backend, không suy theo vai trò.
class CareTasksHomeScreen extends StatefulWidget {
  const CareTasksHomeScreen({
    super.key,
    required this.api,
    required this.accountId,
    this.queue,
    this.cache,
    this.medication,
    this.clock = DateTime.now,
  });
  final ApiClient api;
  final int accountId;
  final OfflineQueue? queue;
  final CareChecklistCache? cache;

  /// Kho vòng phát thuốc khi có quyền phát thuốc; dòng liều trong Checklist ca bấm được (spec 2026-11-20 mục 5.2).
  final MedicationRoundRepository? medication;
  final DateTime Function() clock;
  @override
  State<CareTasksHomeScreen> createState() => _CareTasksHomeScreenState();
}

class _CareTasksHomeScreenState extends State<CareTasksHomeScreen> {
  Set<String>? permissions;
  String? error;
  List<int>? offlineShifts;
  CareChecklistCache? _ownCache;
  CareChecklistRepository? _repository;

  /// Một kết nối cache cho cả màn (mở nhiều lần cùng tệp thì drift cảnh báo tranh chấp); màn tự mở thì tự đóng.
  CareChecklistCache get cache => widget.cache ?? (_ownCache ??= CareChecklistCache.onDevice());

  CareChecklistRepository get repository => _repository ??= CareChecklistRepository(
    ApiCareChecklistGateway(widget.api),
    cache,
    recorder: widget.queue == null ? null : CareOfflineRecording(widget.api, widget.queue!, widget.accountId),
  );

  @override
  void dispose() {
    _ownCache?.close();
    super.dispose();
  }

  Future<void> openChecklist(Map<String, dynamic> shift, {int? taskId}) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CareChecklistScreen(
        repository: repository,
        accountId: widget.accountId,
        shiftId: shift['id'] as int,
        shiftLabel: shiftLabel(shift),
        initialTaskId: taskId,
        links: apiCareChecklistLinks(widget.api),
        medication: widget.medication,
        alertsApi: widget.api,
      ),
    ),
  );
  Future<void> load() async {
    try {
      final rows = await widget.api.getList('/me/permissions');
      final current = rows.whereType<Map<String, dynamic>>().map((p) => '${p['function']}:${p['operation']}').toSet();
      if (!current.contains('TASK_CHECKLIST:VIEW')) {
        await cache.clearAccount(widget.accountId);
      }
      if (mounted) {
        setState(() {
          permissions = current;
          error = null;
          offlineShifts = null;
        });
      }
    } on ApiUnreachable {
      final cached = await cache.shiftIds(widget.accountId);
      if (mounted) {
        setState(() {
          offlineShifts = cached;
          error = 'Đang ngoại tuyến. Chỉ mở được checklist đã tải của tài khoản này.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiProblem ? e.detail : 'Không tải được quyền. Kiểm tra kết nối rồi thử lại.');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  bool can(String function, String operation) => permissions?.contains('$function:$operation') == true;
  void open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// Ngoại tuyến: chỉ mở được checklist đã tải của tài khoản này, chọn theo mã ca (bản tải không có giờ ca).
  Future<void> offlineChecklist() async {
    final ids = offlineShifts ?? const <int>[];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Chọn ca xem checklist'),
        children: [
          for (final id in ids)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, id), child: Text('Ca $id')),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CareChecklistScreen(
          repository: repository,
          accountId: widget.accountId,
          shiftId: selected,
          links: apiCareChecklistLinks(widget.api),
          medication: widget.medication,
          alertsApi: widget.api,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tools = <(IconData, String, VoidCallback)>[
      if (can('TASK_CHECKLIST', 'CREATE') && widget.queue != null)
        (
          LucideIcons.clipboardPlus,
          'Ghi nhận phát sinh',
          () => open(AdHocCareRecordingScreen(api: widget.api, queue: widget.queue!, accountId: widget.accountId)),
        ),
      if (can('SHIFT_TASK_PLANNING', 'VIEW'))
        (
          LucideIcons.clipboardList,
          'Lập công việc của ca',
          () => open(
            Scaffold(
              appBar: AppBar(title: const Text('Lập công việc của ca')),
              body: ShiftTaskPlanningScreen(gateway: ApiCareTaskPlanningGateway(widget.api)),
            ),
          ),
        ),
      if (can('DAY_CARE_ATTENDANCE', 'VIEW'))
        (
          LucideIcons.userCheck,
          'Điểm danh bán trú',
          () {
            final day = widget.clock().toUtc().add(const Duration(hours: 7));
            final date = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            open(
              Scaffold(
                appBar: AppBar(title: const Text('Điểm danh bán trú')),
                body: DayCareAttendanceScreen(gateway: ApiDayCareAttendanceGateway(widget.api), date: date),
              ),
            );
          },
        ),
      if (can('OVERDUE_TASK_HANDLING', 'VIEW'))
        (
          LucideIcons.clockAlert,
          'Công việc quá hạn',
          () => open(
            Scaffold(
              appBar: AppBar(title: const Text('Công việc quá hạn')),
              body: OverdueTasksScreen(
                accountId: widget.accountId,
                canView: true,
                load: (_, floor) async => (await widget.api.getList(
                  '/care-tasks/overdue${floor == null ? '' : '?floorAreaId=$floor'}',
                )).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
              ),
            ),
          ),
        ),
    ];
    final toolBlock = tools.isEmpty
        ? null
        : Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: ListTile.divideTiles(
                context: context,
                tiles: [for (final t in tools) _toolTile(t, t.$3)],
              ).toList(),
            ),
          );
    // Figma 98:1671: có quyền checklist và đang có mạng thì tab là Checklist theo tuần; các việc chăm sóc khác xếp sau.
    if (can('TASK_CHECKLIST', 'VIEW') && error == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: WeeklyChecklist(
              shifts: ApiCareTaskPlanningGateway(widget.api).shiftsBetween,
              repository: repository,
              accountId: widget.accountId,
              openChecklist: openChecklist,
              clock: widget.clock,
            ),
          ),
          if (toolBlock != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _ToolsButton(tools: tools),
              ),
            ),
        ],
      );
    }
    return PageBody(
      child: ListView(
        children: [
          if (offlineShifts?.isNotEmpty == true)
            ListTile(title: const Text('Checklist đã tải (ngoại tuyến)'), onTap: offlineChecklist),
          if (error != null) ...[
            Semantics(liveRegion: true, child: Text(error!)),
            OutlinedButton(onPressed: load, child: const Text('Thử lại')),
          ],
          if (permissions == null && error == null) const Center(child: CircularProgressIndicator()),
          ?toolBlock,
          if (permissions != null &&
              ![
                'TASK_CHECKLIST',
                'SHIFT_TASK_PLANNING',
                'DAY_CARE_ATTENDANCE',
                'OVERDUE_TASK_HANDLING',
              ].any((f) => can(f, 'VIEW')))
            const Text('Bạn không có quyền mở màn chăm sóc hằng ngày.'),
        ],
      ),
    );
  }
}

/// Lối vào các việc chăm sóc khác (Ghi nhận phát sinh, Lập công việc, Điểm danh, Quá hạn) dưới Checklist theo tuần:
/// Figma chỉ vẽ lịch và việc của ca, nên gom vào một nút mở bảng dưới để không mất lối vào.
class _ToolsButton extends StatelessWidget {
  const _ToolsButton({required this.tools});

  final List<(IconData, String, VoidCallback)> tools;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(LucideIcons.clipboardList),
    label: const Text('Việc chăm sóc khác'),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Việc chăm sóc khác', style: Theme.of(context).textTheme.titleMedium),
            ),
            ...ListTile.divideTiles(
              context: context,
              tiles: [
                for (final t in tools)
                  _toolTile(t, () {
                    Navigator.pop(context);
                    t.$3();
                  }),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _toolTile((IconData, String, VoidCallback) tool, VoidCallback onTap) => ListTile(
  leading: Icon(tool.$1),
  title: Text(tool.$2),
  trailing: const Icon(LucideIcons.chevronRight),
  onTap: onTap,
);

/// Lối đi của Checklist ca bằng API thật: màn Bàn giao ca chọn sẵn ca, kế hoạch chăm sóc, form Báo sự cố.
CareChecklistLinks apiCareChecklistLinks(ApiClient api) => CareChecklistLinks(
  openHandover: (context, shiftId) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Bàn giao ca')),
        body: HandoverScreen(api: api, initialShiftId: shiftId),
      ),
    ),
  ),
  openPlans: (context, residents) => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => CarePlansScreen(api: api, residents: residents))),
  reportIncident: (context, residentId) async =>
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => RecordIncidentScreen(api: api, residentId: residentId)),
      ) ==
      true,
);
