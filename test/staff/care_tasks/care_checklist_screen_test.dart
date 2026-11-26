import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/api/api_client.dart';
import 'package:mobile/common/offline/offline_database.dart';
import 'package:mobile/common/offline/offline_queue.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/care_tasks/care_checklist_cache.dart';
import 'package:mobile/staff/care_tasks/care_checklist_links.dart';
import 'package:mobile/staff/care_tasks/care_checklist_repository.dart';
import 'package:mobile/staff/care_tasks/care_checklist_screen.dart';
import 'package:mobile/staff/care_tasks/care_offline_recording.dart';
import '../../support/fake_backend.dart';
import 'care_checklist_cache_test.dart' show FixtureChecklistGateway;

void main() {
  late CareChecklistCache cache;
  late FixtureChecklistGateway gateway;
  late CareChecklistRepository repository;
  setUp(() {
    cache = CareChecklistCache(NativeDatabase.memory());
    gateway = FixtureChecklistGateway();
    repository = CareChecklistRepository(gateway, cache);
    gateway.body['tasks'] = [
      {
        'id': 1,
        'taskType': 'Việc đến hạn',
        'status': 'DUE',
        'residentId': 77,
        'residentCard': {'fullName': 'Người kiểm thử'},
        'allowedCommands': ['notPerform'],
      },
      {
        'id': 2,
        'taskType': 'Việc quá hạn',
        'status': 'OVERDUE',
        'residentId': 77,
        'residentCard': {'fullName': 'Người kiểm thử'},
        'allowedCommands': ['claim'],
      },
    ];
    gateway.body['riskAgreements'] = [
      {
        'residentId': 77,
        'agreements': [
          {'choice': 'Lựa chọn đã trao đổi', 'reviewDate': '2026-11-08'},
        ],
      },
    ];
    gateway.body['nonPerformanceReasonTypes'] = [
      {'id': 1, 'name': 'Người cao tuổi từ chối', 'status': 'ACTIVE', 'fixed': true},
    ];
  });
  tearDown(() => cache.close());
  Future<void> open(WidgetTester tester, String task) async {
    await tester.tap(find.text(task));
    await tester.pumpAndSettle();
  }

  Future<void> view(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CareChecklistScreen(repository: repository, accountId: 1, shiftId: 9),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('FR_030_quaHanLenTruocVaTheHienLuaChon', (tester) async {
    await view(tester);
    expect(tester.getTopLeft(find.text('Việc quá hạn')).dy, lessThan(tester.getTopLeft(find.text('Việc đến hạn')).dy));
    expect(find.text('QUÁ HẠN'), findsOneWidget);
    expect(find.text('BÂY GIỜ'), findsOneWidget);
    await open(tester, 'Việc đến hạn');
    expect(find.text('Lựa chọn đã trao đổi'), findsOneWidget);
  });
  testWidgets('FR_034_hoanThanhNhanhTuChecklistVaTaiLaiTrangThai', (tester) async {
    final simple = {
      'id': 1,
      'taskType': 'Việc cần hoàn thành',
      'status': 'DUE',
      'resultType': 'PERFORMED',
      'allowedCommands': ['record'],
    };
    final measured = {...simple, 'id': 2, 'taskType': 'Đo chỉ số', 'resultType': 'MEASURED_VALUE'};
    gateway.body['tasks'] = [simple, measured];
    await view(tester);
    final quick = find.text('Đánh dấu hoàn thành');
    expect(quick, findsOneWidget);
    await tester.tap(quick);
    await tester.pumpAndSettle();
    expect(find.text('Vừa hoàn thành'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(gateway.recordings, isEmpty);
    gateway.body['tasks'] = [
      {...simple, 'status': 'COMPLETED', 'allowedCommands': <String>[]},
      measured,
    ];
    await tester.tap(find.text('Xác nhận hoàn thành'));
    await tester.pumpAndSettle();
    expect(gateway.recordings.single, isEmpty);
    expect(quick, findsNothing);
  });

  testWidgets('FR_035_hoanThanhTruocDoNgoaiTuyenGiuCaHaiMoc', (tester) async {
    final backend = FakeBackend()..down = true;
    final api = backend.client();
    final db = OfflineDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final deviceTime = DateTime.utc(2026, 11, 6, 4, 5);
    final queue = OfflineQueue(db, api, clock: () => deviceTime);
    repository = CareChecklistRepository(gateway, cache, recorder: CareOfflineRecording(api, queue, 1));
    gateway.body['tasks'] = [
      {
        'id': 1,
        'taskType': 'Việc đã thực hiện',
        'status': 'OVERDUE',
        'resultType': 'PERFORMED',
        'allowedCommands': ['record'],
        'windowFrom': '2026-11-06T01:00:00Z',
      },
    ];
    await repository.load(1, 9);
    gateway.failure = ApiUnreachable();
    await view(tester);
    await tester.tap(find.text('Đánh dấu hoàn thành'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã hoàn thành trước đó'));
    await tester.pumpAndSettle();
    final confirm = find.text('Xác nhận hoàn thành');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('Nhập thời điểm thực tế đã thực hiện.'), findsOneWidget);
    expect(await queue.unsynced(1), isEmpty);
    final performed = find.widgetWithText(TextField, 'Thời điểm thực hiện (dd/MM/yyyy HH:mm)');
    await tester.enterText(performed, '06/11/2026 08:27');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    final row = (await queue.unsynced(1)).single;
    expect(row.deviceTime.toUtc(), deviceTime);
    expect(jsonDecode(row.content), {
      'taskId': 1,
      'action': 'RECORD',
      'recording': {'performedAt': '2026-11-06T01:27:00.000Z'},
    });
    expect(find.textContaining('Chưa đồng bộ'), findsWidgets);
    expect(find.text('Đánh dấu hoàn thành'), findsNothing);
  });
  testWidgets('FR_030_dayDuNguCanhCongViecKhiChu200PhanTram', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    gateway.body['tasks'] = [
      {
        'id': 1,
        'taskType': 'Hỗ trợ uống nước',
        'status': 'OVERDUE',
        'residentId': 77,
        'residentCard': {'fullName': 'Người kiểm thử', 'roomBed': 'Phòng A · Giường 1', 'careNotes': 'Ngồi thẳng'},
        'plannedAt': '2026-11-01T03:00:00Z',
        'windowFrom': '2026-11-01T02:45:00Z',
        'windowTo': '2026-11-01T03:15:00Z',
        'importance': 'IMPORTANT',
        'basis': {'type': 'CARE_PLAN_ITEM', 'id': 8},
        'performer': 'Nhân viên kiểm thử',
        'carryover': 'AWAITING_CONFIRMATION',
      },
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CareChecklistScreen(repository: repository, accountId: 1, shiftId: 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Người kiểm thử · Phòng A · Giường 1 · 10:00'), findsOneWidget);
    await open(tester, 'Hỗ trợ uống nước');
    expect(find.text('Phòng A · Giường 1'), findsOneWidget);
    expect(find.text('Khung giờ: 09:45–10:15'), findsOneWidget);
    expect(find.text('Dự kiến: 01/11/2026 10:00'), findsOneWidget);
    expect(find.text('Quan trọng'), findsOneWidget);
    expect(find.text('Nguồn: Kế hoạch chăm sóc'), findsOneWidget);
    expect(find.text('Phụ trách: Nhân viên kiểm thử'), findsOneWidget);
    expect(find.text('Tồn, chờ xác nhận bàn giao'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('FR_034_sleepFormUsesResultCatalogAndStoresMinutesWithQuality', (tester) async {
    gateway.body['tasks'] = [
      {
        'id': 1,
        'taskType': 'Giấc ngủ',
        'status': 'DUE',
        'resultType': 'SLEEP',
        'allowedCommands': ['record'],
      },
    ];
    gateway.body['resultValues'] = [
      {'type': 'SLEEP_QUALITY', 'code': 'QUIET', 'name': 'Ngủ yên', 'status': 'ACTIVE'},
    ];
    await view(tester);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi nhận kết quả'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Thời gian ngủ (phút)'), '60');
    await tester.tap(find.text('Ngủ yên'));
    await tester.ensureVisible(find.text('Lưu kết quả'));
    await tester.tap(find.text('Lưu kết quả'));
    await tester.pumpAndSettle();
    expect(gateway.recordings.single['numericValue'], 60);
    expect(gateway.recordings.single['codeValue'], 'QUIET');
  });
  testWidgets('FR_035_matMangHienChuaCapNhatVaKhongGuiLenh', (tester) async {
    await repository.load(1, 9);
    gateway.failure = ApiUnreachable();
    await view(tester);
    expect(find.textContaining('Chưa cập nhật'), findsOneWidget);
    await open(tester, 'Việc quá hạn');
    expect(find.text('Nhận công việc'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await open(tester, 'Việc đến hạn');
    expect(find.text('Không thực hiện được…'), findsNothing);
  });
  testWidgets('BR_M15_20_offlineChecklistRecordsIntoSharedQueueAndShowsUnsynced', (tester) async {
    final backend = FakeBackend()..down = true;
    final api = backend.client();
    final db = OfflineDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final queue = OfflineQueue(db, api);
    repository = CareChecklistRepository(gateway, cache, recorder: CareOfflineRecording(api, queue, 1));
    gateway.body['tasks'] = [
      {
        'id': 1,
        'taskType': 'Uống nước',
        'status': 'DUE',
        'resultType': 'ML',
        'allowedCommands': ['record'],
        'residentId': 77,
      },
    ];
    await repository.load(1, 9);
    gateway.failure = ApiUnreachable();
    await view(tester);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi nhận kết quả'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Lượng nước (ml)'), '200');
    await tester.ensureVisible(find.text('Lưu kết quả'));
    await tester.tap(find.text('Lưu kết quả'));
    await tester.pumpAndSettle();
    expect(await queue.unsynced(1), hasLength(1));
    expect(find.textContaining('Chưa đồng bộ'), findsWidgets);
  });
  testWidgets('FR_028a_phaiChonLoaiLyDoTruocKhiLuu', (tester) async {
    await view(tester);
    await open(tester, 'Việc đến hạn');
    await tester.tap(find.text('Không thực hiện được…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu Không thực hiện'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn loại lý do Không thực hiện.'), findsOneWidget);
    expect(find.text('Người cao tuổi từ chối'), findsOneWidget);
  });
  testWidgets('FR_036_loiKhongMatGhiChuVaThuLaiCungUuid', (tester) async {
    gateway.commandFailure = ApiProblem(409, 'CARE_TASK_CLOSED', 'Công việc đã được ghi nhận.');
    await view(tester);
    await open(tester, 'Việc đến hạn');
    await tester.tap(find.text('Không thực hiện được…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Người cao tuổi từ chối'));
    await tester.enterText(find.byType(TextField), 'Lời người cao tuổi đã nói');
    await tester.tap(find.text('Lưu Không thực hiện'));
    await tester.pumpAndSettle();
    expect(find.text('Công việc đã được ghi nhận.'), findsOneWidget);
    expect(find.text('Lời người cao tuổi đã nói'), findsOneWidget);
    await tester.tap(find.text('Lưu Không thực hiện'));
    await tester.pumpAndSettle();
    expect(gateway.attempts.length, 2);
    expect(
      gateway.attempts.first.last,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(gateway.attempts.first.last, gateway.attempts.last.last);
  });
  testWidgets('FR_038_ghiNhanMlTheoSnapshotVaGiuGiaTriKhiLoi', (tester) async {
    gateway.body['tasks'] = [
      {
        'id': 1,
        'taskType': 'Tên loại đã đổi',
        'resultType': 'ML',
        'status': 'DUE',
        'allowedCommands': ['record'],
      },
    ];
    gateway.commandFailure = ApiProblem(409, 'CARE_TASK_CLOSED', 'Công việc đã được ghi nhận.');
    await view(tester);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi nhận kết quả'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Lượng nước (ml)'), '200');
    await tester.tap(find.text('Lưu kết quả'));
    await tester.pumpAndSettle();
    expect(gateway.recordings.single, {'numericValue': 200});
    expect(find.text('200'), findsOneWidget);
    expect(find.text('Công việc đã được ghi nhận.'), findsOneWidget);
  });
  testWidgets('FR_035_guiGioThucHienTheoGioVietNam', (tester) async {
    gateway.body['tasks'] = [
      {
        'id': 1,
        'taskType': 'Uống nước kiểm thử',
        'resultType': 'ML',
        'status': 'DUE',
        'allowedCommands': ['record'],
      },
    ];
    await view(tester);
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi nhận kết quả'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Lượng nước (ml)'), '200');
    await tester.enterText(
      find.widgetWithText(TextField, 'Thời điểm thực hiện (dd/MM/yyyy HH:mm)'),
      '01/11/2026 10:15',
    );
    await tester.tap(find.text('Lưu kết quả'));
    await tester.pumpAndSettle();
    expect(gateway.recordings.single, {'numericValue': 200, 'performedAt': '2026-11-01T03:15:00.000Z'});
  });
  testWidgets('BR_M15_20_doiTaiKhoanXoaHienThiCuVaBoResponseCu', (tester) async {
    await view(tester);
    final oldRequest = Completer<Map<String, dynamic>>();
    final newRequest = Completer<Map<String, dynamic>>();
    gateway.loader = (id) => id == 9 ? oldRequest.future : newRequest.future;
    await tester.tap(find.byTooltip('Tải lại checklist'));
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CareChecklistScreen(repository: repository, accountId: 2, shiftId: 10),
      ),
    );
    await tester.pump();
    expect(find.text('Việc đến hạn'), findsNothing);
    newRequest.complete({
      'shiftId': 10,
      'loadedAt': '2026-11-01T04:00:00Z',
      'tasks': [
        {'id': 10, 'taskType': 'Việc tài khoản mới', 'status': 'DUE'},
      ],
    });
    await tester.pumpAndSettle();
    expect(find.text('Việc tài khoản mới'), findsOneWidget);
    oldRequest.complete(gateway.body);
    await tester.pumpAndSettle();
    expect(find.text('Việc tài khoản mới'), findsOneWidget);
    expect(find.text('Việc đến hạn'), findsNothing);
  });
  testWidgets('FR_030_hienThuocCanhBaoVaBanGiao', (tester) async {
    gateway.body['tasks'] = [];
    gateway.body['medicationDoses'] = [
      {
        'doseKey': 'dose-1',
        'medication': {'description': 'Liều thuốc kiểm thử'},
      },
    ];
    gateway.body['openAlerts'] = [
      {'id': 22, 'residentId': 77},
    ];
    gateway.body['handoverTasks'] = {'receiveAtStart': true, 'prepareAtEnd': true};
    await view(tester);
    expect(find.text('Liều thuốc kiểm thử'), findsOneWidget);
    expect(find.text('Cảnh báo #22'), findsOneWidget);
    expect(find.text('Nhận bàn giao đầu ca'), findsOneWidget);
    expect(find.text('Lập bàn giao cuối ca'), findsOneWidget);
  });

  group('Lối đi từ Checklist ca', () {
    late List<String> opened;
    CareChecklistLinks links() => CareChecklistLinks(
      openHandover: (context, shiftId) async => opened.add('handover:$shiftId'),
      openPlans: (context, residents) async =>
          opened.add('plans:${residents.map((r) => '${r['id']} ${r['name']}').join(',')}'),
      reportIncident: (context, residentId) async {
        opened.add('incident:$residentId');
        return false;
      },
    );
    Future<void> withLinks(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: CareChecklistScreen(repository: repository, accountId: 1, shiftId: 9, links: links()),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() => opened = []);

    testWidgets('khongConDaiTienTrinhCa', (tester) async {
      await withLinks(tester);
      expect(find.text('Tiến trình ca'), findsNothing);
      expect(find.text('Báo sự cố'), findsNothing);
    });

    testWidgets('chiTietCongViec_xemKeHoachVaBaoSuCoCuaNguoiCaoTuoi', (tester) async {
      await withLinks(tester);
      await open(tester, 'Việc đến hạn');
      await tester.tap(find.text('Xem kế hoạch chăm sóc'));
      await tester.tap(find.text('Báo sự cố'));
      await tester.pumpAndSettle();
      expect(opened, ['plans:77 Người kiểm thử', 'incident:77']);
    });

    testWidgets('dongBanGiao_moManBanGiaoCuaCa', (tester) async {
      gateway.body['handoverTasks'] = {'prepareAtEnd': true};
      await withLinks(tester);
      await tester.tap(find.text('Lập bàn giao cuối ca'));
      await tester.pumpAndSettle();
      expect(opened, ['handover:9']);
    });

    testWidgets('khongCoLinks_khongCoNutKeHoach', (tester) async {
      await view(tester);
      await open(tester, 'Việc đến hạn');
      expect(find.text('Xem kế hoạch chăm sóc'), findsNothing);
    });
  });
}
