import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/incidents/incidents_screen.dart';

import '../../support/fake_backend.dart';

// 007 T037, T042 (US4, US5; FR-045, FR-047, FR-048; BF-06): danh sách có tên cụ, loại, mức; chi tiết trang riêng: ghi
// nhanh diễn biến một chạm, tiếp nhận, đóng cần kết quả, thẻ khẩn cấp (dị ứng, gọi người liên hệ chính).

Future<void> pumpScreen(WidgetTester tester, FakeBackend backend) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: IncidentsScreen(api: backend.client())),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> incident(
  String status,
  String level,
  List<String> commands, {
  List<Object> progressions = const [],
}) => {
  'id': 2,
  'status': status,
  'level': level,
  'wasEmergency': level == 'CRITICAL',
  'currentTypeId': 71,
  'assignee': 'Hoàng Thị Dung',
  'content': {
    'residentId': 9103,
    'incidentTypeId': 71,
    'discoveredAt': '2026-11-26T07:47:00Z',
    'description': 'Cụ trượt chân ở hành lang',
  },
  'progressions': progressions,
  'allowedCommands': commands,
};

void stub(FakeBackend backend) {
  backend
    ..on('GET', '/incident-types', 200, [
      {'id': 71, 'code': 'FALL', 'name': 'Ngã', 'defaultLevel': 'CRITICAL'},
    ])
    ..on('GET', '/progression-types', 200, [
      {'id': 98, 'code': 'FIRST_AID', 'name': 'Sơ cứu, chăm sóc tại chỗ', 'group': 'ACTION'},
      {'id': 99, 'code': 'OTHER_ACTION', 'name': 'Xử lý khác (ghi rõ)', 'group': 'ACTION'},
      {'id': 64, 'code': 'CALL_SUPPORT', 'name': 'Gọi hỗ trợ', 'group': 'NOTIFICATION'},
    ])
    ..on('GET', '/residents', 200, {
      'items': [
        {
          'id': 9103,
          'personalInfo': {'fullName': 'Hoàng Văn Em'},
        },
      ],
    })
    ..on('GET', '/incident-residents', 200, [
      {'id': 9103, 'fullName': 'Hoàng Văn Em', 'roomName': 'Phòng 102', 'floorName': 'Tầng 1'},
    ]);
}

