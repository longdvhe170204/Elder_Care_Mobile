import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/care/daily_care_schedule_screen.dart';
import '../../common/format/date_time.dart';
import '../../common/widgets/status_pill.dart';
import '../admissions/change_request_screen.dart';
import '../admissions/contract_screen.dart';
import '../balance/family_balance_screen.dart';
import '../belongings/family_belongings_screen.dart';
import '../charges/family_costs_screen.dart';
import '../charges/purchase_consent_screen.dart';
import '../feedback/feedback_screen.dart';
import '../profile/family_profile_screen.dart';
import '../right_change_requests/right_change_requests_screen.dart';
import '../visits/visit_registration_screen.dart';
import 'family_activities_screen.dart';
import 'family_selection.dart';
import 'portal_screen.dart' show HealthScreen, familyHealthLock, familyStatusLabels;

/// Câu thiếu quyền của tab cố định (spec 2026-11-20 mục 6): nói rõ quyền nào và cách được cấp.
Widget noRightNotice(BuildContext context, String what, String residentName) => Padding(
  padding: const EdgeInsets.all(16),
  child: Text(
    'Bạn chưa được cấp quyền $what của $residentName. Liên hệ người đại diện hoặc viện để được cấp.',
    style: Theme.of(context).textTheme.bodyLarge,
  ),
);

void _push(BuildContext context, String title, Widget body, {bool scaffold = true}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => scaffold
          ? Scaffold(
              appBar: AppBar(title: Text(title)),
              body: body,
            )
          : body,
    ),
  );
}

/// Khối dòng trắng bo góc như Figma "Danh sách".
class _Group extends StatelessWidget {
  const _Group(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: ListTile.divideTiles(context: context, tiles: rows).toList(),
    ),
  );
}

ListTile _row(IconData icon, String title, VoidCallback onTap, {String? subtitle}) => ListTile(
  minTileHeight: 64,
  leading: Icon(icon),
  title: Text(title),
  subtitle: subtitle == null ? null : Text(subtitle),
  trailing: const Icon(LucideIcons.chevronRight),
  onTap: onTap,
);

/// Tải thông tin chung của người cao tuổi (`GET /family-portal/residents/{id}/general`, 012 FR-046 (1)).
class _General extends StatefulWidget {
  const _General({required this.api, required this.resident, required this.builder});

  final ApiClient api;
  final FamilyResident resident;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;

  @override
  State<_General> createState() => _GeneralState();
}

class _GeneralState extends State<_General> {
  Map<String, dynamic>? _general;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final general = await widget.api.get('/family-portal/residents/${widget.resident.id}/general');
      if (mounted) setState(() => _general = general);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!));
    final general = _general;
    if (general == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(onRefresh: _load, child: widget.builder(context, general));
  }
}

/// Tab "Hôm nay": tình trạng, lịch sinh hoạt, bữa ăn (thực đơn chung 7 ngày, 012 FR-046), sự cố phần chung, sức khỏe
/// theo quyền có tác dụng (BR-M01-08).
class FamilyTodayTab extends StatelessWidget {
  const FamilyTodayTab({super.key, required this.api, required this.resident});

  final ApiClient api;
  final FamilyResident resident;

