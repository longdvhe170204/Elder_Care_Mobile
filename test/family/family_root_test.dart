import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/auth/secure_store.dart';
import 'package:mobile/common/auth/session_controller.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/family_root.dart';

import '../support/fake_backend.dart';
import 'portal/portal_screen_test.dart' show resident;

// Khung người thân (spec 2026-11-20 điều hướng theo vai trò mục 6, anh chốt): thanh dưới cố định 5 tab cho mọi người
// thân, kể cả khi thiếu quyền; người thân của nhiều người cao tuổi chọn người ở đầu màn.

const _tabs = ['Hôm nay', 'Lịch thăm', 'Chi phí', 'Thông báo', 'Thêm'];

Future<FakeBackend> _pump(WidgetTester tester, List<Map<String, dynamic>> residents) async {
  final store = MemoryStore();
  await store.write(SessionController.tokenKey, 'family-1');
  final backend = FakeBackend()
    ..on('GET', '/me', 200, user('FAMILY_MEMBER'))
    ..on('GET', '/family-portal/residents', 200, residents)
    ..on('GET', '/me/notifications', 200, {'items': <Object>[]});
  final s = session(backend, store, FakeBiometric(available: false));
  await s.start();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: FamilyRoot(session: s),
    ),
  );
  await tester.pumpAndSettle();
  return backend;
}

List<String> _labels(WidgetTester tester) => [
  for (final d in tester.widgetList<NavigationDestination>(find.byType(NavigationDestination))) d.label,
];

void main() {
  testWidgets('nguoiThan_luonDu5Tab', (tester) async {
    await _pump(tester, [resident()]);
    expect(_labels(tester), _tabs);
  });

  testWidgets('khongCoNguoiCaoTuoi_van5Tab_baoChuaCo', (tester) async {
    await _pump(tester, []);
    expect(_labels(tester), _tabs);
    expect(find.text('Chưa có người cao tuổi nào có quan hệ Hiệu lực với tài khoản này.'), findsOneWidget);
  });

  testWidgets('motNguoiCaoTuoi_khongCoOChon', (tester) async {
    await _pump(tester, [resident()]);
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('haiNguoiCaoTuoi_coOChon', (tester) async {
    await _pump(tester, [
      resident(),
      {...resident(), 'residentId': 6, 'fullName': 'Trần Văn Bình'},
    ]);
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Trần Văn Bình'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Trần Văn Bình')).selected, isTrue);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Nguyễn Thị Lan')).selected, isFalse);
  });
}
