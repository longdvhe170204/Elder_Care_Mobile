import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/auth/auth_layout.dart';
import 'package:mobile/common/auth/forgot_password_screen.dart';
import 'package:mobile/common/auth/login_screen.dart';
import 'package:mobile/common/theme/app_theme.dart';

import '../../support/fake_backend.dart';

// Tỷ lệ theo Figma "Elder Care — Thiết kế lại Web + App Base", trang Prototype · Mobile: khung "Đăng nhập · Mobile" (88:254)
// và "Quên mật khẩu · Mobile" (94:259), máy 390 × 860.

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
  await tester.pumpAndSettle();
}

Widget _forgot() => ForgotPasswordScreen(api: FakeBackend().client());

void main() {
  testWidgets('thuongHieu_logo60_chu34', (tester) async {
    await _pump(tester, _forgot());
    expect(tester.getSize(find.byKey(AuthLayout.logoKey)), const Size(60, 60));
    expect(tester.widget<Text>(find.text('Elder Care')).style?.fontSize, 34);
    expect(tester.widget<Text>(find.text('Elder Care')).style?.fontWeight, FontWeight.w700);
  });

  testWidgets('quenMatKhau_tieuDe26_nutXacNhan176x52', (tester) async {
    await _pump(tester, _forgot());
    expect(tester.widget<Text>(find.text('Quên mật khẩu')).style?.fontSize, 26);
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Xác nhận')), const Size(176, 52));
    expect(tester.getCenter(find.widgetWithText(FilledButton, 'Xác nhận')).dx, 195);
  });

  testWidgets('quenMatKhau_oNhapCao56_leNoiDung28', (tester) async {
    await _pump(tester, _forgot());
    final field = find.byKey(ForgotPasswordScreen.usernameKey);
    expect(tester.getSize(field).height, 56);
    expect(tester.getTopLeft(field).dx, 28);
    expect(tester.getTopRight(field).dx, 362);
  });

  testWidgets('quenMatKhau_quayLaiCanPhai_dongMan', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _forgot())),
            child: const Text('mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    final back = find.text('Quay lại trang đăng nhập');
    expect(tester.getTopRight(back).dx, closeTo(362, 1));
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('mở'), findsOneWidget);
  });

  testWidgets('dangNhap_cungThuongHieu_nut244x52', (tester) async {
    await _pump(tester, LoginScreen(onSubmit: (_, _) async {}, residentLogin: (_) => const SizedBox()));
    expect(tester.getSize(find.byKey(AuthLayout.logoKey)), const Size(60, 60));
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Đăng nhập')), const Size(244, 52));
    expect(tester.getSize(find.byKey(LoginScreen.usernameKey)).height, 56);
  });

  testWidgets('phienBan_oChanMan', (tester) async {
    await _pump(tester, _forgot());
    final version = find.text('Phiên bản $appVersion');
    expect(tester.widget<Text>(version).style?.fontSize, 13);
    expect(tester.getBottomLeft(version).dy, greaterThan(780));
  });
}
