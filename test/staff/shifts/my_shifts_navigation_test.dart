import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/app.dart';
import 'package:mobile/common/auth/secure_store.dart';
import 'package:mobile/common/auth/session_controller.dart';

import '../../support/fake_backend.dart';

Future<void> pumpStaff(WidgetTester tester, FakeBackend backend) async {
  backend.on('GET', '/me', 200, user('STAFF'));
  final store = MemoryStore()..values[SessionController.tokenKey] = 'test-session';
  final current = session(backend, store, FakeBiometric(available: false));
  await current.start();
  await tester.pumpWidget(ElderCareApp(session: current, queue: memoryQueue(current)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR_054_trangChu_tabDau_moMacDinh', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'SHIFT_SCHEDULE', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [])
      ..on('GET', '/staff', 200, []);

    await pumpStaff(tester, backend);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
    expect((bar.destinations.first as NavigationDestination).label, 'Trang chủ');
    expect(backend.calls('GET', '/me/permissions').single.headers['Authorization'], 'Bearer test-session');
    expect(tester.takeException(), isNull);
  });

  testWidgets('FR_054_lichCaVaDon_moLichCa_coDoiCaNghi', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'SHIFT_SCHEDULE', 'operation': 'VIEW'},
        {'function': 'SHIFT_SWAP_REQUEST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [])
      ..on('GET', '/staff', 200, []);

    await pumpStaff(tester, backend);
    await tester.scrollUntilVisible(find.text('Lịch ca và đơn'), 200);
    await tester.tap(find.text('Lịch ca và đơn'));
    await tester.pumpAndSettle();
    expect(find.text('Bạn không có ca nào trong tháng này.'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Đổi ca, nghỉ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final grants in <List<Map<String, dynamic>>>[
    [],
    [
      {'function': 'SHIFT_SCHEDULE', 'operation': 'CREATE'},
    ],
  ]) {
    testWidgets('FR_054_khongQuyenXemLich_khongCoLichCaVaDon_$grants', (tester) async {
      final backend = FakeBackend()..on('GET', '/me/permissions', 200, grants);
      await pumpStaff(tester, backend);
      expect(find.text('Lịch ca và đơn'), findsNothing);
      await tester.scrollUntilVisible(find.text('Báo sự cố'), 160);
      expect(find.text('Báo sự cố'), findsOneWidget);
    });
  }

  testWidgets('FR_054_homeGridWorksAt200PercentTextOnNarrowPhone', (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'SHIFT_SCHEDULE', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [])
      ..on('GET', '/staff', 200, []);

    await pumpStaff(tester, backend);
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