Future<void> openDetail(WidgetTester tester) async {
  await tester.tap(find.text('Hoàng Văn Em'));
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  setUp(() {
    backend = FakeBackend();
    stub(backend);
  });

  testWidgets('FR_045_danhSach_hienTenCuLoaiMuc', (tester) async {
    backend.on('GET', '/incidents', 200, [incident('IN_PROGRESS', 'MEDIUM', [])]);
    await pumpScreen(tester, backend);
    expect(find.text('Hoàng Văn Em'), findsOneWidget);
    expect(find.textContaining('Ngã · 14:47 · Đang xử lý'), findsOneWidget);
    expect(find.text('Trung bình'), findsOneWidget);
  });

  testWidgets('FR_045_tiepNhan_guiLenh', (tester) async {
    backend.on('GET', '/incidents', 200, [incident('NEW', 'MEDIUM', [])]);
    backend.on('GET', '/incidents/2', 200, incident('NEW', 'MEDIUM', ['receive']));
    backend.on('POST', '/incidents/2/receive', 200);
    await pumpScreen(tester, backend);
    await openDetail(tester);
    await tester.tap(find.text('Tiếp nhận xử lý'));
    await tester.pumpAndSettle();
    expect(backend.calls('POST', '/incidents/2/receive').single.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Đã tiếp nhận.'), findsOneWidget);
  });

  testWidgets('FR_045_ghiNhanhDienBien_motCham', (tester) async {
    backend.on('GET', '/incidents', 200, [incident('IN_PROGRESS', 'MEDIUM', [])]);
    backend.on('GET', '/incidents/2', 200, incident('IN_PROGRESS', 'MEDIUM', ['progressions']));
    backend.on('POST', '/incidents/2/progressions', 201);
    await pumpScreen(tester, backend);
    await openDetail(tester);
    await tester.tap(find.text('Đã sơ cứu'));
    await tester.pumpAndSettle();
    expect(jsonDecode(backend.calls('POST', '/incidents/2/progressions').single.body), {
      'progressionTypeId': 98,
      'content': 'Đã sơ cứu tại chỗ',
    });
    expect(find.text('Đã ghi: Đã sơ cứu tại chỗ.'), findsOneWidget);
  });

  testWidgets('FR_045_dong_canKetQua', (tester) async {
    backend.on('GET', '/incidents', 200, [incident('IN_PROGRESS', 'MEDIUM', [])]);
    backend.on('GET', '/incidents/2', 200, incident('IN_PROGRESS', 'MEDIUM', ['close']));
    backend.on('POST', '/incidents/2/close', 200);
    await pumpScreen(tester, backend);
    await openDetail(tester);
    await tester.tap(find.text('Đóng sự cố'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cụ ổn định');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Đóng sự cố'));
    await tester.pumpAndSettle();
    expect(jsonDecode(backend.calls('POST', '/incidents/2/close').single.body), {'resolution': 'Cụ ổn định'});
    expect(find.text('Đã đóng sự cố.'), findsOneWidget);
  });

  testWidgets('FR_047_theKhanCap_diUng_goiNguoiLienHe', (tester) async {
    backend.on('GET', '/incidents', 200, [incident('IN_PROGRESS', 'CRITICAL', [])]);
    backend.on('GET', '/incidents/2', 200, incident('IN_PROGRESS', 'CRITICAL', []));
    backend.on('GET', '/incidents/2/emergency-card', 200, {
      'identification': {'fullName': 'Hoàng Văn Em', 'roomBed': 'P102-G1'},
      'endOfLifeWish': {'notRecorded': true},
      'allergies': [
        {'name': 'Penicillin'},
      ],
      'currentMedications': [],
      'chronicConditions': [],
      'primaryContact': {'fullName': 'Hoàng Thị Én', 'phoneNumber': '0911000103'},
    });
    await pumpScreen(tester, backend);
    await openDetail(tester);
    await tester.tap(find.text('Thẻ khẩn cấp'));
    await tester.pumpAndSettle();
    expect(find.text('Penicillin'), findsOneWidget);
    expect(find.text('Chưa có nguyện vọng'), findsOneWidget);
    expect(find.text('Hoàng Thị Én'), findsOneWidget);
    expect(find.text('Gọi'), findsOneWidget);
  });

  testWidgets('FR_047_theKhanCap_matKetNoi_baoLoi', (tester) async {
    backend.on('GET', '/incidents', 200, [incident('IN_PROGRESS', 'CRITICAL', [])]);
    backend.on('GET', '/incidents/2', 200, incident('IN_PROGRESS', 'CRITICAL', []));
    await pumpScreen(tester, backend);
    await openDetail(tester);
    backend.down = true;
    await tester.tap(find.text('Thẻ khẩn cấp'));
    await tester.pumpAndSettle();
    expect(find.text('Mất kết nối, chưa mở được thẻ khẩn cấp.'), findsOneWidget);
  });

  testWidgets('BR_M05_14_daChuyenVien_baoCuVeKhongCanMoLai', (tester) async {
    final transferred = incident(
      'IN_PROGRESS',
      'MEDIUM',
      ['transfer-out', 'close'],
      progressions: [
        {'id': 1, 'progressionTypeId': 97, 'typeCode': 'TRANSFERRED_OUT', 'occurredAt': '2026-11-26T07:50:00Z'},
      ],
    );
    backend.on('GET', '/incidents', 200, [transferred]);
    backend.on('GET', '/incidents/2', 200, transferred);
    await pumpScreen(tester, backend);
    await openDetail(tester);
    expect(find.textContaining('Cụ đang ở bệnh viện'), findsOneWidget);
    expect(find.text('Chuyển viện'), findsNothing);
  });
}
