import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';

/// Phiên bản hiển thị ở chân màn; giữ khớp `version` trong pubspec.yaml.
const appVersion = '1.0.0';

/// Khung chung của màn trước đăng nhập (Đăng nhập, Quên mật khẩu), tỷ lệ theo Figma "Elder Care — Thiết kế lại Web + App
/// Base", trang Prototype · Mobile, khung 88:254 và 94:259 (máy 390 × 860): lề nội dung 28, trên 58; thương hiệu là ô
/// 60 × 60 bo 16 màu xanh đêm có lá 28, cách 14 là chữ "Elder Care" 34/44 đậm; cách 34 là phần biểu mẫu; chân màn là
/// phiên bản 13/20 chữ phụ.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.children});

  static const logoKey = ValueKey('auth.logo');

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 58, 28, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: ExcludeSemantics(
                              child: Container(
                                key: logoKey,
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(color: tones.header, borderRadius: BorderRadius.circular(16)),
                                child: Icon(LucideIcons.leaf, color: tones.headerInkStrong, size: 28),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Semantics(
                            header: true,
                            child: Text(
                              'Elder Care',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineLarge?.copyWith(
                                fontSize: 34,
                                height: 44 / 34,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          const SizedBox(height: 34),
                          ...children,
                        ],
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: Text(
                        'Phiên bản $appVersion',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          height: 20 / 13,
                          fontWeight: FontWeight.w500,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiêu đề biểu mẫu 26/34 đậm, căn giữa (Figma 94:275).
class AuthTitle extends StatelessWidget {
  const AuthTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontSize: 26,
          height: 34 / 26,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Nhãn 14/20 nửa đậm trên ô, cách 8 (Figma thành phần "Số điện thoại"); gộp với ô cho trình đọc màn hình
/// (WCAG 1.3.1, 3.3.2).
class AuthField extends StatelessWidget {
  const AuthField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Ô nhập cao 56, bo 10, viền màu control; biểu tượng 20 cách lề trái 14 và cách chữ 12; chữ gợi ý 16/22 màu phụ
/// (Figma "Ô nhập").
InputDecoration authInputDecoration(
  BuildContext context, {
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  final colors = Theme.of(context).colorScheme;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 16, height: 22 / 16, color: colors.onSurfaceVariant),
    constraints: const BoxConstraints.tightFor(height: 56),
    contentPadding: const EdgeInsets.symmetric(vertical: 17),
    prefixIcon: Padding(
      padding: const EdgeInsets.only(left: 14, right: 12),
      child: Icon(icon, size: 20, color: colors.onSurfaceVariant),
    ),
    prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 20),
    suffixIcon: suffix == null ? null : Padding(padding: const EdgeInsets.only(right: 8), child: suffix),
  );
}

/// Kiểu chữ ô nhập 16/22 (Figma "Ô nhập").
const authInputStyle = TextStyle(fontSize: 16, height: 22 / 16);

/// Nút chính cao 52, bo 8, chữ 14/21 nửa đậm, rộng theo khung Figma (Đăng nhập 244, Xác nhận 176); đang gửi thì khóa
/// nút và hiện vòng tải.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.width,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
  });

  final String label;
  final double width;
  final VoidCallback onPressed;
  final bool busy;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        width: width,
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            textStyle: const TextStyle(fontSize: 14, height: 21 / 14, fontWeight: FontWeight.w600),
          ),
          onPressed: busy ? null : onPressed,
          child: busy
              ? SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    semanticsLabel: busyLabel,
                    color: colors.onSurfaceVariant,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}

/// Liên kết chữ 14/20 nửa đậm màu xanh trời đậm, vùng bấm cao 48 (Figma "Quên mật khẩu?", "Quay lại trang đăng nhập").
class AuthLink extends StatelessWidget {
  const AuthLink({super.key, required this.label, required this.onPressed, this.alignment = Alignment.centerRight});

  final String label;
  final VoidCallback onPressed;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: alignment,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: colors.secondary,
          minimumSize: const Size(48, 48),
          padding: EdgeInsets.zero,
          textStyle: const TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

/// Câu báo trên biểu mẫu: lỗi đỏ có chữ (DESIGN.md mục 1 điều 6), báo thường màu chữ chính; đọc ngay khi hiện.
class AuthMessage extends StatelessWidget {
  const AuthMessage(this.message, {super.key, this.error = false});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: error ? theme.colorScheme.error : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
