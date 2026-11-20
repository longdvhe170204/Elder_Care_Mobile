import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../api/problem_message.dart';
import '../theme/app_theme.dart';
import 'forgot_password_screen.dart';

/// Phiên bản hiển thị ở chân màn; giữ khớp `version` trong pubspec.yaml.
const appVersion = '1.0.0';

/// Màn đầu khi chưa đăng nhập (000 T006; 002 T046, T047; sửa 2026-10-28, chủ dự án duyệt; bố cục theo mẫu anh gửi
/// 2026-11-21): logo, một form tên đăng nhập, mật khẩu cho nhân viên và người thân (kênh `MOBILE_APP`, backend gán kênh
/// phiên theo loại tài khoản nên thời gian tự đăng xuất theo kênh giữ nguyên, FR-013a), kèm câu máy dùng chung
/// (FR-014a); nút phụ mở màn quét mã của người cao tuổi (FR-069). Máy đã gắn với tài khoản người cao tuổi không qua màn
/// này. Màn quét mã do `ElderCareApp` truyền vào để `common/` không phụ thuộc `resident/` (mobile/README.md luật 1). Lỗi
/// theo câu backend trả (không lộ tài khoản có hay không, FR-014). Có `api` và kênh tin nhắn đã cấu hình thì có
/// "Quên mật khẩu?" (002 T105, FR-052a, Q-06). Ô đầu là tên đăng nhập vì backend đăng nhập bằng tên đăng nhập (anh chốt
/// 2026-11-21, mẫu ghi "Số điện thoại").
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSubmit, required this.residentLogin, this.notice, this.api});

  static const usernameKey = ValueKey('login.username');
  static const passwordKey = ValueKey('login.password');

  final Future<void> Function(String username, String password) onSubmit;
  final WidgetBuilder residentLogin;

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
      if (mounted) setState(() => _error = backendMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final colors = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 420, minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 56),
                        Center(
                          child: ExcludeSemantics(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: tones.header,
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                              ),
                              child: Icon(LucideIcons.leaf, color: tones.headerInkStrong, size: 28),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            'Elder Care',
                            textAlign: TextAlign.center,
                            style: text.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (widget.notice != null) _Message(widget.notice!, tone: _Tone.info),
                        if (_resetDone) const _Message('Đã đặt mật khẩu mới. Đăng nhập bằng mật khẩu mới.'),
                        // Cho trình quản lý mật khẩu điền (DESIGN.md 15.5; WCAG 3.3.8)
                        AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Field(
                                label: 'Tên đăng nhập',
                                child: TextField(
                                  key: LoginScreen.usernameKey,
                                  controller: _username,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.username],
                                  decoration: const InputDecoration(
                                    hintText: 'Nhập tên đăng nhập',
                                    prefixIcon: Icon(LucideIcons.userRound),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _Field(
                                label: 'Mật khẩu',
                                child: TextField(
                                  key: LoginScreen.passwordKey,
                                  controller: _password,
                                  obscureText: !_showPassword,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    hintText: 'Nhập mật khẩu',
                                    prefixIcon: const Icon(LucideIcons.lock),
                                    suffixIcon: IconButton(
                                      tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                                      icon: Icon(_showPassword ? LucideIcons.eyeOff : LucideIcons.eye),
                                      onPressed: () => setState(() => _showPassword = !_showPassword),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_resetAvailable)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(onPressed: _forgot, child: const Text('Quên mật khẩu?')),
                          )
                        else
                          const SizedBox(height: 8),
                        if (_error != null) ...[const SizedBox(height: 8), _Message(_error!, tone: _Tone.error)],
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                          ),
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    semanticsLabel: 'Đang đăng nhập',
                                    color: colors.onSurfaceVariant,
                                  ),
                                )
                              : const Text('Đăng nhập'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: () =>
                              Navigator.of(context).push(MaterialPageRoute<void>(builder: widget.residentLogin)),
                          child: const Text('Quét mã QR cho người cao tuổi'),
                        ),
                        const SizedBox(height: 24),
                        // Đẩy câu máy dùng chung và phiên bản xuống chân màn như mẫu
                        const Spacer(),
                        Text(
                          'Máy dùng chung: đăng nhập sẽ kết thúc phiên của người trước trên máy này.',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Phiên bản $appVersion',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nhãn hiện rõ phía trên ô (không chỉ chữ gợi ý), gộp với ô cho trình đọc màn hình (WCAG 1.3.1, 3.3.2).
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        child,
      ],
    ),
  );
}

enum _Tone { neutral, info, error }

/// Câu báo trên form: lỗi đỏ có chữ (DESIGN.md mục 1 điều 6), báo thường tông trung tính.
class _Message extends StatelessWidget {
  const _Message(this.message, {this.tone = _Tone.neutral});

  final String message;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone == _Tone.error ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        liveRegion: true,
        child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
      ),
    );
  }
}
