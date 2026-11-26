import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../common/api/api_client.dart';
import '../common/auth/session_controller.dart';
import '../common/notifications/notification_api.dart';
import '../common/notifications/push_coordinator.dart';
import '../common/offline/offline_queue.dart';
import '../common/theme/app_theme.dart';
import '../common/widgets/header_app_bar.dart';
import 'account/staff_account_screen.dart';
import 'activities/session_list_screen.dart';
import 'activities/trip_list_screen.dart';
import 'alerts/alerts_screen.dart';
import 'alerts/emergency_assist_screen.dart';
import 'approval_requests/approval_inbox_screen.dart';
import 'beds/beds_screen.dart';
import 'care_tasks/care_api_gateways.dart';
import 'care_tasks/care_tasks_home_screen.dart';
import 'care_tasks/day_care_attendance_screen.dart';
import 'early_unlock/early_unlock_screen.dart';
import 'handover/handover_cache.dart';
import 'handover/handover_screen.dart';
import 'incidents/incidents_screen.dart';
import 'incidents/record_incident_screen.dart';
import 'medication/family_medication_screen.dart';
import 'medication/medication_labels.dart';
import 'medication/medication_round_cache.dart';
import 'medication/medication_round_gateway.dart';
import 'medication/medication_round_repository.dart';
import 'medication/medication_round_screen.dart';
import 'medication/supplied_intake_screen.dart';
import 'notifications/staff_inbox_screen.dart';
import 'nutrition/family_food_screen.dart';
import 'nutrition/meal_slip_screen.dart';
import 'nutrition/shared_menu_screen.dart';
import 'pending_review/pending_review_screen.dart';
import 'resident_login_qr/resident_login_qr_screen.dart';
import 'residents/resident_lookup_screen.dart';
import 'shift_home/shift_home_screen.dart';
import 'shift_swaps/shift_swaps_screen.dart';
import 'shifts/assignments_screen.dart';
import 'shifts/my_shifts_screen.dart';
import 'staff_dashboard_style.dart';
import 'staff_navigation.dart';
import 'sync_results/sync_results_screen.dart';

/// Ba tab của app nhân viên. Các lối vào nghiệp vụ trên Trang chủ lọc theo vai trò và quyền.
class StaffRoot extends StatefulWidget {
  const StaffRoot({super.key, required this.session, required this.queue, this.push});

  final SessionController session;
  final OfflineQueue queue;
  final PushCoordinator? push;

  @override
  State<StaffRoot> createState() => _StaffRootState();
}

typedef _Item = (String label, String? subtitle, IconData icon, Widget Function() body);

class _StaffRootState extends State<StaffRoot> {
  StaffTab _tab = StaffTab.home;
  int _urgent = 0;
  bool _urgentBand = false;
  int _unsynced = 0;

  /// Quyền hiện hành dạng `CHUC_NANG:THAO_TAC` từ `/me/permissions`; chưa tải được thì rỗng, mục theo quyền không hiện.
  Set<String> _grants = const {};

  /// 003 T060: Trưởng tầng, Người phụ trách ca đọc được giường Chờ sẵn sàng của tầng (`GET /bed-readiness/beds` trả 200);
  /// ô ⁴⁰ của Điều dưỡng chỉ có ở lớp nhiệm vụ nên không có trong `/me/permissions`.
  bool _readinessDuty = false;

  /// Bộ nhớ đệm vòng phát thuốc trên máy (006 T028): mở một lần, đóng khi rời phần nhân viên.
  MedicationRoundCache? _medicationCache;

  SessionController get _session => widget.session;

  StaffNavigation get _nav =>
      buildStaffNavigation(roles: _session.user?.roles ?? const {}, grants: _grants, readinessDuty: _readinessDuty);

  @override
  void initState() {
    super.initState();
    widget.push?.addListener(_onPush);
    unawaited(_loadPermissions());
    unawaited(_loadUnsynced());
    // Thông báo không còn là tab mở mặc định: tải số Khẩn cấp chưa xác nhận cho huy hiệu ngay khi vào (009 T022).
    unawaited(_refreshUrgent());
  }

