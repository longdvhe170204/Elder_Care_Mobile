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
  testWidgets('SRS_2_2_chonCa_hienGioVaCaDangDienRaLenDau', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [
        {'id': 21, 'startsAt': '2026-11-18T00:00:00Z', 'endsAt': '2026-11-18T11:00:00Z', 'status': 'PUBLISHED'},
        {'id': 20, 'startsAt': '2026-11-17T11:00:00Z', 'endsAt': '2026-11-18T00:00:00Z', 'status': 'IN_PROGRESS'},
      ]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CareTasksHomeScreen(api: backend.client(), accountId: 7, cache: cache),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist ca'));
    await tester.pumpAndSettle();
    final current = find.text('17/11/2026 18:00 – 18/11/2026 07:00');
    final next = find.text('18/11/2026 07:00 – 18/11/2026 18:00');
    expect(current, findsOneWidget);
    expect(next, findsOneWidget);
    expect(find.text('Đang diễn ra'), findsOneWidget);
    expect(tester.getTopLeft(current).dy, lessThan(tester.getTopLeft(next).dy));
    expect(find.text('Ca 20'), findsNothing);
  });
  testWidgets('SRS_2_2_checklistTuManChamSoc_coTienTrinhCa_moKeHoachVaBaoSuCo', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CareTasksHomeScreen(api: backend.client(), accountId: 7, cache: cache),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Checklist ca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('17/11/2026 18:00 – 18/11/2026 07:00'));
    await tester.pumpAndSettle();
    expect(find.text('Tiến trình ca'), findsOneWidget);
    expect(find.text('0/1 xong'), findsOneWidget);
    expect(find.text('Chưa lập, còn 1 việc chưa xong'), findsOneWidget);
    await tester.tap(find.text('Xem kế hoạch'));
    await tester.pumpAndSettle();
    expect(find.text('Kế hoạch chăm sóc'), findsOneWidget);
    expect(find.text('Người kiểm thử'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Báo sự cố').last);
    await tester.pumpAndSettle();
    expect(find.text('Ghi nhận sự cố'), findsOneWidget);
  });
}
