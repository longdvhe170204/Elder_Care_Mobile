import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/auth/secure_store.dart';
import 'package:mobile/common/auth/session_controller.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/staff_root.dart';

import '../support/fake_backend.dart';

// Khung app nhân viên theo Figma "03 · App nhân viên" (spec 2026-11-20 điều hướng theo vai trò mục 5): thanh dưới
// Ca của tôi · [tab 2] · Tra cứu · Thông báo · Thêm; nút Khẩn cấp trên mọi tab; "Thêm" có nhóm công cụ và Đăng xuất;
// vai trò chỉ dùng web không vào phần nhân viên.

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

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(NavigationDestination, 'Thêm'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dieuDuong_thanhDuoi_theoFigma', (tester) async {
    await _pump(tester, ['AC-04']);
    expect(_tabLabels(tester), ['Ca của tôi', 'Checklist', 'Tra cứu', 'Thông báo', 'Thêm']);
  });

  testWidgets('bacSi_thanhDuoi_4Tab', (tester) async {
    await _pump(tester, ['AC-03']);
    expect(_tabLabels(tester), ['Ca của tôi', 'Người cao tuổi', 'Thông báo', 'Thêm']);
  });

  testWidgets('truongTang_tab2TangHomNay', (tester) async {
    await _pump(tester, ['AC-02', 'AC-04']);
    expect(_tabLabels(tester)[1], 'Tầng hôm nay');
  });

  testWidgets('bep_tab2PhieuBuaAn', (tester) async {
    await _pump(tester, ['AC-07']);
    expect(_tabLabels(tester)[1], 'Phiếu bữa ăn');
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

  testWidgets('them_haiNhom_coDangXuat', (tester) async {
    await _pump(tester, ['AC-04']);
    await _openMore(tester);
    expect(find.text('Đồng bộ'), findsOneWidget);
    expect(find.text('Chờ xem lại'), findsOneWidget);
    expect(find.text('Phê duyệt'), findsNothing);
    expect(find.text('Phát thuốc'), findsNothing);
    await tester.scrollUntilVisible(find.text('Đăng xuất'), 200);
    expect(find.text('Đăng xuất'), findsOneWidget);
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
    expect(_tabLabels(tester), contains('Checklist'));
  });

  // 003 T060: ô ⁴⁰ (Người phụ trách ca) không có trong `/me/permissions`; mục Giường của Trưởng tầng hiện khi danh sách
  // giường Chờ sẵn sàng theo nhiệm vụ trả 200, 403 thì không hiện.
  testWidgets('T060_truongTangPhuTrachCa_hienMucGiuong', (tester) async {
    await _pump(tester, ['AC-02'], routes: (b) => b.on('GET', '/bed-readiness/beds', 200, <Object>[]));
    await _openMore(tester);
    expect(find.text('Giường'), findsOneWidget);
  });

  testWidgets('T060_khongNhiemVuPhuTrachCa_khongHienMucGiuong', (tester) async {
    await _pump(
      tester,
      ['AC-02'],
      routes: (b) => b.on('GET', '/bed-readiness/beds', 403, {'detail': 'Không có quyền'}),
    );
    await _openMore(tester);
    expect(find.text('Giường'), findsNothing);
  });
}