  Future<void> _loadPermissions() async {
    var grants = <String>{};
    try {
      grants = {
        for (final grant in (await _session.api.getList('/me/permissions')).whereType<Map<String, dynamic>>())
          '${grant['function']}:${grant['operation']}',
      };
    } on ApiUnreachable {
      return;
    } on Object {
      // Chưa xác nhận được quyền thì không mở mục theo quyền.
    }
    var readinessDuty = false;
    if (!grants.contains('ROOM_BED_CONFIGURATION:VIEW') && (_session.user?.roles.contains('AC-02') ?? false)) {
      try {
        await _session.api.getList('/bed-readiness/beds');
        readinessDuty = true;
      } on ApiUnreachable {
        readinessDuty = _readinessDuty;
      } on Object {
        // Chưa xác nhận được nhiệm vụ thì không hiện mục Giường.
      }
    }
    if (mounted) {
      setState(() {
        _grants = grants;
        _readinessDuty = readinessDuty;
      });
    }
  }

  Future<void> _loadUnsynced() async {
    final accountId = _session.user?.accountId;
    if (accountId == null) return;
    try {
      final count = (await widget.queue.unsynced(accountId)).length;
      if (mounted) setState(() => _unsynced = count);
    } on Object {
      // Không đọc được hàng đợi thì không hiện số.
    }
  }

  @override
  void dispose() {
    widget.push?.removeListener(_onPush);
    unawaited(_medicationCache?.close());
    super.dispose();
  }

  /// Ngày hôm nay theo máy, `yyyy-MM-dd` cho danh sách chuyến (014 T018).
  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  /// Hộp đang mở tự tải lại và mở thông báo; tab khác thì chuyển sang hộp hoặc báo.
  void _onPush() {
    final push = widget.push!;
    final urgent = push.takeUrgent();
    if (_tab == StaffTab.inbox) return;
    if (push.hasOpened) {
      _selectTab(StaffTab.inbox);
      return;
    }
    if (urgent) setState(() => _urgentBand = true);
    _refreshUrgent();
  }

  Future<void> _refreshUrgent() async {
    try {
      _setUrgent((await NotificationApi(_session.api).page()).urgentCount);
    } on Exception {
      // giữ số trước đó, hộp thông báo báo lỗi tải khi mở
    }
  }

  void _setUrgent(int count) {
    if (mounted) setState(() => _urgent = count);
  }

