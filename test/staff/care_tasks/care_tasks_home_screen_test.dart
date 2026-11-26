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
    // Tab Checklist không còn "Việc chăm sóc khác"; Điểm danh bán trú ở tab Ca của tôi (chủ dự án 2026-11-22).
    expect(find.text('Bạn không có quyền mở Checklist ca.'), findsOneWidget);
    expect(find.text('Điểm danh bán trú'), findsNothing);
    expect(find.text('Lập công việc của ca'), findsNothing);
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

  testWidgets('checklistTuan_khongConViecChamSocKhac', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/permissions', 200, [
        {'function': 'TASK_CHECKLIST', 'operation': 'VIEW'},
        {'function': 'TASK_CHECKLIST', 'operation': 'CREATE'},
        {'function': 'SHIFT_TASK_PLANNING', 'operation': 'VIEW'},
        {'function': 'DAY_CARE_ATTENDANCE', 'operation': 'VIEW'},
      ])
      ..on('GET', '/me/shifts', 200, <dynamic>[]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 22, 1));
    expect(find.text('Chưa có ca đã công bố'), findsOneWidget);
    expect(find.text('Việc chăm sóc khác'), findsNothing);
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

  testWidgets('Figma_98_1671_lichTuan_caVaCongViecTheoGio', (tester) async {
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
                task(1, 'Đo huyết áp', 'OVERDUE', 77, 'Nguyễn Thị Lan', '2026-11-18T01:30:00Z'),
                task(2, 'Ghi nhận lượng nước', 'NOT_YET_DUE', 77, 'Nguyễn Thị Lan', '2026-11-18T03:30:00Z'),
                task(3, 'Hỗ trợ vận động', 'DUE', 78, 'Phạm Minh Đức', '2026-11-18T02:45:00Z'),
                task(4, 'Hỗ trợ vệ sinh cá nhân', 'COMPLETED', 78, 'Phạm Minh Đức', '2026-11-18T00:30:00Z'),
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
    expect(find.text('Ca ngày'), findsOneWidget);
    expect(find.text('Đang diễn ra'), findsOneWidget);
    expect(find.text('Giờ'), findsOneWidget);
    expect(find.text('Công việc'), findsOneWidget);
    // Công việc hiện thẳng trong ca, theo giờ dự kiến.
    final rows = ['07:30', '08:30', '09:45', '10:30'].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(rows, orderedEquals([...rows]..sort()));
    expect(find.text('Đo huyết áp'), findsOneWidget);
    expect(find.text('Nguyễn Thị Lan · Phòng 203'), findsNWidgets(2));
    expect(find.text('Quá hạn'), findsOneWidget);
    expect(find.text('Đến giờ'), findsOneWidget);
    expect(find.text('Sắp tới'), findsOneWidget);
    expect(find.text('Hoàn thành'), findsOneWidget);
    expect(find.text('Ca đêm'), findsOneWidget);
    expect(find.text('18:00 – 07:00 · Kết thúc 19/11'), findsOneWidget);
    expect(find.text('Chưa có công việc trong ca này.'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Thứ ba, 17/11, có ca'));
    await tester.pumpAndSettle();
    expect(find.text('Đã đóng'), findsOneWidget);
    expect(find.text('Đo huyết áp'), findsNothing);
  });

  testWidgets('Figma_98_1671_bamCongViec_moChiTietVaGhiNhan', (tester) async {
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
          task(3, 'Hỗ trợ vận động', 'DUE', 78, 'Phạm Minh Đức', '2026-11-18T01:00:00Z'),
        ],
      })
      ..on('GET', '/result-values', 200, <dynamic>[]);
    final cache = CareChecklistCache(NativeDatabase.memory());
    addTearDown(cache.close);
    await home(tester, backend, cache, DateTime.utc(2026, 11, 18, 1));
    await tester.tap(find.text('Đo huyết áp'));
    await tester.pumpAndSettle();
    expect(find.text('Ghi nhận kết quả'), findsOneWidget);
    expect(find.text('Hỗ trợ vận động'), findsNothing);
    await tester.tap(find.text('Ghi nhận kết quả'));
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
    await tester.tap(find.text('Hỗ trợ uống nước'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem kế hoạch chăm sóc'));
    await tester.pumpAndSettle();
    expect(find.text('Kế hoạch chăm sóc'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Báo sự cố'));
    await tester.pumpAndSettle();
    // Màn Báo sự cố 4 bước (BF-06): mở từ công việc thì cụ đã chọn sẵn, vào thẳng bước chọn loại
    expect(find.text('Chuyện gì đã xảy ra?'), findsOneWidget);
  });
}
