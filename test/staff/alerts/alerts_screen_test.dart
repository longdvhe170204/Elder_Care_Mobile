import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/alerts/alerts_screen.dart';

import '../../support/fake_backend.dart';

// 007 T031 (US3; FR-027, FR-029, FR-033, FR-036; BR-M05-30, 31; BF-06): danh sách có tên người cao tuổi và tên loại tiếng
// Việt; chi tiết trang riêng có nơi đã chọn, GPS, Tiếp nhận, Đã tới nơi, Gọi 115; chuyển sự cố hỏi loại bằng ô lớn;
// đóng cần kết quả; mất kết nối không gửi lệnh.

final dialed = <String>[];

Future<void> pumpScreen(WidgetTester tester, FakeBackend backend) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AlertsScreen(
          api: backend.client(),
          refreshEvery: const Duration(hours: 1),
          dial: (phone) async {
            dialed.add(phone);
            return true;
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openDetail(WidgetTester tester) async {
  await tester.tap(find.text('Nguyễn Thị An'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> sos(String status, List<String> commands, {Map<String, dynamic>? location}) => {
  'id': 5,
  'residentId': 9001,
  'type': 'RESIDENT_HELP_REQUEST',
  'origin': 'SOS',
  'level': 'CRITICAL',
  'status': status,
  'chosenPlace': 'CORRIDOR',
  'floorName': 'Tầng 1',
  'firstAt': '2026-11-26T07:28:00Z',
  'latestAt': '2026-11-26T07:38:00Z',
  'sources': [
    {'sourceType': 'M05.SOS_PRESS', 'level': 'CRITICAL'},
    {'sourceType': 'M05.SOS_PRESS', 'level': 'CRITICAL'},
  ],
  'latestLocation': location,
  'allowedCommands': commands,
};

void stubResidents(FakeBackend backend) {
  backend.on('GET', '/residents', 200, {
    'items': [
      {
        'id': 9001,
        'personalInfo': {'fullName': 'Nguyễn Thị An'},
      },
    ],
  });
  backend.on('GET', '/incident-residents', 200, [
    {'id': 9001, 'fullName': 'Nguyễn Thị An', 'roomName': 'Phòng 101', 'floorName': 'Tầng 1'},
  ]);
}

void main() {
  late FakeBackend backend;
  setUp(() {
    backend = FakeBackend();
    dialed.clear();
    stubResidents(backend);
  });

  testWidgets('FR_027_danhSach_hienTenCuVaTenLoaiTiengViet', (tester) async {
    backend.on('GET', '/alerts', 200, [sos('NEW', [])]);
    await pumpScreen(tester, backend);
    expect(find.text('Nguyễn Thị An'), findsOneWidget);
    expect(find.textContaining('Người cao tuổi bấm nút SOS'), findsOneWidget);
    expect(find.textContaining('RESIDENT_HELP_REQUEST'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FR_029_chiTiet_noiDaChon_tiepNhan_guiKemIdempotencyKey', (tester) async {
    backend.on('GET', '/alerts', 200, [sos('NEW', [])]);
    backend.on('GET', '/alerts/5', 200, sos('NEW', ['receive', 'call-115']));
    backend.on('POST', '/alerts/5/receive', 200);
    await pumpScreen(tester, backend);
    await openDetail(tester);
    expect(find.text('Nơi đã chọn: Hành lang'), findsOneWidget);
    expect(find.text('Báo 2 lần, gần nhất 14:38'), findsOneWidget);

    await tester.tap(find.text('Tiếp nhận'));
    await tester.pumpAndSettle();
    expect(backend.calls('POST', '/alerts/5/receive').single.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Đã tiếp nhận.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('BR_M05_30_daToiNoi_BR_M05_31_goi115', (tester) async {
    backend.on('GET', '/alerts', 200, [sos('IN_PROGRESS', [])]);
    backend.on('GET', '/alerts/5', 200, sos('IN_PROGRESS', ['mark-arrived', 'call-115']));
    backend.on('POST', '/alerts/5/mark-arrived', 200);
    backend.on('POST', '/alerts/5/call-115', 201, {'id': 7});
    await pumpScreen(tester, backend);
    await openDetail(tester);

    await tester.tap(find.text('Đã tới nơi'));
    await tester.pumpAndSettle();
    expect(backend.calls('POST', '/alerts/5/mark-arrived'), hasLength(1));

    await tester.tap(find.text('Gọi cấp cứu 115'));
    await tester.pumpAndSettle();
    expect(backend.calls('POST', '/alerts/5/call-115'), hasLength(1));
    expect(dialed, ['115']);
    expect(find.text('Đã gọi được'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FR_047h_coGps_hienChiDuong', (tester) async {
    final location = {
      'latitude': 21.0,
      'longitude': 105.8,
      'accuracyMeters': 12.4,
      'measuredAt': '2026-11-26T07:41:00Z',
    };
    backend.on('GET', '/alerts', 200, [sos('IN_PROGRESS', [])]);
    backend.on('GET', '/alerts/5', 200, sos('IN_PROGRESS', [], location: location));
    await pumpScreen(tester, backend);
    await openDetail(tester);
    expect(find.text('Vị trí GPS · sai số 12 m'), findsOneWidget);
    expect(find.text('Chỉ đường'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FR_029_chuyenSuCo_chonLoaiBangO_guiLoai', (tester) async {
    backend.on('GET', '/alerts', 200, [sos('IN_PROGRESS', [])]);
    backend.on('GET', '/alerts/5', 200, sos('IN_PROGRESS', ['convert-to-incident']));
    backend.on('GET', '/incident-types', 200, [
      {'id': 71, 'code': 'FALL', 'name': 'Ngã', 'defaultLevel': 'CRITICAL'},
      {'id': 88, 'code': 'MEDICATION', 'name': 'Sự cố liên quan đến sử dụng thuốc', 'defaultLevel': 'MEDIUM'},
    ]);
    backend.on('POST', '/alerts/5/convert-to-incident', 201, {'id': 3});
    backend.on('GET', '/progression-types', 200, []);
    backend.on('GET', '/incidents/3', 200, {
      'id': 3,
      'status': 'NEW',
      'level': 'CRITICAL',
      'currentTypeId': 71,
      'content': {'residentId': 9001, 'incidentTypeId': 71, 'discoveredAt': '2026-11-26T07:28:00Z'},
      'progressions': [],
      'allowedCommands': ['receive'],
    });
    backend.on('POST', '/incidents/3/receive', 200);
    await pumpScreen(tester, backend);
    await openDetail(tester);

    await tester.tap(find.text('Chuyển thành sự cố'));
    await tester.pumpAndSettle();
    expect(find.text('Chuyện gì đã xảy ra?'), findsOneWidget);
    await tester.tap(find.text('Ngã'));
    await tester.pumpAndSettle();

    expect(jsonDecode(backend.calls('POST', '/alerts/5/convert-to-incident').single.body), {'incidentTypeId': 71});
    // Mở thẳng sự cố vừa tạo và nhận xử lý luôn
    expect(find.text('Sự cố #3'), findsOneWidget);
    expect(backend.calls('POST', '/incidents/3/receive'), hasLength(1));
    expect(find.text('Đã chuyển thành sự cố, bạn là người xử lý.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FR_087_hienDanhSachTheoDoi', (tester) async {
    backend.on('GET', '/alerts', 200, [sos('IN_PROGRESS', [])]);
    backend.on('GET', '/alerts/5', 200, {
      ...sos('IN_PROGRESS', ['follow-up']),
      'followUps': [
        {'content': 'Cụ cần hỗ trợ uống nước', 'at': '2026-11-26T09:58:00Z', 'recordedBy': 'Hoàng Thị Dung'},
      ],
    });
    await pumpScreen(tester, backend);
    await openDetail(tester);
    expect(find.text('Theo dõi'), findsOneWidget);
    expect(find.text('16:58 · Hoàng Thị Dung: Cụ cần hỗ trợ uống nước'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FR_029_dong_canKetQua', (tester) async {
    backend.on('GET', '/alerts', 200, [sos('IN_PROGRESS', [])]);
    backend.on('GET', '/alerts/5', 200, sos('IN_PROGRESS', ['close']));
    backend.on('POST', '/alerts/5/close', 200);
    await pumpScreen(tester, backend);
    await openDetail(tester);

    await tester.tap(find.text('Đóng cảnh báo'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Đóng cảnh báo');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'Cụ ổn, đã đỡ về phòng');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(jsonDecode(backend.calls('POST', '/alerts/5/close').single.body), {'resolution': 'Cụ ổn, đã đỡ về phòng'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('FR_050_matKetNoi_lenhKhongDuocGui', (tester) async {
    backend.on('GET', '/alerts', 200, [sos('NEW', [])]);
    backend.on('GET', '/alerts/5', 200, sos('NEW', ['receive']));
    await pumpScreen(tester, backend);
    await openDetail(tester);
    backend.down = true;
    await tester.tap(find.text('Tiếp nhận'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mất kết nối'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
