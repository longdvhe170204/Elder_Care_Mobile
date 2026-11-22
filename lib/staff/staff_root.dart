import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../common/api/api_client.dart';
import '../common/auth/session_controller.dart';
import '../common/notifications/notification_api.dart';
import '../common/notifications/push_coordinator.dart';
import '../common/offline/offline_queue.dart';
import '../common/theme/app_theme.dart';
import '../common/widgets/header_app_bar.dart';
import 'activities/session_list_screen.dart';
import 'activities/trip_list_screen.dart';
import 'alerts/alerts_screen.dart';
import 'alerts/emergency_assist_screen.dart';
import 'beds/beds_screen.dart';
import 'care_tasks/care_tasks_home_screen.dart';
import 'early_unlock/early_unlock_screen.dart';
import 'handover/handover_cache.dart';
import 'handover/handover_screen.dart';
import 'incidents/incidents_screen.dart';
import 'incidents/record_incident_screen.dart';
import 'medication/family_medication_screen.dart';
import 'medication/medication_round_cache.dart';
import 'medication/medication_round_gateway.dart';
import 'medication/medication_round_repository.dart';
import 'medication/supplied_intake_screen.dart';
import 'notifications/staff_inbox_screen.dart';
import 'nutrition/family_food_screen.dart';
import 'nutrition/meal_slip_screen.dart';
import 'nutrition/serving_confirmation_screen.dart';
import 'pending_review/pending_review_screen.dart';
import 'resident_login_qr/resident_login_qr_screen.dart';
import 'residents/resident_lookup_screen.dart';
import 'shift_home/shift_home_screen.dart';
import 'shift_swaps/shift_swaps_screen.dart';
import 'shifts/assignments_screen.dart';
import 'shifts/my_shifts_screen.dart';
import 'staff_navigation.dart';
import 'sync_results/sync_results_screen.dart';

