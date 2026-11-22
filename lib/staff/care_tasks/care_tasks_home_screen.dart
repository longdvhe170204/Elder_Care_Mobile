import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/offline/offline_queue.dart';
import '../../common/widgets/page_body.dart';
import '../handover/handover_screen.dart';
import '../incidents/record_incident_screen.dart';
import '../medication/medication_round_repository.dart';
import 'care_api_gateways.dart';
import 'care_checklist_cache.dart';
import 'care_checklist_gateway.dart';
import 'care_checklist_links.dart';
import 'care_checklist_repository.dart';
import 'care_checklist_screen.dart';
import 'care_offline_recording.dart';
import 'care_plans_screen.dart';
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

  Future<void> openTask(Map<String, dynamic> shift, Map<String, dynamic> task) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CareChecklistScreen(
        repository: repository,
        accountId: widget.accountId,
        shiftId: shift['id'] as int,
        shiftLabel: shiftLabel(shift),
        taskId: task['id'] as int,
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
    // Figma 98:1671: có quyền checklist và đang có mạng thì tab chỉ là Checklist theo tuần. Không còn "Việc chăm sóc
    // khác" (chủ dự án 2026-11-22): Ghi nhận phát sinh trùng Báo sự cố, Lập công việc của ca ngoài quyền Điều dưỡng,
    // Điểm danh bán trú chuyển sang tab Ca của tôi.
    if (can('TASK_CHECKLIST', 'VIEW') && error == null) {
      return WeeklyChecklist(
        shifts: ApiCareTaskPlanningGateway(widget.api).shiftsBetween,
        repository: repository,
        accountId: widget.accountId,
        openTask: openTask,
        clock: widget.clock,
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
          if (permissions != null && !can('TASK_CHECKLIST', 'VIEW'))
            const Text('Bạn không có quyền mở Checklist ca.'),
        ],
      ),
    );
  }
}

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
