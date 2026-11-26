import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/auth/secure_store.dart';
import 'package:mobile/common/auth/session_controller.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/staff_root.dart';

import '../support/fake_backend.dart';

Future<FakeBackend> _pump(
  WidgetTester tester,
  List<String> roles, {
  List<Map<String, String>> grants = const [],
  void Function(FakeBackend)? routes,
}) async {
  final store = MemoryStore();
  await store.write(SessionController.tokenKey, 'session-1');
  final backend = FakeBackend()
    ..on('GET', '/me', 200, {...user('STAFF'), 'roles': roles})
    ..on('GET', '/me/permissions', 200, grants);
  routes?.call(backend);
  final s = session(backend, store, FakeBiometric());
  await s.start();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: StaffRoot(session: s, queue: memoryQueue(s)),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

List<String> _tabLabels(WidgetTester tester) => [
  for (final d in tester.widgetList<NavigationDestination>(find.byType(NavigationDestination))) d.label,
];

Future<void> _openAccount(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(NavigationDestination, 'Tài khoản'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('thanhDuoi_baTab_theoFigma', (tester) async {
    await _pump(tester, ['AC-04']);
    expect(_tabLabels(tester), ['Trang chủ', 'Thông báo', 'Tài khoản']);
    expect(find.text('Checklist ca'), findsOneWidget);
    expect(find.text('Tra cứu'), findsOneWidget);
    expect(find.text('Điều dưỡng'), findsOneWidget);
  });

  testWidgets('bacSi_moTraCuuTuTrangChu', (tester) async {
    await _pump(tester, ['AC-03']);
    expect(_tabLabels(tester), ['Trang chủ', 'Thông báo', 'Tài khoản']);
    expect(find.text('Tra cứu'), findsOneWidget);
    expect(find.text('Checklist ca'), findsNothing);
  });

  testWidgets('truongTang_coChecklistTrenTrangChu', (tester) async {
    await _pump(tester, ['AC-02', 'AC-04']);
    expect(find.text('Trưởng tầng'), findsOneWidget);
    expect(find.text('Checklist ca'), findsOneWidget);
  });

  testWidgets('bep_coPhieuBuaAnTrenTrangChu', (tester) async {
    await _pump(tester, ['AC-07']);
    expect(find.text('Phiếu bữa ăn'), findsOneWidget);
  });

  testWidgets('chiKeToan_manChiWeb', (tester) async {
    await _pump(tester, ['AC-14']);
    expect(find.text('Vai trò của bạn dùng trên web quản trị'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Đăng xuất'), findsOneWidget);
  });

  testWidgets('nutKhanCap_moiTab', (tester) async {
    await _pump(tester, ['AC-05']);
    for (final label in _tabLabels(tester)) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      // Tab có vòng tải chạy liên tục (chờ backend giả) nên không chờ ổn định hẳn.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.widgetWithText(TextButton, 'Khẩn cấp'), findsOneWidget, reason: label);
    }
  });

  testWidgets('trangChu_coTienIch_vaTaiKhoanCoNutDangXuatCanGiua', (tester) async {
    await _pump(tester, ['AC-04']);
    expect(find.text('Đồng bộ'), findsOneWidget);
    expect(find.text('Chờ xem lại'), findsOneWidget);
    expect(find.text('Phát thuốc'), findsNothing);
    expect(find.text('Đăng xuất'), findsNothing);

    await _openAccount(tester);
    final logout = find.widgetWithText(FilledButton, 'Đăng xuất');
    expect(find.text('Thông tin cá nhân'), findsOneWidget);
    expect(find.text('Đổi mật khẩu'), findsOneWidget);
    expect(logout, findsOneWidget);
    expect(tester.getCenter(logout).dx, tester.getCenter(find.byType(NavigationBar)).dx);
    expect(tester.getTopLeft(logout).dy, greaterThan(tester.getBottomLeft(find.text('Đổi mật khẩu')).dy));
  });

  testWidgets('taiKhoan_moThongTinCaNhan_vaDoiMatKhauGiuVaiTro', (tester) async {
    final backend = await _pump(
      tester,
      ['AC-04'],
      routes: (backend) {
        backend.on('GET', '/me', 200, {
          ...user('STAFF'),
          'fullName': 'Hoàng Thị Dung',
          'email': 'dung@example.test',
          'phoneNumber': '0900000000',
        });
        backend.on('POST', '/auth/change-password', 204);
      },
    );
    await _openAccount(tester);
    expect(find.text('Hoàng Thị Dung'), findsOneWidget);
    await tester.tap(find.text('Thông tin cá nhân'));
    await tester.pumpAndSettle();
    expect(find.text('dung@example.test'), findsOneWidget);
    expect(find.text('0900000000'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Đổi mật khẩu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu hiện tại'), 'hienTai123');
    await tester.enterText(find.widgetWithText(TextField, 'Mật khẩu mới'), 'matKhauMoi123');
    await tester.tap(find.text('Lưu mật khẩu mới'));
    await tester.pumpAndSettle();
    expect(backend.calls('POST', '/auth/change-password'), hasLength(1));
    expect(find.text('Đã đổi mật khẩu.'), findsOneWidget);
    expect(find.text('Điều dưỡng'), findsOneWidget);
    expect(_tabLabels(tester), ['Trang chủ', 'Thông báo', 'Tài khoản']);
  });

  testWidgets('matMang_vaiTroDaLuu_vanCoChecklist', (tester) async {
    final store = MemoryStore();
    await store.write(SessionController.tokenKey, 'session-1');
    await store.write(SessionController.userTypeKey, AccountType.staff.name);
    await store.write(SessionController.rolesKey, 'AC-04');
    final backend = FakeBackend()..down = true;
    final s = session(backend, store, FakeBiometric());
    await s.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StaffRoot(session: s, queue: memoryQueue(s)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Checklist ca'), findsOneWidget);
  });

  testWidgets('taiLaiKhiMatMang_giuCacLoiVaoDaCapQuyen', (tester) async {
    final backend = await _pump(
      tester,
      ['AC-04'],
      grants: [
        {'function': 'SHIFT_SCHEDULE', 'operation': 'VIEW'},
        {'function': 'SHIFT_HANDOVER', 'operation': 'VIEW'},
      ],
    );
    expect(find.text('Lịch ca và đơn'), findsOneWidget);
    expect(find.text('Bàn giao ca'), findsOneWidget);

    backend.down = true;
    await tester.runAsync(tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh);
    await tester.pumpAndSettle();
    expect(find.text('Lịch ca và đơn'), findsOneWidget);
    expect(find.text('Bàn giao ca'), findsOneWidget);
  });

  // 003 T060: ô ⁴⁰ (Người phụ trách ca) không có trong `/me/permissions`; mục Giường của Trưởng tầng hiện khi danh sách
  // giường Chờ sẵn sàng theo nhiệm vụ trả 200, 403 thì không hiện.
  testWidgets('T060_truongTangPhuTrachCa_hienMucGiuong', (tester) async {
    await _pump(tester, ['AC-02'], routes: (b) => b.on('GET', '/bed-readiness/beds', 200, <Object>[]));
    await tester.scrollUntilVisible(find.text('Giường'), 160);
    await tester.pumpAndSettle();
    expect(find.text('Giường').hitTestable(), findsOneWidget);
  });

  testWidgets('T060_khongNhiemVuPhuTrachCa_khongHienMucGiuong', (tester) async {
    await _pump(tester, [
      'AC-02',
    ], routes: (b) => b.on('GET', '/bed-readiness/beds', 403, {'detail': 'Không có quyền'}));
    await tester.scrollUntilVisible(find.text('Báo sự cố'), 160);
    expect(find.text('Giường'), findsNothing);
  });
}
