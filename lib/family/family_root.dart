import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../common/auth/session_controller.dart';
import '../common/notifications/push_coordinator.dart';
import '../common/widgets/header_app_bar.dart';
import 'notifications/family_inbox_screen.dart';
import 'portal/family_selection.dart';
import 'portal/family_tabs.dart';

/// Gốc phần người thân (000 T007; 002 T047; Q-346, Q-305; spec docs/superpowers/specs/2026-11-20-role-based-navigation-
/// design.md mục 6): thanh dưới cố định 5 tab Hôm nay · Lịch thăm · Chi phí · Thông báo · Thêm cho mọi người thân, kể cả
/// khi thiếu quyền (tab thiếu quyền nói rõ lý do). Người thân của nhiều người cao tuổi chọn người ở đầu màn; mọi tab tính
/// theo người đang chọn.
class FamilyRoot extends StatefulWidget {
  const FamilyRoot({super.key, required this.session, this.push});

  final SessionController session;
  final PushCoordinator? push;

  @override
  State<FamilyRoot> createState() => _FamilyRootState();
}

class _FamilyRootState extends State<FamilyRoot> {
  int _index = 0;
  late final FamilySelection _selection = FamilySelection(widget.session.api)..addListener(_changed);

  static const _inboxIndex = 3;

  @override
  void initState() {
    super.initState();
    _selection.load();
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  static const _tabs = [
    ('Hôm nay', LucideIcons.heartHandshake),
    ('Lịch thăm', LucideIcons.calendarDays),
    ('Chi phí', LucideIcons.wallet),
    ('Thông báo', LucideIcons.bell),
    ('Thêm', LucideIcons.ellipsis),
  ];

  Widget _body(BuildContext context) {
    if (_index == _inboxIndex) return FamilyInboxScreen(api: widget.session.api, push: widget.push);
    final text = Theme.of(context).textTheme;
    final residents = _selection.residents;
    if (_selection.error != null) {
      return Padding(padding: const EdgeInsets.all(16), child: Text(_selection.error!, style: text.bodyMedium));
    }
    if (residents == null) return const Center(child: CircularProgressIndicator());
    final current = _selection.current;
    if (current == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Chưa có người cao tuổi nào có quan hệ Hiệu lực với tài khoản này.', style: text.bodyMedium),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (residents.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                for (final r in residents)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(r.fullName),
                      selected: r.id == current.id,
                      onSelected: (_) => _selection.select(r.id),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: KeyedSubtree(key: ValueKey((_index, current.id)), child: _tab(current)),
        ),
      ],
    );
  }

  Widget _tab(FamilyResident resident) {
    final api = widget.session.api;
    return switch (_index) {
      0 => FamilyTodayTab(api: api, resident: resident),
      1 => FamilyVisitsTab(api: api, resident: resident),
      2 => FamilyCostsTab(api: api, resident: resident),
      _ => FamilyMoreTab(api: api, resident: resident, onSignOut: () => widget.session.signOut()),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: headerAppBar(context, title: _tabs[_index].$1),
      body: _body(context),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final (label, icon) in _tabs) NavigationDestination(icon: Icon(icon), label: label),
        ],
      ),
    );
  }
}
