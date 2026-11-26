import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/incidents/record_incident_screen.dart';

import '../../support/fake_backend.dart';

// Báo sự cố 4 bước (007 FR-040 → FR-042; BF-06): chọn cụ → chọn loại (ô lớn) → mức, giờ, mô tả → xem lại rồi ghi.
// Mức chọn sẵn theo loại; thấp hơn thì bắt buộc lý do; "Đã xử lý xong" là ghi nhận sau (không báo khẩn, bắt buộc nói đã
// báo người nhà chưa); Quay lại lùi một bước; ghi xong hiện ai đã được báo.

Future<void> pumpScreen(WidgetTester tester, FakeBackend backend, {int? residentId}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<bool>(
                  builder: (_) => RecordIncidentScreen(api: backend.client(), residentId: residentId),
                ),
              ),
              child: const Text('Mở'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Mở'));
  await tester.pumpAndSettle();
}

void stub(FakeBackend backend) {
  backend
    ..on('GET', '/incident-types', 200, [
      {'id': 71, 'code': 'FALL', 'name': 'Ngã', 'defaultLevel': 'CRITICAL', 'allowsNoResident': false},
      {'id': 88, 'code': 'MEDICATION', 'name': 'Sự cố liên quan đến sử dụng thuốc', 'defaultLevel': 'MEDIUM'},
      {'id': 95, 'code': 'FACILITY', 'name': 'Cơ sở vật chất', 'defaultLevel': 'MEDIUM', 'allowsNoResident': true},
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
    ])
    ..on('GET', '/incident-floors', 200, [
      {'id': 9001, 'name': 'Tầng 1', 'current': true},
    ]);
}

void main() {
  late FakeBackend backend;
  setUp(() {
    backend = FakeBackend();
    stub(backend);
  });

  testWidgets('bonBuoc_nga_mucKhanCapMacDinh_guiDungBody_hienDaBaoAi', (tester) async {
    backend.on('POST', '/incidents', 201, {
      'incident': {'id': 12},
    });
    await pumpScreen(tester, backend);
    expect(find.text('Sự cố xảy ra với ai?'), findsOneWidget);
    await tester.tap(find.text('Hoàng Văn Em'));
    await tester.pumpAndSettle();
    expect(find.text('Chuyện gì đã xảy ra?'), findsOneWidget);
    await tester.tap(find.text('Ngã'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Báo ngay bác sĩ trực'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Trượt chân ở hành lang');
    await tester.tap(find.text('Tiếp'));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra rồi ghi'), findsOneWidget);
    await tester.tap(find.text('Ghi sự cố'));
    await tester.pumpAndSettle();

    final post = backend.calls('POST', '/incidents').single;
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(post.headers['Idempotency-Key'], isNotEmpty);
    expect(body['residentId'], 9103);
    expect(body['incidentTypeId'], 71);
    expect(body['level'], 'CRITICAL');
    expect(body['description'], 'Trượt chân ở hành lang');
    expect(body.containsKey('recordedLater'), isFalse);
    expect(find.text('Đã ghi sự cố #12'), findsOneWidget);
    expect(find.textContaining('đã báo bác sĩ trực'), findsOneWidget);
    expect(find.text('Gọi cấp cứu 115'), findsOneWidget);
  });

  testWidgets('chonMucThapHon_batBuocLyDo', (tester) async {
    await pumpScreen(tester, backend, residentId: 9103);
    await tester.tap(find.text('Ngã'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trung bình'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập lý do chọn mức thấp hơn'), findsOneWidget);
    expect(find.text('Kiểm tra rồi ghi'), findsNothing);
  });

  testWidgets('daXuLyXong_ghiNhanSau_batBuocNguoiNha_khongBaoKhan', (tester) async {
    backend.on('POST', '/incidents', 201, {
      'incident': {'id': 13},
    });
    await pumpScreen(tester, backend, residentId: 9103);
    await tester.tap(find.text('Ngã'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đã xử lý xong'));
    await tester.pumpAndSettle();
    expect(find.textContaining('không báo khẩn'), findsWidgets);
    await tester.tap(find.text('Tiếp'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn đã báo người nhà hay chưa'), findsOneWidget);

    await tester.tap(find.text('Đã báo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi nhận'));
    await tester.pumpAndSettle();

    final body = jsonDecode(backend.calls('POST', '/incidents').single.body) as Map<String, dynamic>;
    expect(body['recordedLater'], isTrue);
    expect((body['familyNotice'] as Map)['state'], 'INFORMED');
    expect((body['familyNotice'] as Map)['method'], 'PHONE');
    expect(find.text('Đã ghi nhận sau'), findsOneWidget);
    expect(find.text('Gọi cấp cứu 115'), findsNothing);
  });

  testWidgets('quayLai_luiMotBuoc_khongThoat', (tester) async {
    await pumpScreen(tester, backend, residentId: 9103);
    await tester.tap(find.text('Ngã'));
    await tester.pumpAndSettle();
    expect(find.text('Mức độ'), findsOneWidget);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chuyện gì đã xảy ra?'), findsOneWidget);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Sự cố xảy ra với ai?'), findsOneWidget);
  });

  testWidgets('khongGanCu_chiHienLoaiChoPhep_guiTang', (tester) async {
    backend.on('POST', '/incidents', 201, {
      'incident': {'id': 14},
    });
    await pumpScreen(tester, backend);
    await tester.tap(find.text('Không gắn với cụ nào (đồ đạc, cơ sở vật chất)'));
    await tester.pumpAndSettle();
    expect(find.text('Ngã'), findsNothing);
    await tester.tap(find.text('Cơ sở vật chất'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi sự cố'));
    await tester.pumpAndSettle();
    final body = jsonDecode(backend.calls('POST', '/incidents').single.body) as Map<String, dynamic>;
    expect(body.containsKey('residentId'), isFalse);
    expect(body['floorAreaId'], 9001);
    expect(body['description'], 'Cơ sở vật chất');
  });

  testWidgets('loiBackend_giuBuocXemLai_hienChiTiet', (tester) async {
    backend.on('POST', '/incidents', 422, {'errorCode': 'INVALID_VALUE', 'detail': 'Giờ phát hiện không hợp lệ'});
    await pumpScreen(tester, backend, residentId: 9103);
    await tester.tap(find.text('Ngã'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghi sự cố'));
    await tester.pumpAndSettle();
    expect(find.text('Giờ phát hiện không hợp lệ'), findsOneWidget);
    expect(find.text('Kiểm tra rồi ghi'), findsOneWidget);
  });
}
