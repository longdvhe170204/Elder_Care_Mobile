import 'package:flutter/material.dart';

import '../../common/auth/change_password_screen.dart';
import '../../common/auth/session_controller.dart';
import '../../common/theme/app_theme.dart';
import '../../common/widgets/header_app_bar.dart';
import '../staff_dashboard_style.dart';

class StaffIdentity extends StatelessWidget {
  const StaffIdentity({super.key, required this.name, required this.role, this.inHeader = false});

  final String name;
  final String role;
  final bool inHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    final words = name.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
    final initials = [
      if (words.isNotEmpty) words.first.characters.first,
      if (words.length > 1) words.last.characters.first,
    ].join().toUpperCase();
    final size = inHeader ? 44.0 : 56.0;
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(inHeader ? 13 : 16),
            ),
            child: Text(
              initials,
              style: (inHeader ? theme.textTheme.titleSmall : theme.textTheme.titleMedium)?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SizedBox(width: inHeader ? 10 : 15),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: inHeader ? 1 : null,
                overflow: inHeader ? TextOverflow.ellipsis : null,
                style: (inHeader ? theme.textTheme.titleMedium : theme.textTheme.titleLarge)?.copyWith(
                  color: inHeader ? tones.headerInkStrong : scheme.onSurface,
                  fontSize: inHeader ? null : 20,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                role,
                maxLines: inHeader ? 1 : null,
                overflow: inHeader ? TextOverflow.ellipsis : null,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: inHeader ? tones.headerInk : scheme.onSurfaceVariant,
                  fontSize: inHeader ? null : 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StaffAccountScreen extends StatefulWidget {
  const StaffAccountScreen({super.key, required this.session, required this.name, required this.role});

  final SessionController session;
  final String name;
  final String role;

  @override
  State<StaffAccountScreen> createState() => _StaffAccountScreenState();
}

class _StaffAccountScreenState extends State<StaffAccountScreen> {
  bool _signingOut = false;

  Future<void> _openPassword() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ChangePasswordScreen(session: widget.session, requiredAtLogin: false)),
    );
    if (mounted && changed == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đổi mật khẩu.')));
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    try {
      await widget.session.signOut();
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            staffDashboardCard(
              context,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: StaffIdentity(name: widget.name, role: widget.role),
              ),
            ),
            const SizedBox(height: 21),
            staffDashboardCard(
              context,
              Column(
                children: [
                  _AccountRow(
                    icon: 'people',
                    title: 'Thông tin cá nhân',
                    iconColor: scheme.secondary,
                    onTap: _signingOut
                        ? null
                        : () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  _PersonalInfo(session: widget.session, name: widget.name, role: widget.role),
                            ),
                          ),
                  ),
                  const Divider(height: 1, indent: 13, endIndent: 13),
                  _AccountRow(
                    icon: 'lock',
                    title: 'Đổi mật khẩu',
                    iconColor: scheme.onSurfaceVariant,
                    onTap: _signingOut ? null : _openPassword,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Center(
              child: FilledButton.icon(
                onPressed: _signingOut ? null : _signOut,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(202, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                  textStyle: theme.textTheme.titleMedium,
                ),
                icon: StaffDashboardIcon('logout', color: scheme.onError),
                label: Text(_signingOut ? 'Đang đăng xuất' : 'Đăng xuất'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.icon, required this.title, required this.iconColor, required this.onTap});

  final String icon;
  final String title;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      minTileHeight: 60,
      minVerticalPadding: 8,
      contentPadding: const EdgeInsets.fromLTRB(13, 0, 17, 0),
      horizontalTitleGap: 12,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: StaffDashboardIcon(icon, color: iconColor),
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      trailing: StaffDashboardIcon('chevron', color: scheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}

class _PersonalInfo extends StatefulWidget {
  const _PersonalInfo({required this.session, required this.name, required this.role});

  final SessionController session;
  final String name;
  final String role;

  @override
  State<_PersonalInfo> createState() => _PersonalInfoState();
}

class _PersonalInfoState extends State<_PersonalInfo> {
  late final Future<Map<String, dynamic>?> _profile = widget.session.api.get('/me');

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: headerAppBar(context, title: 'Thông tin cá nhân'),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: FutureBuilder(
          future: _profile,
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final user = widget.session.user;
            final fields = {
              'Họ và tên': profile?['fullName'] as String? ?? widget.name,
              'Vai trò': widget.role,
              'Tên đăng nhập': widget.session.username,
              'Số điện thoại': profile?['phoneNumber'] as String? ?? user?.phoneNumber,
              'Email': profile?['email'] as String? ?? user?.email,
            };
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
                if (snapshot.hasError)
                  const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Chưa tải được thông tin mới nhất.')),
                staffDashboardCard(
                  context,
                  Column(
                    children: [
                      for (final field in fields.entries)
                        ListTile(
                          title: Text(field.key),
                          subtitle: Text(field.value?.trim().isNotEmpty == true ? field.value! : 'Chưa có'),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