  @override
  Widget build(BuildContext context) => _General(
    api: api,
    resident: resident,
    builder: (context, g) {
      final theme = Theme.of(context);
      final status = g['status'];
      final (statusLabel, statusTone) = familyStatusLabels[status] ?? ('$status', StatusTone.neutral);
      final unavailable = (g['unavailable'] as List? ?? const []).cast<String>();
      final menu = (g['menu'] as List? ?? const []).cast<Map<String, dynamic>>();
      final days = <String, List<Map<String, dynamic>>>{};
      for (final m in menu) {
        (days[m['date'] as String] ??= []).add(m);
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(resident.fullName, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Row(
            children: [
              StatusPill(label: statusLabel, tone: statusTone),
              const SizedBox(width: 8),
              if (g['location'] != null) Expanded(child: Text('${g['location']}', style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: 16),
          _Group([
            // Q-416, 012 FR-076: mọi người thân có quan hệ Hiệu lực; giá trị đo chỉ khi có quyền xem sức khỏe
            _row(
              LucideIcons.calendarClock,
              'Lịch chăm sóc hằng ngày',
              () => _push(
                context,
                'Lịch chăm sóc hằng ngày',
                DailyCareScheduleScreen(
                  api: api,
                  path: '/family-portal/residents/${resident.id}/daily-care-schedule',
                  residentName: resident.fullName,
                ),
              ),
              subtitle: 'Mốc trong ngày, công việc chăm sóc và trạng thái',
            ),
            _row(
              LucideIcons.calendarDays,
              'Lịch sinh hoạt và hoạt động',
              () => _push(
                context,
                'Hoạt động',
                FamilyActivitiesScreen(api: api, residentId: resident.id, representative: resident.representative),
                scaffold: false,
              ),
            ),
          ]),
          Text('Bữa ăn', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (unavailable.contains('menu') || days.isEmpty)
            Text('Chưa có thực đơn.', style: theme.textTheme.bodyMedium)
          else
            _Group([
              for (final MapEntry(key: date, value: meals) in days.entries)
                ListTile(
                  title: Text(formatDate(date)),
                  subtitle: Text([for (final m in meals) '${m['mealName']}: ${m['dishName']}'].join('\n')),
                ),
            ]),
          const SizedBox(height: 4),
          Text('Sự cố, phần chung', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            unavailable.contains('incidents')
                ? 'Chưa có dữ liệu sự cố.'
                : '${(g['incidents'] as List? ?? const []).length} sự cố trong 30 ngày qua',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text('Sức khỏe', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (resident.can('VIEW_HEALTH'))
            OutlinedButton(
              onPressed: () => _push(
                context,
                'Sức khỏe',
                HealthScreen(api: api, residentId: resident.id, residentName: resident.fullName),
                scaffold: false,
              ),
              child: const Text('Xem sức khỏe'),
            )
          else
            Text(familyHealthLock, style: theme.textTheme.bodyMedium),
        ],
      );
    },
  );
}

/// Tab "Lịch thăm": lượt thăm sắp tới và đăng ký thăm khi có quyền đăng ký thăm (BR-M10-02).
class FamilyVisitsTab extends StatelessWidget {
  const FamilyVisitsTab({super.key, required this.api, required this.resident});

  final ApiClient api;
  final FamilyResident resident;

  @override
  Widget build(BuildContext context) {
    if (!resident.can('REGISTER_VISITS')) return noRightNotice(context, 'đăng ký thăm', resident.fullName);
    return _General(
      api: api,
      resident: resident,
      builder: (context, g) {
        final theme = Theme.of(context);
        final visits = (g['visits'] as List? ?? const []).cast<Map<String, dynamic>>();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FilledButton(
              onPressed: () => _push(
                context,
                'Đăng ký thăm',
                VisitRegistrationScreen(api: api, residentId: resident.id, residentName: resident.fullName),
              ),
              child: const Text('Đăng ký thăm'),
            ),
            const SizedBox(height: 16),
            Text('Lượt thăm của bạn', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (visits.isEmpty)
              Text('Chưa có lượt thăm sắp tới.', style: theme.textTheme.bodyMedium)
            else
              _Group([
                for (final v in visits)
                  ListTile(title: Text('${formatDate(v['date'] as String)}, ${v['startTime']}–${v['endTime']}')),
              ]),
          ],
        );
      },
    );
  }
}

/// Tab "Chi phí": số dư, bảng chi phí khi có quyền xem chi phí (BR-M10-10); đề nghị mua hộ cho người đại diện.
class FamilyCostsTab extends StatelessWidget {
  const FamilyCostsTab({super.key, required this.api, required this.resident});

  final ApiClient api;
  final FamilyResident resident;

  @override
  Widget build(BuildContext context) {
    final costs = resident.can('VIEW_COSTS');
    return ListView(
      padding: costs ? const EdgeInsets.all(16) : EdgeInsets.zero,
      children: [
        if (costs)
          _Group([
            _row(
              LucideIcons.wallet,
              'Số dư',
              () => _push(
                context,
                'Số dư',
                FamilyBalanceScreen(api: api, residentId: resident.id, residentName: resident.fullName),
              ),
              subtitle: 'Số dư, lịch sử giao dịch, chứng từ, thông tin nộp tiền',
            ),
            _row(
              LucideIcons.clipboardList,
              'Bảng chi phí',
              () =>
                  _push(context, 'Bảng chi phí', FamilyCostsScreen(api: api, residentId: resident.id), scaffold: false),
            ),
          ])
        else
          noRightNotice(context, 'xem chi phí', resident.fullName),
        if (resident.representative)
          Padding(
            padding: costs ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
            child: _Group([
              _row(
                LucideIcons.shoppingCart,
                'Đề nghị mua hộ',
                () => _push(context, 'Đề nghị mua hộ', PurchaseConsentScreen(api: api, residentId: resident.id)),
                subtitle: 'Đồng ý hoặc từ chối đề nghị vượt hạn mức',
              ),
            ]),
          ),
      ],
    );
  }
}

/// Tab "Thêm": việc của người đại diện (BR-M10-01, BR-M10-07), đồ gửi (BR-M12-09), phản hồi, hồ sơ, đăng xuất.
class FamilyMoreTab extends StatelessWidget {
  const FamilyMoreTab({super.key, required this.api, required this.resident, required this.onSignOut});

  final ApiClient api;
  final FamilyResident resident;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (resident.representative)
          _Group([
            _row(
              LucideIcons.clipboardCheck,
              'Yêu cầu chờ xác nhận',
              () => _push(context, 'Yêu cầu chờ xác nhận', RightChangeRequestsScreen(api: api)),
            ),
            _row(
              LucideIcons.arrowLeftRight,
              'Yêu cầu thay đổi dịch vụ',
              () => _push(context, 'Yêu cầu thay đổi dịch vụ', ChangeRequestScreen(api: api)),
            ),
            _row(LucideIcons.fileText, 'Hợp đồng', () => _push(context, 'Hợp đồng', ContractScreen(api: api))),
          ]),
        _Group([
          if (resident.belongings)
            _row(
              LucideIcons.package,
              'Đồ gửi',
              () => _push(context, 'Đồ gửi', FamilyBelongingsScreen(api: api, residentId: resident.id)),
            ),
          _row(LucideIcons.messageSquare, 'Phản hồi', () => _push(context, 'Phản hồi', FeedbackScreen(api: api))),
          _row(LucideIcons.userRound, 'Hồ sơ', () => _push(context, 'Hồ sơ', FamilyProfileScreen(api: api))),
        ]),
        _Group([
          ListTile(
            minTileHeight: 56,
            leading: Icon(LucideIcons.logOut, color: error),
            title: Text('Đăng xuất', style: TextStyle(color: error)),
            onTap: onSignOut,
          ),
        ]),
      ],
    );
  }
}
