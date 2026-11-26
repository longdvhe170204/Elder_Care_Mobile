/// Điều hướng app nhân viên theo vai trò và quyền từ `/me/permissions`.
library;

enum StaffTab {
  home('Trang chủ', 'home'),
  inbox('Thông báo', 'bell'),
  account('Tài khoản', 'user');

  const StaffTab(this.label, this.icon);

  final String label;
  final String icon;
}

/// Lối vào chính trên Trang chủ theo vai trò.
enum StaffPrimary { checklist, floorToday, residents, mealSlips }

/// Lối vào nghiệp vụ và tiện ích trên Trang chủ.
enum StaffFeature {
  medicationIntake,
  familyMedication,
  incidents,
  alerts,
  sharedMenu,
  mealSlipFloor,
  activitySessions,
  trips,
  assignments,
  beds,
  carePlanApproval,
  familyFood,
  residentLoginQr,
  syncResults,
  pendingReview,
  earlyUnlock,
}

class StaffNavigation {
  const StaffNavigation({required this.primary, required this.showHandover, required this.work, required this.tools});

  /// `null`: tài khoản không có vai trò dùng app nhân viên (Quản lý viện, Hành chính, Kế toán chỉ dùng web).
  final StaffPrimary? primary;

  /// Lối vào Bàn giao ca trên Trang chủ.
  final bool showHandover;
  final List<StaffFeature> work;
  final List<StaffFeature> tools;
}

const _floorManager = 'AC-02';
const _doctor = 'AC-03';
const _nurse = 'AC-04';
const _caregiver = 'AC-05';
const _kitchen = 'AC-07';

/// Thứ tự ưu tiên khi tài khoản có nhiều vai trò (Trưởng tầng thường là người phụ trách ca).
const _priority = [
  (_floorManager, StaffPrimary.floorToday),
  (_nurse, StaffPrimary.checklist),
  (_caregiver, StaffPrimary.checklist),
  (_doctor, StaffPrimary.residents),
  (_kitchen, StaffPrimary.mealSlips),
];

const _appRoles = {_floorManager, _doctor, _nurse, _caregiver, _kitchen};

String staffRoleLabel(Set<String> roles) {
  final role = _priority.where((entry) => roles.contains(entry.$1)).firstOrNull?.$1;
  return switch (role) {
    _floorManager => 'Trưởng tầng',
    _doctor => 'Bác sĩ',
    _nurse => 'Điều dưỡng',
    _caregiver => 'Nhân viên chăm sóc',
    _kitchen => 'Nhân viên bếp',
    _ => 'Nhân viên',
  };
}

/// Mỗi mục: vai trò được có, và điều kiện quyền (`null` là chỉ lọc theo vai trò).
final Map<StaffFeature, (Set<String>, bool Function(_Grants)?)> _features = {
  StaffFeature.medicationIntake: ({_nurse}, (g) => g.has('MEDICATION_RECEIPT:CREATE')),
  StaffFeature.familyMedication: (
    {_nurse},
    (g) => g.has('MEDICATION_ADMINISTRATION:VIEW') || g.has('MEDICATION_ADMINISTRATION:PROFESSIONAL'),
  ),
  StaffFeature.incidents: (_appRoles, (g) => g.has('INCIDENT_EMERGENCY:VIEW') || g.has('INCIDENT_EMERGENCY:UPDATE')),
  StaffFeature.alerts: (
    {_floorManager, _doctor, _nurse},
    (g) => g.has('ALERT_HANDLING:VIEW') || g.has('ALERT_HANDLING:UPDATE'),
  ),
  StaffFeature.sharedMenu: (_appRoles, (g) => g.has('DISH_MENU:VIEW')),
  StaffFeature.mealSlipFloor: ({_caregiver}, null),
  StaffFeature.activitySessions: ({_floorManager, _caregiver}, (g) => g.has('ACTIVITY_OUTING:VIEW')),
  StaffFeature.trips: ({_floorManager, _caregiver}, (g) => g.has('ACTIVITY_OUTING:VIEW')),
  StaffFeature.assignments: ({_floorManager}, (g) => g.has('SHIFT_SCHEDULE:VIEW')),
  StaffFeature.beds: ({_floorManager}, (g) => g.has('ROOM_BED_CONFIGURATION:VIEW') || g.readinessDuty),
  StaffFeature.carePlanApproval: ({_doctor}, null),
  StaffFeature.familyFood: ({_kitchen}, null),
  StaffFeature.residentLoginQr: ({_nurse}, null),
  StaffFeature.syncResults: (_appRoles, null),
  StaffFeature.pendingReview: (_appRoles, null),
  StaffFeature.earlyUnlock: ({_floorManager, _nurse}, null),
};

const _toolFeatures = {StaffFeature.syncResults, StaffFeature.pendingReview, StaffFeature.earlyUnlock};

class _Grants {
  const _Grants(this.grants, this.readinessDuty);
  final Set<String> grants;
  final bool readinessDuty;
  bool has(String grant) => grants.contains(grant);
}

/// [roles]: mã actor; [grants]: `FUNCTION:OPERATION`; [readinessDuty]: đọc được giường Chờ sẵn sàng theo nhiệm vụ.
StaffNavigation buildStaffNavigation({
  required Set<String> roles,
  required Set<String> grants,
  required bool readinessDuty,
}) {
  final appRoles = roles.intersection(_appRoles);
  final primary = _priority.where((p) => appRoles.contains(p.$1)).map((p) => p.$2).firstOrNull;
  final g = _Grants(grants, readinessDuty);
  final visible = [
    for (final MapEntry(key: feature, value: (allowed, condition)) in _features.entries)
      if (allowed.intersection(appRoles).isNotEmpty && (condition == null || condition(g))) feature,
  ];
  return StaffNavigation(
    primary: primary,
    showHandover: appRoles.intersection({_floorManager, _nurse, _caregiver}).isNotEmpty && g.has('SHIFT_HANDOVER:VIEW'),
    work: [
      for (final f in visible)
        if (!_toolFeatures.contains(f)) f,
    ],
    tools: [
      for (final f in visible)
        if (_toolFeatures.contains(f)) f,
    ],
  );
}
