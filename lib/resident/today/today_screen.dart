import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/auth/secure_store.dart';
import '../../common/format/date_time.dart';
import '../../common/notifications/notification_api.dart';
import '../../common/notifications/push_coordinator.dart';
import '../../common/theme/app_theme.dart';
import '../channel/channel_screens.dart';
import '../feedback/resident_feedback_screen.dart';
import '../notifications/resident_notifications_screen.dart';
import '../sos/sos_button.dart';

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

/// Ngày dưới tiêu đề Hôm nay, theo giờ Việt Nam (DESIGN.md 15.6).
String _todayDate(DateTime now) {
  final vn = now.toUtc().add(const Duration(hours: 7));
  return '${_weekdays[vn.weekday - 1]}, ${formatDateTime(now).split(' ').first}';
}

/// Màn đầu "Hôm nay" của người cao tuổi (DESIGN.md 15.6; 012 T070, T071): thẻ lớn một cột, mỗi thẻ hiện việc gần nhất
/// và mở màn tương ứng (Lịch hôm nay, Bữa ăn, Hoạt động, Người đến thăm, Đồ của tôi, Góp ý với viện, Thông báo của 009
/// T042); nút "Gọi người giúp" cố định ở đáy. Không có thẻ sức khỏe, thuốc, chi phí (FR-084).
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.api, this.push, this.now, this.store});

  final ApiClient api;

  /// Kho trên máy: token thiết bị cho nút SOS, số của viện đã lưu, đã xem giới thiệu (012 FR-085).
  final SecureStore? store;

  /// Nhận đẩy: có thông báo thì cập nhật số, bấm thông báo thì mở thông báo đó (009 T042).
  final PushCoordinator? push;
  final DateTime? now;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  int? _unread;
  late final SecureStore _store = widget.store ?? MemoryStore();
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _activities;
  Map<String, dynamic>? _visits;
  Map<String, dynamic>? _belongings;
  Map<String, dynamic>? _menu;

  @override
  void initState() {
    super.initState();
    _loadUnread();
    _loadChannel();
    widget.push?.addListener(_onPush);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPending());
  }

  @override
  void dispose() {
    widget.push?.removeListener(_onPush);
    super.dispose();
  }

  void _onPush() {
    _loadUnread();
    _openPending();
  }

  Future<void> _openPending() async {
    final id = widget.push?.takeOpened();
    if (id == null || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ResidentNotificationScreen(notifications: NotificationApi(widget.api), id: id),
      ),
    );
    await _loadUnread();
  }

  /// Không lấy được số thì thẻ vẫn mở được, chỉ không có dòng số (mất mạng).
  Future<void> _loadUnread() async {
    try {
      final page = await NotificationApi(widget.api).page();
      if (mounted) setState(() => _unread = page.unreadCount);
    } on Exception {
      if (mounted) setState(() => _unread = null);
    }
  }

  /// Việc gần nhất của từng thẻ; phần nào không tải được thì thẻ vẫn mở được, chỉ không có dòng việc.
  Future<void> _loadChannel() async {
    Future<Map<String, dynamic>?> get(String part) async {
      try {
        return await widget.api.get('/resident-channel/$part');
      } on Exception {
        return null;
      }
    }

    final parts = await Future.wait([get('today'), get('activities'), get('visits'), get('belongings'), get('menu')]);
    if (!mounted) return;
    setState(() {
      _today = parts[0];
      _activities = parts[1];
      _visits = parts[2];
      _belongings = parts[3];
      _menu = parts[4];
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));
    await _loadChannel();
  }

  String? get _scheduleLine {
    final today = _today;
    if (today == null) return null;
    final lines = todayLines(today);
    return lines.isEmpty ? 'Hôm nay chưa có lịch' : lines.first;
  }

  String? get _nextLine {
    final today = _today;
    return today == null ? null : nextTodayLine(today, widget.now ?? DateTime.now());
  }

  String? get _activityLine {
    final items = _activities?['items'] as List<dynamic>?;
    if (_activities == null) return null;
    if (_activities!['available'] != true) return 'Chưa có lịch hoạt động';
    if (items == null || items.isEmpty) return 'Chưa có buổi sắp tới';
    final a = ChannelActivity(items.first as Map<String, dynamic>);
    return '${formatTime(a.startAt)} ${a.name}';
  }

  String? get _visitLine {
    final items = _visits?['items'] as List<dynamic>?;
    if (items == null) return null;
    if (items.isEmpty) return 'Chưa có lượt thăm sắp tới';
    final v = ChannelVisit(items.first as Map<String, dynamic>);
    final today = _today?['date'] as String?;
    final when = v.date == today ? v.startTime : '${formatDate(v.date)} ${v.startTime}';
    return '$when ${v.visitors.isEmpty ? 'Người thân' : v.visitors.first} đến thăm';
  }

  String? get _belongingLine {
    if (_belongings == null) return null;
    if (_belongings!['available'] != true) return 'Chưa có thông tin đồ gửi';
    final n = (_belongings!['items'] as List<dynamic>).length;
    return n == 0 ? 'Viện đang không giữ đồ nào' : '$n món đang giữ';
  }

  String? get _menuLine {
    if (_menu == null) return null;
    final items = _menu!['items'] as List<dynamic>;
    return _menu!['available'] != true || items.isEmpty ? 'Chưa có thực đơn' : null;
  }

  Widget _card(IconData icon, String title, String? line, VoidCallback onTap) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: colors.outline),
        ),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 82),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: text.titleMedium),
                      if (line != null) ...[const SizedBox(height: 4), Text(line, style: text.bodyLarge)],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(LucideIcons.chevronRight, color: colors.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Khối "Sắp tới" đầu màn (spec 2026-11-20 mục 7): việc gần giờ hiện tại nhất, chữ lớn, không bấm.
  Widget _upcoming(String line) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('sap-toi'),
      padding: const EdgeInsets.only(bottom: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sắp tới', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(line, style: theme.textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => ResidentNotificationsScreen(api: widget.api)));
    await _loadUnread();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final tones = theme.extension<Tones>()!;
    final unread = _unread;
    final api = widget.api;
    final screen = Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColoredBox(
              color: tones.header,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text('Hôm nay', style: text.headlineMedium?.copyWith(color: tones.headerInkStrong)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _todayDate(widget.now ?? DateTime.now()),
                        style: text.bodySmall?.copyWith(color: tones.headerInk),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                bottom: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_nextLine case final next?) _upcoming(next),
                      _card(
                        LucideIcons.calendarDays,
                        'Lịch hôm nay',
                        _scheduleLine,
                        () => _open(ScheduleScreen(api: api)),
                      ),
                      _card(LucideIcons.utensils, 'Bữa ăn', _menuLine, () => _open(MenuScreen(api: api))),
                      _card(LucideIcons.activity, 'Hoạt động', _activityLine, () => _open(ActivitiesScreen(api: api))),
                      _card(LucideIcons.usersRound, 'Người đến thăm', _visitLine, () => _open(VisitsScreen(api: api))),
                      _card(
                        LucideIcons.shoppingBag,
                        'Đồ của tôi',
                        _belongingLine,
                        () => _open(BelongingsScreen(api: api)),
                      ),
                      _card(
                        LucideIcons.messageCircle,
                        'Góp ý với viện',
                        null,
                        () => _open(ResidentFeedbackScreen(api: api)),
                      ),
                      _card(
                        LucideIcons.bell,
                        'Thông báo',
                        unread == null ? null : (unread > 0 ? '$unread thông báo chưa xem' : 'Không có thông báo mới'),
                        _openNotifications,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SosButton(api: api, store: _store),
    );
    // Giới thiệu lần đầu cần kho trên máy; không có kho (màn dựng riêng trong test cũ) thì không chặn
    return widget.store == null ? screen : SosIntroGate(store: widget.store!, child: screen);
  }
}
