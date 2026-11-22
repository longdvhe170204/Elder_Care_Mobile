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

  Map<String, dynamic> task(int id, String type, String status, int resident, String name, String at,
      {List<String> commands = const []}) => {
    'id': id,
    'taskType': type,
    'status': status,
    'resultType': 'PERFORMED',
    'plannedAt': at,
    'residentId': resident,
    'residentCard': {'fullName': name, 'roomBed': 'Phòng 203'},
    'allowedCommands': commands,
  };

  testWidgets('Figma_105_1024_lichTuan_caVaDanhSachNguoiCaoTuoi', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [
        {'id': 21, 'startsAt': '2026-11-18T00:00:00Z', 'endsAt': '2026-11-18T11:00:00Z', 'status': 'IN_PROGRESS'},
        {'id': 22, 'startsAt': '2026-11-18T11:00:00Z', 'endsAt': '2026-11-19T00:00:00Z', 'status': 'PUBLISHED'},
        {'id': 20, 'startsAt': '2026-11-17T11:00:00Z', 'endsAt': '2026-11-18T00:00:00Z', 'status': 'CLOSED'},
      ])
      ..onRequest('GET', '/checklist', (r) {
        final tasks = r.url.queryParameters['shiftId'] == '21'
            ? [
                task(1, 'Đo huyết áp', 'OVERDUE', 77, 'Nguyễn Thị Lan', '2026-11-18T00:30:00Z'),
                task(2, 'Ghi nhận lượng nước', 'NOT_YET_DUE', 77, 'Nguyễn Thị Lan', '2026-11-18T03:30:00Z'),
                task(3, 'Hỗ trợ vận động', 'DUE', 78, 'Phạm Minh Đức', '2026-11-18T01:00:00Z'),
              ]
            : <Map<String, dynamic>>[];
        return {'loadedAt': '2026-11-18T01:00:00Z', 'tasks': tasks};
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
    expect(find.text('Nguyễn Thị Lan'), findsOneWidget);
    expect(find.text('2 việc còn lại'), findsOneWidget);
    expect(find.text('1 quá hạn'), findsOneWidget);
    expect(find.text('Phạm Minh Đức'), findsOneWidget);
    expect(find.text('Ca đêm'), findsOneWidget);
    expect(find.text('18:00 – 07:00 · Kết thúc 19/11'), findsOneWidget);
    expect(find.text('Chưa có danh sách người cao tuổi cho ca này.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Thứ ba, 17/11, có ca'));
    await tester.pumpAndSettle();
    expect(find.text('Đã đóng'), findsOneWidget);
    expect(find.text('Hôm nay'), findsNothing);
  });

  testWidgets('Figma_105_1324_bamNguoiCaoTuoi_moViecChamSocVaGhiNhan', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [
        {'id': 21, 'startsAt': '2026-11-18T00:00:00Z', 'endsAt': '2026-11-18T11:00:00Z', 'status': 'IN_PROGRESS'},
      ])
      ..on('GET', '/checklist', 200, {
        'loadedAt': '2026-11-18T01:00:00Z',
        'tasks': [
          task(1, 'Đo huyết áp', 'OVERDUE', 77, 'Nguyễn Thị Lan', '2026-11-18T02:00:00Z', commands: ['record']),
          task(2, 'Hỗ trợ vệ sinh cá nhân', 'COMPLETED', 77, 'Nguyễn Thị Lan', '2026-11-18T00:30:00Z'),
          task(3, 'Hỗ trợ vận động', 'DUE', 78, 'Phạm Minh Đức', '2026-11-18T01:00:00Z'),
        ],
      })
      ..on('GET', '/result-values', 200, <dynamic>[]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 18, 1));
    await tester.tap(find.text('Nguyễn Thị Lan'));
    await tester.pumpAndSettle();
    expect(find.text('Việc chăm sóc'), findsOneWidget);
    expect(find.text('Ca ngày · 18/11 · 07:00–18:00'), findsOneWidget);
    expect(find.text('NL'), findsOneWidget);
    expect(find.text('1/2 việc đã hoàn thành'), findsOneWidget);
    expect(find.text('Cần thực hiện'), findsOneWidget);
    expect(find.text('1 việc'), findsOneWidget);
    expect(find.text('Quá hạn'), findsOneWidget);
    expect(find.text('Hỗ trợ vận động'), findsNothing);
    expect(find.text('Hỗ trợ vệ sinh cá nhân'), findsNothing);
    await tester.tap(find.text('Đã hoàn thành · 1 việc'));
    await tester.pumpAndSettle();
    expect(find.text('Hỗ trợ vệ sinh cá nhân'), findsOneWidget);
    await tester.tap(find.text('Ghi nhận'));
    await tester.pumpAndSettle();
    expect(find.text('Lưu kết quả'), findsOneWidget);
  });

  testWidgets('chiTietCongViec_moKeHoachVaBaoSuCo', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, [
        {'id': 20, 'startsAt': '2026-11-17T11:00:00Z', 'endsAt': '2026-11-18T00:00:00Z', 'status': 'IN_PROGRESS'},
      ])
      ..on('GET', '/checklist', 200, {
        'loadedAt': '2026-11-17T12:00:00Z',
        'tasks': [task(1, 'Hỗ trợ uống nước', 'DUE', 77, 'Người kiểm thử', '2026-11-17T12:00:00Z')],
      })
      ..on('GET', '/result-values', 200, <dynamic>[])
      ..on('GET', '/residents/77/care-plans', 200, <dynamic>[])
      ..on('GET', '/incident-types', 200, <dynamic>[])
      ..on('GET', '/residents', 200, {'items': <dynamic>[]});
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 17, 12));
    expect(find.text('Ca đêm'), findsOneWidget);
    await tester.tap(find.text('Người kiểm thử'));
    await tester.pumpAndSettle();
    expect(find.text('Ca đêm · 17/11 · 18:00–07:00'), findsOneWidget);
    await tester.tap(find.text('Hỗ trợ uống nước'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem kế hoạch chăm sóc'));
    await tester.pumpAndSettle();
    expect(find.text('Kế hoạch chăm sóc'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Báo sự cố'));
    await tester.pumpAndSettle();
    expect(find.text('Ghi nhận sự cố'), findsOneWidget);
  });
}
