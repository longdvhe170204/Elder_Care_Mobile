import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/care_tasks/care_checklist_cache.dart';
import 'package:mobile/staff/care_tasks/care_tasks_home_screen.dart';

import '../../support/fake_backend.dart';

void main() {
  testWidgets('BR_M15_20_revokedChecklistPermissionClearsOnlyOwnCache', (tester) async {
    final backend = FakeBackend()..on('GET', '/me/permissions', 200, <dynamic>[]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await cache.save(7, 9, {'loadedAt': '2026-11-06T08:00:00Z', 'tasks': <dynamic>[]});
    await cache.save(8, 10, {'loadedAt': '2026-11-06T08:00:00Z', 'tasks': <dynamic>[]});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CareTasksHomeScreen(api: backend.client(), accountId: 7, cache: cache),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await cache.shiftIds(7), isEmpty);
    expect(await cache.shiftIds(8), [10]);
  });
  testWidgets('BR_M15_20_homeCanReopenOwnCachedChecklistWithoutNetwork', (tester) async {
    final backend = FakeBackend()..down = true;
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await cache.save(7, 9, {'loadedAt': '2026-11-06T08:00:00Z', 'tasks': <dynamic>[]});
    await cache.save(8, 10, {'loadedAt': '2026-11-06T08:00:00Z', 'tasks': <dynamic>[]});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CareTasksHomeScreen(api: backend.client(), accountId: 7, cache: cache),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist đã tải (ngoại tuyến)'));
    await tester.pumpAndSettle();
    expect(find.text('Ca 9'), findsOneWidget);
    expect(find.text('Ca 10'), findsNothing);
  });
  testWidgets('FR_049_homeShowsOnlyPermittedScreens', (tester) async {
    final backend = FakeBackend();
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    backend.on('GET', '/me/permissions', 200, [
      {'function': 'DAY_CARE_ATTENDANCE', 'operation': 'VIEW'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CareTasksHomeScreen(api: backend.client(), accountId: 7, cache: cache),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Điểm danh bán trú'), findsOneWidget);
    expect(find.text('Lập công việc của ca'), findsNothing);
    expect(find.text('Checklist ca'), findsNothing);
  });
  Future<void> home(WidgetTester tester, FakeBackend backend, CareChecklistCache cache, DateTime now) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CareTasksHomeScreen(api: backend.client(), accountId: 7, cache: cache, clock: () => now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Figma_98_1671_lichTuan_chonSanHomNayVaCaDangDienRa', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [
        {'id': 21, 'startsAt': '2026-11-18T00:00:00Z', 'endsAt': '2026-11-18T11:00:00Z', 'status': 'IN_PROGRESS'},
        {'id': 20, 'startsAt': '2026-11-17T11:00:00Z', 'endsAt': '2026-11-18T00:00:00Z', 'status': 'CLOSED'},
      ])
      ..on('GET', '/checklist', 200, {
        'loadedAt': '2026-11-18T01:00:00Z',
        'tasks': [
          {
            'id': 1,
            'taskType': 'Đo huyết áp',
            'status': 'OVERDUE',
            'plannedAt': '2026-11-18T00:30:00Z',
            'residentCard': {'fullName': 'Người kiểm thử', 'roomBed': 'P. 203'},
          },
          {'id': 2, 'taskType': 'Hỗ trợ vận động', 'status': 'DUE', 'plannedAt': '2026-11-18T01:00:00Z'},
        ],
      })
      ..on('GET', '/result-values', 200, <dynamic>[]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 18, 1));
    expect(find.text('Tháng 11, 2026'), findsOneWidget);
    expect(find.text('16–22/11'), findsOneWidget);
    expect(find.text('Thứ tư, 18/11'), findsOneWidget);
    expect(find.text('Hôm nay'), findsOneWidget);
    expect(find.text('Ca ngày'), findsOneWidget);
    expect(find.text('Đang diễn ra'), findsOneWidget);
    expect(find.text('Đang xem'), findsOneWidget);
    expect(find.text('Việc trong ca ngày'), findsOneWidget);
    expect(find.text('Quá hạn · 1 việc'), findsOneWidget);
    expect(find.text('Đến giờ'), findsOneWidget);
    expect(find.text('Người kiểm thử · P. 203'), findsOneWidget);
    expect(find.text('07:30'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Thứ ba, 17/11, có ca'));
    await tester.pumpAndSettle();
    expect(find.text('Ca đêm'), findsOneWidget);
    expect(find.text('Đã đóng · Kết thúc 18/11'), findsOneWidget);
    expect(find.text('Hôm nay'), findsNothing);
  });

  testWidgets('Figma_98_1671_tuanTruocTrong_baoChuaCoCa', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, <dynamic>[]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 22, 1));
    await tester.tap(find.byTooltip('Tuần trước'));
    await tester.pumpAndSettle();
    expect(find.text('9–15/11'), findsOneWidget);
    expect(find.text('Chủ nhật, 15/11'), findsOneWidget);
    expect(find.text('Chưa có ca đã công bố'), findsOneWidget);
  });

  testWidgets('checklistTuManChamSoc_chiTietMoKeHoachVaBaoSuCo', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [
        {'id': 20, 'startsAt': '2026-11-17T11:00:00Z', 'endsAt': '2026-11-18T00:00:00Z', 'status': 'IN_PROGRESS'},
      ])
      ..on('GET', '/checklist', 200, {
        'loadedAt': '2026-11-17T12:00:00Z',
        'tasks': [
          {
            'id': 1,
            'taskType': 'Hỗ trợ uống nước',
            'status': 'DUE',
            'residentId': 77,
            'residentCard': {'fullName': 'Người kiểm thử'},
            'allowedCommands': <String>[],
          },
        ],
      })
      ..on('GET', '/result-values', 200, <dynamic>[])
      ..on('GET', '/incidents', 200, <dynamic>[])
      ..on('GET', '/residents/77/care-plans', 200, <dynamic>[])
      ..on('GET', '/incident-types', 200, <dynamic>[])
      ..on('GET', '/residents', 200, {'items': <dynamic>[]});
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 17, 12));
    await tester.tap(find.text('Xem checklist'));
    await tester.pumpAndSettle();
    expect(find.text('Ca đêm · 18:00–07:00 · 17/11'), findsOneWidget);
    expect(find.text('Tiến trình ca'), findsNothing);
    await tester.tap(find.text('Hỗ trợ uống nước'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem kế hoạch chăm sóc'));
    await tester.pumpAndSettle();
    expect(find.text('Kế hoạch chăm sóc'), findsOneWidget);
    expect(find.text('Người kiểm thử'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Báo sự cố').last);
    await tester.pumpAndSettle();
    expect(find.text('Ghi nhận sự cố'), findsOneWidget);
  });

  testWidgets('Figma_98_1671_bamViec_moSanChiTietCongViec', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [
        {'id': 20, 'startsAt': '2026-11-17T11:00:00Z', 'endsAt': '2026-11-18T00:00:00Z', 'status': 'IN_PROGRESS'},
      ])
      ..on('GET', '/checklist', 200, {
        'loadedAt': '2026-11-17T12:00:00Z',
        'tasks': [
          {
            'id': 1,
            'taskType': 'Hỗ trợ uống nước',
            'status': 'DUE',
            'residentId': 77,
            'residentCard': {'fullName': 'Người kiểm thử', 'roomBed': 'Phòng A · Giường 1'},
            'allowedCommands': ['record'],
          },
        ],
      })
      ..on('GET', '/result-values', 200, <dynamic>[])
      ..on('GET', '/incidents', 200, <dynamic>[]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 17, 12));
    await tester.tap(find.text('Hỗ trợ uống nước'));
    await tester.pumpAndSettle();
    expect(find.text('Phòng A · Giường 1'), findsOneWidget);
    expect(find.text('Ghi nhận kết quả'), findsOneWidget);
  });
}
