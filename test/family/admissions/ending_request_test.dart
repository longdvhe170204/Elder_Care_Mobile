import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/admissions/ending_request_screen.dart';
import 'package:mobile/family/notifications/family_inbox_screen.dart';

import '../../support/fake_backend.dart';

// Demo 2026-11-26 (E; api-004 tag residency-ending): người đại diện gửi yêu cầu kết thúc lưu trú, xem trạng thái, hủy khi
// còn chờ xử lý; mỗi người cao tuổi một yêu cầu đang chờ nên đang chờ thì không hiện form.

const _path = '/family-portal/residents/5/residency-ending-requests';

Map<String, dynamic> request({String status = 'PENDING', String? decisionReason}) => {
  'id': 7,
  'residentId': 5,
  'residentName': 'Nguyễn Văn A',
  'endCase': 'CONTRACT_EXPIRED',
  'expectedEndDate': '2026-11-30',
  'reason': 'Gia đình đón về',
  'status': status,
  'createdAt': '2026-11-20T02:00:00Z',
  'decisionReason': decisionReason,
};

Future<void> pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: screen));
  await tester.pumpAndSettle();
}

Future<void> pumpScreen(WidgetTester tester, FakeBackend backend) => pump(
  tester,
  Scaffold(
    body: EndingRequestScreen(api: backend.client(), residentId: 5, today: DateTime(2026, 11, 20)),
  ),
);

void main() {
  testWidgets('thieuTruong_baoTaiO_vaChuaGui', (tester) async {
    final backend = FakeBackend()..on('GET', _path, 200, <Object>[]);
    await pumpScreen(tester, backend);

    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();

    expect(find.text('Chọn trường hợp'), findsOneWidget);
    expect(find.text('Nhập ngày kết thúc mong muốn'), findsOneWidget);
    expect(find.text('Nhập lý do'), findsOneWidget);
    expect(backend.calls('POST', _path), isEmpty);
  });

  testWidgets('guiSauKhiXacNhan_roiHienDangCho', (tester) async {
    var sent = false;
    final backend = FakeBackend()
      ..onRequest('GET', _path, (_) => sent ? [request()] : <Object>[])
      ..onRequest('POST', _path, (_) {
        sent = true;
        return request();
      });
    await pumpScreen(tester, backend);

    await tester.tap(find.text('Trường hợp kết thúc'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hết hạn hợp đồng').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Ngày kết thúc mong muốn (dd/MM/yyyy)'), '30/11/2026');
    await tester.enterText(find.widgetWithText(TextField, 'Lý do'), 'Gia đình đón về');
    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();
    expect(backend.calls('POST', _path), isEmpty);
    await tester.tap(find.text('Xác nhận gửi'));
    await tester.pumpAndSettle();

    final call = backend.calls('POST', _path).single;
    expect(jsonDecode(call.body), {
      'endCase': 'CONTRACT_EXPIRED',
      'expectedEndDate': '2026-11-30',
      'reason': 'Gia đình đón về',
    });
    expect(call.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Đang chờ viện xử lý'), findsOneWidget);
    expect(find.text('Gửi yêu cầu'), findsNothing);
  });

  testWidgets('dangCho_huySauKhiXacNhan', (tester) async {
    var cancelled = false;
    final backend = FakeBackend()
      ..onRequest('GET', _path, (_) => [request(status: cancelled ? 'CANCELLED' : 'PENDING')])
      ..onRequest('POST', '/family-portal/residency-ending-requests/7/cancel', (_) {
        cancelled = true;
        return request(status: 'CANCELLED');
      });
    await pumpScreen(tester, backend);

    await tester.tap(find.text('Hủy yêu cầu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận hủy'));
    await tester.pumpAndSettle();

    expect(backend.calls('POST', '/family-portal/residency-ending-requests/7/cancel'), hasLength(1));
    expect(find.text('Đã hủy'), findsOneWidget);
    expect(find.text('Gửi yêu cầu'), findsOneWidget);
  });

  testWidgets('biTuChoi_hienLyDo', (tester) async {
    final backend = FakeBackend()
      ..on('GET', _path, 200, [request(status: 'REJECTED', decisionReason: 'Cần trao đổi thêm')]);
    await pumpScreen(tester, backend);

    expect(find.text('Viện từ chối'), findsOneWidget);
    expect(find.text('Lý do từ chối: Cần trao đổi thêm'), findsOneWidget);
  });

  testWidgets('thongBao_moManYeuCauKetThuc', (tester) async {
    final n = {
      'id': 1,
      'level': 'MEDIUM',
      'eventType': 'M02_ENDING_REQUEST_REJECTED',
      'title': 'Yêu cầu kết thúc lưu trú',
      'content': const [
        {'informationType': 'GENERAL', 'content': 'Viện từ chối yêu cầu.'},
      ],
      'hiddenParts': const <String>[],
      'identityOnly': false,
      'status': 'SENT',
      'sentAt': '2026-11-20T02:00:00Z',
      'viewedAt': null,
      'acknowledgedAt': null,
      'sourceRecord': {'type': 'M02.ENDING_REQUEST', 'id': '7', 'canOpen': false},
    };
    final backend = FakeBackend()
      ..on('GET', '/me/notifications', 200, {
        'items': [n],
        'unreadCount': 1,
        'unacknowledgedUrgentCount': 0,
        'nextCursor': null,
      })
      ..on('GET', '/me/notifications/1', 200, n)
      ..on('GET', '/family-portal/residents', 200, [
        {'residentId': 5, 'representative': true},
      ])
      ..on('GET', _path, 200, [request(status: 'REJECTED', decisionReason: 'Cần trao đổi thêm')]);
    await pump(tester, Scaffold(body: FamilyInboxScreen(api: backend.client())));
    await tester.tap(find.text('Yêu cầu kết thúc lưu trú').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Xem yêu cầu kết thúc lưu trú'));
    await tester.pumpAndSettle();

    expect(find.text('Viện từ chối'), findsOneWidget);
  });
}
