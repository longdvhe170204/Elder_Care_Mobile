import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/auth/secure_store.dart';
import 'package:mobile/common/auth/session_controller.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/family_root.dart';

import '../../support/fake_backend.dart';
import 'portal_screen_test.dart' show resident;

// Nội dung 4 tab người thân (spec 2026-11-20 mục 6): Hôm nay (tình trạng, bữa ăn, sự cố phần chung, sức khỏe theo quyền
// có tác dụng), Lịch thăm, Chi phí, Thêm; tab thiếu quyền nói rõ lý do, mục chỉ cho người đại diện ẩn với người khác.

String _today() {
  final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
  return '${vn.year}-${vn.month.toString().padLeft(2, '0')}-${vn.day.toString().padLeft(2, '0')}';
}

Map<String, dynamic> _general({List<Object> menu = const []}) => {
  'residentId': 5,
  'fullName': 'Nguyễn Thị Lan',
  'status': 'IN_RESIDENCE',
  'location': 'Phòng 201, giường A',
  'visits': <Object>[],
  'absences': <Object>[],
  'dayCareSchedule': <Object>[],
  'incidents': <Object>[],
  'menu': menu,
  'unavailable': menu.isEmpty ? ['menu'] : <String>[],
};

Future<void> _pump(WidgetTester tester, Map<String, dynamic> r, {Map<String, dynamic>? general}) async {
  final store = MemoryStore();
  await store.write(SessionController.tokenKey, 'family-1');
  final backend = FakeBackend()
    ..on('GET', '/me', 200, user('FAMILY_MEMBER'))
    ..on('GET', '/family-portal/residents', 200, [r])
    ..on('GET', '/family-portal/residents/5/general', 200, general ?? _general());
  final s = session(backend, store, FakeBiometric(available: false));
  await s.start();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: FamilyRoot(session: s),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(NavigationDestination, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('khongQuyenChiPhi_hienCauThieuQuyen', (tester) async {
    await _pump(tester, resident());
    await _openTab(tester, 'Chi phí');
    expect(find.textContaining('chưa được cấp quyền xem chi phí của Nguyễn Thị Lan'), findsOneWidget);
    expect(find.text('Số dư'), findsNothing);
  });

  testWidgets('coQuyenChiPhi_hienSoDuVaBangChiPhi', (tester) async {
    await _pump(tester, resident(costs: true));
    await _openTab(tester, 'Chi phí');
    expect(find.text('Số dư'), findsOneWidget);
    expect(find.text('Bảng chi phí'), findsOneWidget);
  });

  testWidgets('daiDien_khongQuyenChiPhi_vanCoMuaHo', (tester) async {
    await _pump(tester, resident(representative: true));
    await _openTab(tester, 'Chi phí');
    expect(find.text('Đề nghị mua hộ'), findsOneWidget);
  });

  testWidgets('khongDaiDien_khongCoMucDaiDien', (tester) async {
    await _pump(tester, resident());
    await _openTab(tester, 'Thêm');
    for (final t in ['Yêu cầu chờ xác nhận', 'Yêu cầu thay đổi dịch vụ', 'Hợp đồng', 'Đồ gửi']) {
      expect(find.text(t), findsNothing, reason: t);
    }
    for (final t in ['Phản hồi', 'Hồ sơ', 'Đăng xuất']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('daiDien_coMucDaiDien', (tester) async {
    await _pump(tester, resident(representative: true));
    await _openTab(tester, 'Thêm');
    for (final t in ['Yêu cầu chờ xác nhận', 'Yêu cầu thay đổi dịch vụ', 'Hợp đồng', 'Đồ gửi']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('lichTham_khongQuyen_hienCauThieuQuyen', (tester) async {
    await _pump(tester, resident());
    await _openTab(tester, 'Lịch thăm');
    expect(find.textContaining('chưa được cấp quyền đăng ký thăm'), findsOneWidget);
    expect(find.text('Đăng ký thăm'), findsNothing);
  });

  testWidgets('lichTham_coQuyen_coNutDangKy', (tester) async {
    await _pump(tester, resident(visits: true));
    await _openTab(tester, 'Lịch thăm');
    expect(find.text('Đăng ký thăm'), findsOneWidget);
  });

  testWidgets('homNay_hienThucDon', (tester) async {
    await _pump(
      tester,
      resident(),
      general: _general(
        menu: [
          {'date': _today(), 'mealName': 'Trưa', 'dishName': 'Cá kho'},
        ],
      ),
    );
    await tester.scrollUntilVisible(find.textContaining('Cá kho'), 200);
    expect(find.textContaining('Cá kho'), findsOneWidget);
  });

  testWidgets('homNay_khongQuyenSucKhoe_khongNut', (tester) async {
    await _pump(tester, resident());
    await tester.scrollUntilVisible(
      find.text('Thông tin sức khỏe chỉ hiện với người thân được người cao tuổi đồng ý chia sẻ.'),
      200,
    );
    expect(find.text('Xem sức khỏe'), findsNothing);
  });

  testWidgets('homNay_coQuyenSucKhoe_coNut', (tester) async {
    await _pump(tester, resident(health: true));
    await tester.scrollUntilVisible(find.text('Xem sức khỏe'), 200);
    expect(find.text('Xem sức khỏe'), findsOneWidget);
  });
}
