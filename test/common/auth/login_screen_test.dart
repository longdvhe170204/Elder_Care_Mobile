import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/auth/login_screen.dart';
import 'package:mobile/common/theme/app_theme.dart';

import '../../support/fake_backend.dart';

// Màn đăng nhập theo mẫu anh gửi 2026-11-21 (logo, nhãn trên ô, mắt hiện mật khẩu, Quên mật khẩu?, nút Đăng nhập, Quét mã
// QR cho người cao tuổi, phiên bản); ô đầu giữ "Tên đăng nhập" vì backend đăng nhập bằng tên đăng nhập (anh chốt).

void main() {
  late List<(String, String)> submitted;
  Completer<void>? pending;

  setUp(() {
    submitted = [];
    pending = null;
  });

  Future<void> pump(WidgetTester tester, {FakeBackend? backend}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LoginScreen(
          onSubmit: (u, p) {
            submitted.add((u, p));
            return pending?.future ?? Future.value();
          },
          residentLogin: (_) => const Scaffold(body: Text('màn quét mã')),
          api: backend?.client(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('nhanHienTrenO_vaChuGoiY', (tester) async {
    await pump(tester);
    expect(find.text('Elder Care'), findsOneWidget);
    expect(find.text('Tên đăng nhập'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('Nhập tên đăng nhập'), findsOneWidget);
    expect(find.text('Nhập mật khẩu'), findsOneWidget);
    // Nhãn nằm trên ô, không nằm trong ô
    expect(
      tester.getBottomLeft(find.text('Tên đăng nhập')).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(LoginScreen.usernameKey)).dy),
    );
  });

  testWidgets('nhanGanVoiO_choTrinhDocManHinh', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    expect(tester.getSemantics(find.byKey(LoginScreen.usernameKey)).label, contains('Tên đăng nhập'));
    expect(tester.getSemantics(find.byKey(LoginScreen.passwordKey)).label, contains('Mật khẩu'));
    handle.dispose();
  });

  testWidgets('matKhau_anMacDinh_bamMatDeHien', (tester) async {
    await pump(tester);
    EditableText field() => tester.widget<EditableText>(
      find.descendant(of: find.byKey(LoginScreen.passwordKey), matching: find.byType(EditableText)),
    );
    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Hiện mật khẩu'));
    await tester.pump();
    expect(field().obscureText, isFalse);
    expect(find.byTooltip('Ẩn mật khẩu'), findsOneWidget);
  });

  testWidgets('dangNhap_guiTenDaCatKhoangTrang', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(LoginScreen.usernameKey), ' dd.dieuduong01 ');
    await tester.enterText(find.byKey(LoginScreen.passwordKey), 'Demo2026!');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();
    expect(submitted, [('dd.dieuduong01', 'Demo2026!')]);
  });

  testWidgets('dangGui_nutKhoa_hienVongTai', (tester) async {
    pending = Completer<void>();
    await pump(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    pending!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('quetMaQr_moManNguoiCaoTuoi', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Quét mã QR cho người cao tuổi'));
    await tester.pumpAndSettle();
    expect(find.text('màn quét mã'), findsOneWidget);
  });

  testWidgets('quenMatKhau_chiKhiKenhTinNhanCoCauHinh', (tester) async {
    await pump(tester, backend: FakeBackend()..on('GET', '/auth/password-reset/availability', 200, {'available': true}));
    expect(find.text('Quên mật khẩu?'), findsOneWidget);
  });

  // Câu máy dùng chung (FR-014a) anh bỏ khỏi màn ngày 2026-11-21 cho khớp mẫu Figma 88:254.
  testWidgets('chanMan_coPhienBan', (tester) async {
    await pump(tester);
    expect(find.text('Phiên bản 1.0.0'), findsOneWidget);
  });
}
