import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../api/problem_message.dart';
import 'auth_layout.dart';
import 'forgot_password_screen.dart';

export 'auth_layout.dart' show appVersion;

/// Biểu mẫu chung trên [AuthLayout] cho nhân viên, người thân và người cao tuổi. App truyền màn quét QR và nút SOS
/// cho máy đã gắn người cao tuổi. Có [api] và kênh tin nhắn đã cấu hình thì hiện "Quên mật khẩu?" (002 FR-052a).
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.onSubmit,
    required this.residentLogin,
    this.notice,
    this.api,
    this.errorMessage = backendMessage,
    this.bottomNavigationBar,
  });

  static const usernameKey = ValueKey('login.username');
  static const passwordKey = ValueKey('login.password');

  final Future<void> Function(String username, String password) onSubmit;
  final WidgetBuilder residentLogin;
  final String Function(Object error) errorMessage;
  final Widget? bottomNavigationBar;

  /// Câu báo, ví dụ sau khi phiên bị kết thúc.
  final String? notice;

  /// Client hỏi `/auth/password-reset/availability` và dùng cho màn quên mật khẩu; `null` thì ẩn chức năng.
  final ApiClient? api;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  bool _resetAvailable = false;
  bool _resetDone = false;

  @override
  void initState() {
    super.initState();
    _checkReset();
  }

  // Không gọi được máy chủ thì ẩn chức năng (FR-052a: chưa cấu hình kênh tin nhắn thì không hiện)
  Future<void> _checkReset() async {
    final api = widget.api;
    if (api == null) return;
    try {
      final body = await api.get('/auth/password-reset/availability');
      if (mounted) setState(() => _resetAvailable = body?['available'] == true);
    } on Exception {
      return;
    }
  }

  Future<void> _forgot() async {
    final done = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => ForgotPasswordScreen(api: widget.api!)));
    if (mounted && done == true) setState(() => _resetDone = true);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Đăng nhập xong `ElderCareApp` dựng lại màn theo trạng thái phiên
      await widget.onSubmit(_username.text.trim(), _password.text);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = widget.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      bottomNavigationBar: widget.bottomNavigationBar,
      children: [
        if (widget.notice != null) ...[AuthMessage(widget.notice!), const SizedBox(height: 16)],
        if (_resetDone) ...[
          const AuthMessage('Đã đặt mật khẩu mới. Đăng nhập bằng mật khẩu mới.'),
          const SizedBox(height: 16),
        ],
        // Cho trình quản lý mật khẩu điền (DESIGN.md 15.5; WCAG 3.3.8)
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                label: 'Tên đăng nhập',
                child: TextField(
                  key: LoginScreen.usernameKey,
                  controller: _username,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  style: authInputStyle,
                  decoration: authInputDecoration(context, hint: 'Nhập tên đăng nhập', icon: LucideIcons.userRound),
                ),
              ),
              const SizedBox(height: 16),
              AuthField(
                label: 'Mật khẩu',
                child: TextField(
                  key: LoginScreen.passwordKey,
                  controller: _password,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                  style: authInputStyle,
                  decoration: authInputDecoration(
                    context,
                    hint: 'Nhập mật khẩu',
                    icon: LucideIcons.lock,
                    suffix: IconButton(
                      tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                      icon: Icon(_showPassword ? LucideIcons.eyeOff : LucideIcons.eye, size: 20),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_resetAvailable) AuthLink(label: 'Quên mật khẩu?', onPressed: _forgot) else const SizedBox(height: 48),
        if (_error != null) ...[AuthMessage(_error!, error: true), const SizedBox(height: 12)],
        const SizedBox(height: 10),
        AuthPrimaryButton(label: 'Đăng nhập', width: 244, busy: _busy, busyLabel: 'Đang đăng nhập', onPressed: _submit),
        const SizedBox(height: 8),
        AuthLink(
          label: 'Quét mã QR cho người cao tuổi',
          alignment: Alignment.center,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: widget.residentLogin)),
        ),
      ],
    );
  }
}
