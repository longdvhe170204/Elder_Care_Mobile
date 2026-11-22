import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../api/problem_message.dart';
import 'auth_layout.dart';

/// Tự đặt lại mật khẩu (002 T105; US3 #12 → #14; FR-052a, BR-M15-25; api-002 `/auth/password-reset/*`): nhập tên đăng
/// nhập, nhận mã qua tin nhắn tới số trong hồ sơ, nhập mã và mật khẩu mới. Máy chủ trả như nhau dù tài khoản có thật hay
/// không, nên màn không nói mã đã được gửi hay chưa. Đặt xong thì đóng màn, trả `true` cho màn đăng nhập.
///
/// Bố cục theo Figma "Quên mật khẩu · Mobile" (94:259) trên khung chung [AuthLayout]: tiêu đề, một ô, nút "Xác nhận" 176,
/// liên kết "Quay lại trang đăng nhập" căn phải. Ô là tên đăng nhập (mẫu ghi "Số điện thoại") vì máy chủ nhận tên đăng
/// nhập (Q-399; anh chốt cho màn đăng nhập 2026-11-21). Bước nhập mã chưa có mẫu, dùng cùng khung và tỷ lệ.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.api});

  static const usernameKey = ValueKey('reset.username');
  static const codeKey = ValueKey('reset.code');
  static const newPasswordKey = ValueKey('reset.newPassword');
  static const againKey = ValueKey('reset.again');

  final ApiClient api;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _username = TextEditingController();
  final _code = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _codeStep = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _code.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    if (_username.text.trim().isEmpty) {
      setState(() => _error = 'Nhập tên đăng nhập');
      return;
    }
    await _run(() async {
      await widget.api.post('/auth/password-reset/request', {'username': _username.text.trim()});
      if (mounted) setState(() => _codeStep = true);
    });
  }

  Future<void> _confirm() async {
    if (_code.text.trim().isEmpty || _next.text.isEmpty) {
      setState(() => _error = 'Nhập mã trong tin nhắn và mật khẩu mới');
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _error = 'Hai lần nhập mật khẩu mới chưa giống nhau');
      return;
    }
    await _run(() async {
      await widget.api.post('/auth/password-reset/confirm', {
        'username': _username.text.trim(),
        'code': _code.text.trim(),
        'newPassword': _next.text,
      });
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Widget _field(
    String label,
    Key key,
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
    TextInputType? keyboard,
    List<String>? autofill,
    TextInputAction? action,
  }) => AuthField(
    label: label,
    child: TextField(
      key: key,
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: false,
      enableSuggestions: !obscure,
      textInputAction: action,
      autofillHints: autofill,
      style: authInputStyle,
      decoration: authInputDecoration(context, hint: hint, icon: icon),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AuthLayout(
      children: [
        if (!_codeStep) ...[
          const AuthTitle('Quên mật khẩu'),
          const SizedBox(height: 24),
          _field(
            'Tên đăng nhập',
            ForgotPasswordScreen.usernameKey,
            _username,
            'Nhập tên đăng nhập của bạn',
            LucideIcons.userRound,
            autofill: const [AutofillHints.username],
            action: TextInputAction.done,
          ),
        ] else ...[
          const AuthTitle('Nhập mã và mật khẩu mới'),
          const SizedBox(height: 12),
          Text(
            'Nếu tài khoản có số điện thoại đã đăng ký, mã đã được gửi tới số đó. Không nhận được mã thì liên hệ viện '
            'để được cấp lại mật khẩu.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(
                  'Mã trong tin nhắn',
                  ForgotPasswordScreen.codeKey,
                  _code,
                  'Nhập mã gồm các chữ số',
                  LucideIcons.messageSquare,
                  keyboard: TextInputType.number,
                  autofill: const [AutofillHints.oneTimeCode],
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                _field(
                  'Mật khẩu mới',
                  ForgotPasswordScreen.newPasswordKey,
                  _next,
                  'Nhập mật khẩu mới',
                  LucideIcons.lock,
                  obscure: true,
                  autofill: const [AutofillHints.newPassword],
                  action: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                _field(
                  'Nhập lại mật khẩu mới',
                  ForgotPasswordScreen.againKey,
                  _again,
                  'Nhập lại mật khẩu mới',
                  LucideIcons.lock,
                  obscure: true,
                  autofill: const [AutofillHints.newPassword],
                  action: TextInputAction.done,
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 12), AuthMessage(_error!, error: true)],
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: _codeStep ? 'Đặt mật khẩu mới' : 'Xác nhận',
          width: _codeStep ? 216 : 176,
          busy: _busy,
          busyLabel: 'Đang gửi',
          onPressed: _codeStep ? _confirm : _request,
        ),
        const SizedBox(height: 4),
        AuthLink(label: 'Quay lại trang đăng nhập', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