/// Gốc phần nhân viên (000 T007; 002 T046, T060; spec docs/superpowers/specs/2026-11-20-role-based-navigation-design.md
/// mục 5): vai trò của tài khoản chọn tab 2 và các mục "Thêm" ([buildStaffNavigation]), quyền `/me/permissions` chỉ thu
/// hẹp. Mọi tab có đầu màn xanh đêm (DESIGN.md 15.4) kèm nút Khẩn cấp (Q-375). Tài khoản không có vai trò dùng app nhân
/// viên (Quản lý viện, Hành chính, Kế toán) chỉ thấy màn báo dùng web. Tab Thông báo có huy hiệu số Khẩn cấp chưa xác
/// nhận; đang ở tab khác mà có Khẩn cấp thì hiện dải báo, vì khi app đang mở máy không hiện thông báo hệ thống (009 T022).
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
  StaffTab _tab = StaffTab.shift;

  /// Mục đang mở trong "Thêm"; `null` là danh sách.
  int? _more;
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

  StaffNavigation get _nav => buildStaffNavigation(
    roles: _session.user?.roles ?? const {},
    grants: _grants,
    readinessDuty: _readinessDuty,
  );

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
    } on Object {
      // Chưa xác nhận được quyền thì không mở mục theo quyền.
    }
    var readinessDuty = false;
    if (!grants.contains('ROOM_BED_CONFIGURATION:VIEW') && (_session.user?.roles.contains('AC-02') ?? false)) {
      try {
        await _session.api.getList('/bed-readiness/beds');
        readinessDuty = true;
      } on Object {
        // 403 (không có nhiệm vụ) hoặc lỗi mạng: không hiện mục Giường.
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
      selectTab(StaffTab.inbox);
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

  void selectTab(StaffTab tab) => setState(() {
    _tab = tab;
    _more = null;
    if (tab == StaffTab.inbox) _urgentBand = false;
    if (tab == StaffTab.more) unawaited(_loadUnsynced());
  });

  int get _accountId => _session.user!.accountId;

  bool get _canRunMedicationRound =>
      _grants.contains('MEDICATION_ADMINISTRATION:VIEW') || _grants.contains('MEDICATION_ADMINISTRATION:PROFESSIONAL');

  Widget _careTasks() => CareTasksHomeScreen(
    api: _session.api,
    accountId: _accountId,
    queue: widget.queue,
    medication: _canRunMedicationRound
        ? MedicationRoundRepository(
            ApiMedicationRoundGateway(_session.api),
            _medicationCache ??= MedicationRoundCache.onDevice(),
            widget.queue,
          )
        : null,
  );

  Widget _handover() => HandoverScreen(
    api: _session.api,
    cache: _session.user == null ? null : HandoverCache(_session.store, _accountId),
  );

  (String, IconData, Widget Function()) _primary(StaffPrimary primary) => switch (primary) {
    StaffPrimary.checklist => ('Checklist', LucideIcons.listChecks, _careTasks),
    StaffPrimary.floorToday => ('Tầng hôm nay', LucideIcons.clipboardCheck, _careTasks),
    StaffPrimary.residents => ('Người cao tuổi', LucideIcons.users, () => ResidentLookupScreen(api: _session.api)),
    StaffPrimary.mealSlips => ('Phiếu bữa ăn', LucideIcons.utensils, () => MealSlipScreen(api: _session.api)),
  };

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
      StaffFeature.servingConfirmation => (
        'Xác nhận phục vụ suất ăn',
        null,
        LucideIcons.utensils,
        () => ServingConfirmationScreen(api: api, queue: widget.queue, accountId: _accountId),
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
      StaffFeature.carePlanApproval => (
        'Kế hoạch chăm sóc',
        null,
        LucideIcons.clipboardCheck,
        _careTasks,
      ),
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
        LucideIcons.cloudOff,
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

  /// Hai nhóm của "Thêm" (Figma `5:603`): việc trong ca rồi công cụ.
  (List<_Item>, List<_Item>) _moreGroups(StaffNavigation nav) => (
    [
      if (nav.showHandover) ('Bàn giao ca', null, LucideIcons.arrowLeftRight, _handover),
      for (final f in nav.work) _feature(f),
    ],
    [for (final f in nav.tools) _feature(f)],
  );

  List<(StaffTab, String, IconData, Widget Function())> _tabs(StaffNavigation nav) {
    final (label, icon, body) = _primary(nav.primary!);
    final (work, tools) = _moreGroups(nav);
    final items = [...work, ...tools];
    return [
      (
        StaffTab.shift,
        'Ca của tôi',
        LucideIcons.calendarDays,
        () => ShiftHomeScreen(
          api: _session.api,
          showChecklist: nav.primary == StaffPrimary.checklist || nav.primary == StaffPrimary.floorToday,
          showHandover: nav.showHandover,
          showSchedule: _grants.contains('SHIFT_SCHEDULE:VIEW'),
          onSelectTab: selectTab,
          open: (name) => switch (name) {
            'incident' => RecordIncidentScreen(api: _session.api),
            'handover' => _handover(),
            _ => _ScheduleAndRequests(
              api: _session.api,
              showRequests: _grants.contains('SHIFT_SWAP_REQUEST:VIEW'),
            ),
          },
        ),
      ),
      (StaffTab.primary, label, icon, body),
      if (nav.showLookupTab)
        (StaffTab.lookup, 'Tra cứu', LucideIcons.users, () => ResidentLookupScreen(api: _session.api)),
      (
        StaffTab.inbox,
        'Thông báo',
        LucideIcons.bell,
        () => StaffInboxScreen(api: _session.api, push: widget.push, onUrgentCount: _setUrgent),
      ),
      (
        StaffTab.more,
        'Thêm',
        LucideIcons.ellipsis,
        () => _MoreList(
          groups: [work, tools],
          onOpen: (item) => setState(() => _more = items.indexOf(item)),
          onSignOut: () => _session.signOut(),
        ),
      ),
    ];
  }

  void _openEmergency() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: headerAppBar(context, title: 'Hỗ trợ khẩn cấp'),
          body: EmergencyAssistScreen(api: _session.api),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = _nav;
    if (nav.primary == null) return _WebOnly(onSignOut: () => _session.signOut());
    final tabs = _tabs(nav);
    final index = tabs.indexWhere((t) => t.$1 == _tab).clamp(0, tabs.length - 1);
    final (work, tools) = _moreGroups(nav);
    final items = [...work, ...tools];
    final more = _more != null && _more! < items.length ? items[_more!] : null;
    final title = more?.$1 ?? tabs[index].$2;
    final body = more?.$4 ?? tabs[index].$4;
    return Scaffold(
      appBar: headerAppBar(
        context,
        title: title,
        leading: more == null
            ? null
            : IconButton(
                tooltip: 'Quay lại',
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => setState(() => _more = null),
              ),
        actions: [_EmergencyButton(onPressed: _openEmergency)],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_urgentBand) _UrgentBand(onOpen: () => selectTab(StaffTab.inbox)),
          Expanded(
            child: KeyedSubtree(key: ValueKey((tabs[index].$1, _more)), child: body()),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => selectTab(tabs[i].$1),
        destinations: [
          for (final (tab, label, icon, _) in tabs)
            NavigationDestination(
              icon: tab == StaffTab.inbox
                  ? Badge.count(count: _urgent, isLabelVisible: _urgent > 0, child: Icon(icon))
                  : Icon(icon),
              label: label,
            ),
        ],
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
      padding: const EdgeInsets.only(right: 8),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          backgroundColor: scheme.error,
          foregroundColor: scheme.onError,
          minimumSize: const Size(48, 48),
        ),
        onPressed: onPressed,
        icon: const Icon(LucideIcons.siren),
        label: const Text('Khẩn cấp'),
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
            child: TabBarView(children: [MyShiftsScreen(api: api), ShiftSwapsScreen(api: api)]),
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
            Text('Ứng dụng di động dành cho nhân viên làm việc tại tầng, người thân và người cao tuổi.', style: text.bodyMedium),
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

/// "Thêm" (Figma `5:603`): các nhóm dòng trắng trong khối bo góc; dòng cuối Đăng xuất (máy dùng chung tại tầng).
class _MoreList extends StatelessWidget {
  const _MoreList({required this.groups, required this.onOpen, required this.onSignOut});

  final List<List<_Item>> groups;
  final ValueChanged<_Item> onOpen;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget group(List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: ListTile.divideTiles(context: context, tiles: rows).toList()),
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final items in groups)
          if (items.isNotEmpty)
            group([
              for (final item in items)
                ListTile(
                  minTileHeight: 64,
                  leading: Icon(item.$3),
                  title: Text(item.$1),
                  subtitle: item.$2 == null ? null : Text(item.$2!),
                  trailing: const Icon(LucideIcons.chevronRight),
                  onTap: () => onOpen(item),
                ),
            ]),
        group([
          ListTile(
            minTileHeight: 56,
            leading: Icon(LucideIcons.logOut, color: theme.colorScheme.error),
            title: Text('Đăng xuất', style: TextStyle(color: theme.colorScheme.error)),
            onTap: onSignOut,
          ),
        ]),
      ],
    );
  }
}