  void _selectTab(StaffTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      if (tab == StaffTab.inbox) _urgentBand = false;
    });
    if (tab == StaffTab.home) unawaited(_loadUnsynced());
  }

  Future<void> _refreshDashboard() async {
    await Future.wait([_loadPermissions(), _loadUnsynced(), _refreshUrgent()]);
  }

  int get _accountId => _session.user!.accountId;

  bool get _canRunMedicationRound =>
      _grants.contains('MEDICATION_ADMINISTRATION:VIEW') || _grants.contains('MEDICATION_ADMINISTRATION:PROFESSIONAL');

  Widget _careTasks() => CareTasksHomeScreen(
    api: _session.api,
    accountId: _accountId,
    queue: widget.queue,
    medication: _canRunMedicationRound ? _medicationRepository() : null,
  );

  MedicationRoundRepository _medicationRepository() => MedicationRoundRepository(
    ApiMedicationRoundGateway(_session.api),
    _medicationCache ??= MedicationRoundCache.onDevice(),
    widget.queue,
  );

  Future<int> _pendingMedicationCount() async {
    final doses = await ApiMedicationRoundGateway(_session.api).rounds();
    final pending = {
      for (final record in await widget.queue.unsynced(_accountId))
        if (record.recordType == doseResultRecordType) (jsonDecode(record.content) as Map)['doseKey'],
    };
    return doses
        .where((dose) => doseRecordable(dose['status'] as String?) && !pending.contains(dose['doseKey']))
        .length;
  }

  _Item _feature(StaffFeature feature) {
    final api = _session.api;
    return switch (feature) {
      StaffFeature.medicationIntake => (
        'Tiếp nhận thuốc',
        'Thuốc viện cung cấp',
        LucideIcons.packageCheck,
        () => SuppliedIntakeScreen(api: api),
      ),
      StaffFeature.familyMedication => (
        'Thuốc gia đình gửi',
        'Lô thuốc gia đình gửi',
        LucideIcons.packageOpen,
        () => FamilyMedicationScreen(api: api),
      ),
      StaffFeature.incidents => ('Sự cố', 'Danh sách sự cố', LucideIcons.siren, () => IncidentsScreen(api: api)),
      StaffFeature.alerts => ('Cảnh báo', 'Cảnh báo cần xử lý', LucideIcons.bellRing, () => AlertsScreen(api: api)),
      StaffFeature.sharedMenu => (
        'Thực đơn',
        'Thực đơn hôm nay và cả tuần',
        LucideIcons.utensils,
        () => SharedMenuScreen(api: api),
      ),
      StaffFeature.mealSlipFloor => (
        'Phiếu bữa ăn',
        'Nhận suất ăn tại tầng',
        LucideIcons.clipboardList,
        () => MealSlipScreen(api: api),
      ),
      StaffFeature.activitySessions => (
        'Điểm danh buổi hoạt động',
        null,
        LucideIcons.listChecks,
        () => SessionListScreen(api: api, queue: widget.queue, accountId: _accountId, date: _today()),
      ),
      StaffFeature.trips => (
        'Hoạt động ngoài viện',
        null,
        LucideIcons.bus,
        () => TripListScreen(api: api, queue: widget.queue, accountId: _accountId, date: _today()),
      ),
      StaffFeature.assignments => ('Phân công', null, LucideIcons.users, () => AssignmentsScreen(api: api)),
      StaffFeature.beds => ('Giường', 'Giường chờ sẵn sàng', LucideIcons.bedDouble, () => BedsScreen(api: api)),
      StaffFeature.carePlanApproval => ('Kế hoạch chăm sóc', null, LucideIcons.clipboardCheck, _careTasks),
      StaffFeature.familyFood => ('Đồ ăn gia đình', null, LucideIcons.apple, () => FamilyFoodScreen(api: api)),
      StaffFeature.residentLoginQr => (
        'Mã đăng nhập',
        'Dành cho người cao tuổi',
        LucideIcons.qrCode,
        () => ResidentLoginQrScreen(api: api),
      ),
      StaffFeature.syncResults => (
        'Đồng bộ',
        _unsynced > 0 ? '$_unsynced bản ghi chưa đồng bộ' : 'Bản ghi trên thiết bị',
        LucideIcons.refreshCw,
        () => SyncResultsScreen(queue: widget.queue, session: _session),
      ),
      StaffFeature.pendingReview => (
        'Chờ xem lại',
        'Bản ghi cần xem lại',
        LucideIcons.listChecks,
        () => PendingReviewScreen(api: api),
      ),
      StaffFeature.earlyUnlock => (
        'Mở khóa sớm',
        'Tài khoản đang khóa tạm',
        LucideIcons.lockOpen,
        () => EarlyUnlockScreen(api: api),
      ),
    };
  }

  Future<void> _open(String title, Widget Function() body, {bool standalone = false}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => standalone
            ? body()
            : Scaffold(
                appBar: headerAppBar(context, title: title),
                body: body(),
              ),
      ),
    );
    if (mounted) await _loadUnsynced();
  }

  StaffShortcut _shortcut(
    String title,
    Widget icon,
    StaffShortcutTone tone,
    Widget Function() body, {
    String? subtitle,
    String? pageTitle,
    StaffShortcutSummary? summary,
    bool standalone = false,
  }) => StaffShortcut(
    title,
    icon,
    tone,
    () => _open(pageTitle ?? title, body, standalone: standalone),
    subtitle: subtitle,
    summary: summary,
  );

  StaffShortcut _featureShortcut(StaffFeature feature) {
    final (label, subtitle, icon, body) = _feature(feature);
    final (asset, tone) = switch (feature) {
      StaffFeature.syncResults => ('sync', StaffShortcutTone.indigo),
      StaffFeature.pendingReview => ('checklist', StaffShortcutTone.paleBlue),
      StaffFeature.earlyUnlock => ('unlock', StaffShortcutTone.paleGold),
      StaffFeature.residentLoginQr => ('qr', StaffShortcutTone.paleViolet),
      _ => (null, StaffShortcutTone.sky),
    };
    return _shortcut(
      label,
      asset == null ? Icon(icon) : StaffDashboardIcon(asset, color: Theme.of(context).colorScheme.secondary),
      tone,
      body,
      subtitle: subtitle,
      standalone: const {
        StaffFeature.familyMedication,
        StaffFeature.sharedMenu,
        StaffFeature.activitySessions,
        StaffFeature.trips,
        StaffFeature.beds,
      }.contains(feature),
    );
  }

  Widget _home(StaffNavigation nav) {
    final api = _session.api;
    final primary = nav.primary!;
    final secondary = Theme.of(context).colorScheme.secondary;
    StaffDashboardIcon icon(String name) => StaffDashboardIcon(name, color: secondary);
    final checklist = primary == StaffPrimary.checklist || primary == StaffPrimary.floorToday;
    return ShiftHomeScreen(
      api: api,
      urgentCount: _urgent,
      onOpenInbox: () => _selectTab(StaffTab.inbox),
      refreshDashboard: _refreshDashboard,
      showTaskSummary: checklist && _grants.contains('TASK_CHECKLIST:VIEW'),
      loadMedicationCount: _canRunMedicationRound ? _pendingMedicationCount : null,
      work: [
        if (checklist)
          _shortcut(
            'Checklist ca',
            icon('checklist'),
            StaffShortcutTone.blue,
            _careTasks,
            pageTitle: primary == StaffPrimary.floorToday ? 'Tầng hôm nay' : null,
            summary: StaffShortcutSummary.overdueTasks,
          ),
        if (primary == StaffPrimary.mealSlips)
          _shortcut(
            'Phiếu bữa ăn',
            const Icon(LucideIcons.utensils),
            StaffShortcutTone.blue,
            () => MealSlipScreen(api: api),
          ),
        if (_grants.contains('SHIFT_SCHEDULE:VIEW'))
          _shortcut(
            'Lịch ca và đơn',
            icon('calendar'),
            StaffShortcutTone.violet,
            () => _ScheduleAndRequests(api: api, showRequests: _grants.contains('SHIFT_SWAP_REQUEST:VIEW')),
          ),
        if (_canRunMedicationRound)
          _shortcut(
            'Phát thuốc',
            icon('pill'),
            StaffShortcutTone.green,
            () => MedicationRoundScreen(repository: _medicationRepository(), accountId: _accountId),
            standalone: true,
            summary: StaffShortcutSummary.pendingDoses,
          ),
        if (nav.showHandover)
          _shortcut(
            'Bàn giao ca',
            icon('handover'),
            StaffShortcutTone.gold,
            () => HandoverScreen(api: api, cache: HandoverCache(_session.store, _accountId)),
          ),
      ],
      tools: [
        _shortcut(
          'Tra cứu',
          icon('people'),
          StaffShortcutTone.sky,
          () => ResidentLookupScreen(api: api),
          subtitle: 'Người cao tuổi',
          pageTitle: primary == StaffPrimary.residents ? 'Người cao tuổi' : null,
        ),
        for (final feature in nav.tools) _featureShortcut(feature),
        _shortcut('Phê duyệt', icon('approval'), StaffShortcutTone.paleGreen, () => ApprovalInboxScreen(api: api)),
        if (nav.work.contains(StaffFeature.residentLoginQr)) _featureShortcut(StaffFeature.residentLoginQr),
      ],
      other: [
        _shortcut('Báo sự cố', icon('sos'), StaffShortcutTone.paleGold, () => RecordIncidentScreen(api: api)),
        if (_grants.contains('DAY_CARE_ATTENDANCE:VIEW'))
          _shortcut(
            'Điểm danh bán trú',
            const Icon(LucideIcons.userCheck),
            StaffShortcutTone.paleGreen,
            () => DayCareAttendanceScreen(
              gateway: ApiDayCareAttendanceGateway(api),
              date: DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10),
            ),
          ),
        for (final feature in nav.work)
          if (feature != StaffFeature.residentLoginQr &&
              (feature != StaffFeature.mealSlipFloor || primary != StaffPrimary.mealSlips))
            _featureShortcut(feature),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = _nav;
    if (nav.primary == null) return _WebOnly(onSignOut: () => _session.signOut());
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    final fullName = _session.user?.fullName?.trim() ?? '';
    final name = fullName.isNotEmpty ? fullName : _session.username ?? 'Nhân viên';
    final role = staffRoleLabel(_session.user?.roles ?? const {});
    final extraTextHeight = (MediaQuery.textScalerOf(context).scale(16) - 16).clamp(0.0, double.infinity).toDouble();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        toolbarHeight: 70 + extraTextHeight * 2,
        backgroundColor: tones.header,
        foregroundColor: tones.headerInkStrong,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _tab == StaffTab.home
              ? StaffIdentity(name: name, role: role, inHeader: true)
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _tab.label,
                    style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28, color: tones.headerInkStrong),
                  ),
                ),
        ),
        actions: [
          _EmergencyButton(onPressed: () => _open('Hỗ trợ khẩn cấp', () => EmergencyAssistScreen(api: _session.api))),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            if (_urgentBand && (_tab != StaffTab.home || _urgent == 0))
              _UrgentBand(onOpen: () => _selectTab(StaffTab.inbox)),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: switch (_tab) {
                  StaffTab.home => _home(nav),
                  StaffTab.inbox => StaffInboxScreen(api: _session.api, push: widget.push, onUrgentCount: _setUrgent),
                  StaffTab.account => StaffAccountScreen(session: _session, name: name, role: role),
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
        child: NavigationBarTheme(
          data: theme.navigationBarTheme.copyWith(
            labelTextStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium?.copyWith(color: tones.headerInkStrong)),
            backgroundColor: tones.header,
            indicatorColor: scheme.brightness == Brightness.light ? scheme.primary : scheme.secondaryContainer,
          ),
          child: NavigationBar(
            height: 68,
            selectedIndex: _tab.index,
            onDestinationSelected: (index) => _selectTab(StaffTab.values[index]),
            destinations: [
              for (final tab in StaffTab.values)
                NavigationDestination(
                  icon: tab == StaffTab.inbox
                      ? Badge.count(
                          count: _urgent,
                          isLabelVisible: _urgent > 0,
                          backgroundColor: scheme.error,
                          textColor: scheme.onError,
                          child: StaffDashboardIcon(tab.icon, color: tones.headerInk),
                        )
                      : StaffDashboardIcon(tab.icon, color: tones.headerInk),
                  label: tab.label,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút Hỗ trợ khẩn cấp trên đầu màn (Q-375, BR-M05-29): chữ kèm biểu tượng, đỏ vì là việc gấp.
class _EmergencyButton extends StatelessWidget {
  const _EmergencyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 160),
        child: TextButton(
          style: TextButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            minimumSize: const Size(112, 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          onPressed: onPressed,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StaffDashboardIcon('sos', color: scheme.onError),
              const SizedBox(width: 7),
              const Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, child: Text('Khẩn cấp')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Lịch ca và đơn" mở từ Ca của tôi: lịch ca (008 FR-054) và, khi có quyền, đổi ca, nghỉ đột xuất (015 US3, US4).
class _ScheduleAndRequests extends StatelessWidget {
  const _ScheduleAndRequests({required this.api, required this.showRequests});

  final ApiClient api;
  final bool showRequests;

  @override
  Widget build(BuildContext context) {
    if (!showRequests) return MyShiftsScreen(api: api);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Lịch ca'),
              Tab(text: 'Đổi ca, nghỉ'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                MyShiftsScreen(api: api),
                ShiftSwapsScreen(api: api),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tài khoản nhân viên không có vai trò dùng app (Phụ lục 26.1: Quản lý viện, Hành chính, Kế toán chỉ dùng web).
class _WebOnly extends StatelessWidget {
  const _WebOnly({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: headerAppBar(context, title: 'Elder Care'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vai trò của bạn dùng trên web quản trị', style: text.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Ứng dụng di động dành cho nhân viên làm việc tại tầng, người thân và người cao tuổi.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(LucideIcons.logOut),
              label: const Text('Đăng xuất'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dải báo Khẩn cấp vừa tới khi đang ở tab khác; đỏ vì đây là việc gấp (DESIGN.md mục 1 điều 4).
class _UrgentBand extends StatelessWidget {
  const _UrgentBand({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border.all(color: theme.colorScheme.error, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Có thông báo khẩn cấp mới',
                  style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 8),
                FilledButton(onPressed: onOpen, child: const Text('Mở hộp thông báo')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
