import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/api/api_client.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/admissions/change_confirmation_screen.dart';
import 'package:mobile/family/notifications/family_inbox_screen.dart';

import '../../support/fake_backend.dart';

// 004 T120 (FR-043c): người đại diện xem đề nghị thay đổi lưu trú kèm chi phí, đồng ý hoặc không đồng ý (bắt buộc lý
// do); mở từ thông báo RESIDENCY_CHANGE_CONFIRMATION_REQUESTED (nguồn M02.CHANGE_CONFIRMATION). Chỉ trực tuyến.

const _path = '/family-portal/residency-change-confirmations';

const _item = {
  'id': 7,
  'approvalRequestId': 12,
  'residentId': 5,
  'status': 'AWAITING',
  'sentAt': '2026-11-20T02:00:00Z',
  'changeTypes': ['CARE_LEVEL'],
  'previousValue': {'careLevel': 'BASIC'},
  'newValue': {'careLevel': 'SPECIAL'},
  'costImpact': [
    {'item': 'CARE_SERVICE', 'previousUnitPrice': 3000000, 'newUnitPrice': 9000000},
  ],
  'requestedEffectiveDate': '2026-12-01',
  'reason': 'Theo đánh giá lại của Bác sĩ',
};

FakeBackend backend() => FakeBackend()..on('GET', _path, 200, [_item]);

Future<void> pump(WidgetTester tester, ApiClient api, {int id = 7}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ChangeConfirmationScreen(api: api, confirmationId: id),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR_043c_hienNoiDungThayDoi_chiPhi_ngayHieuLuc', (tester) async {
    await pump(tester, backend().client());
    expect(find.text('Mức chăm sóc: Cơ bản → Đặc biệt'), findsOneWidget);
    expect(find.text('Dịch vụ chăm sóc: 3.000.000 đồng → 9.000.000 đồng'), findsOneWidget);
    expect(find.text('Từ ngày 01/12/2026'), findsOneWidget);
    expect(find.text('Lý do: Theo đánh giá lại của Bác sĩ'), findsOneWidget);
    expect(find.text('Đồng ý'), findsOneWidget);
  });

  testWidgets('FR_043c_dongY_guiLenhAccept_kemIdempotencyKey', (tester) async {
    final b = backend()..on('POST', '$_path/7/accept', 200);
    await pump(tester, b.client());
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    expect(b.calls('POST', '$_path/7/accept').single.headers['Idempotency-Key'], isNotEmpty);
    expect(find.text('Đã gửi đồng ý. Viện sẽ trình Quản lý viện duyệt. Viện sẽ hẹn bạn ký phụ lục.'), findsOneWidget);
    expect(find.text('Đồng ý'), findsNothing);
  });

  testWidgets('FR_043c_khongDongY_batBuocLyDo', (tester) async {
    final b = backend()..on('POST', '$_path/7/decline', 200);
    await pump(tester, b.client());
    await tester.tap(find.text('Không đồng ý'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Gửi không đồng ý'));
    await tester.tap(find.text('Gửi không đồng ý'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập lý do không đồng ý.'), findsOneWidget);
    expect(b.calls('POST', '$_path/7/decline'), isEmpty);

    await tester.enterText(find.byKey(const Key('decline-reason')), 'Gia đình muốn giữ mức cũ');
    await tester.tap(find.text('Gửi không đồng ý'));
    await tester.pumpAndSettle();
    final body = jsonDecode(b.calls('POST', '$_path/7/decline').single.body) as Map<String, dynamic>;
    expect(body['reason'], 'Gia đình muốn giữ mức cũ');
  });

  testWidgets('FR_043c_deNghiKhongConCho_baoVaAnNut', (tester) async {
    await pump(tester, backend().client(), id: 99);
    expect(find.text('Đề nghị này không còn chờ xác nhận (đã trả lời hoặc viện đã sửa nội dung).'), findsOneWidget);
    expect(find.text('Đồng ý'), findsNothing);
  });

  testWidgets('FR_043c_thongBaoDeNghiXacNhan_moManXacNhan', (tester) async {
    final n = {
      'id': 1,
      'level': 'LOW',
      'eventType': 'RESIDENCY_CHANGE_CONFIRMATION_REQUESTED',
      'title': 'Đề nghị xác nhận điều chỉnh hợp đồng',
      'content': const <Map<String, dynamic>>[],
      'hiddenParts': const <String>[],
      'identityOnly': false,
      'status': 'SENT',
      'sentAt': '2026-11-20T02:00:00Z',
      'viewedAt': null,
      'acknowledgedAt': null,
      // Backend 009 hiện luôn trả canOpen false; nút vẫn phải hiện
      'sourceRecord': {'type': 'M02.CHANGE_CONFIRMATION', 'id': '7', 'canOpen': false},
    };
    final b = backend()
      ..on('GET', '/residents', 403, {'errorCode': 'PERMISSION_DENIED'})
      ..on('GET', '/me/notifications', 200, {
        'items': [n],
        'unreadCount': 1,
        'unacknowledgedUrgentCount': 0,
        'nextCursor': null,
      })
      ..on('GET', '/me/notifications/1', 200, n);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: FamilyInboxScreen(api: b.client())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đề nghị xác nhận điều chỉnh hợp đồng').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Xem chi tiết thay đổi'));
    await tester.tap(find.text('Xem chi tiết thay đổi'));
    await tester.pumpAndSettle();
    expect(find.text('Mức chăm sóc: Cơ bản → Đặc biệt'), findsOneWidget);
  });

  // 004 M3: thông báo gửi duyệt, kết quả, phụ lục đã áp dụng (nguồn M02.RESIDENCY_CHANGE) mở danh sách đề nghị đã gửi
  for (final type in ['RESIDENCY_CHANGE_SUBMITTED', 'RESIDENCY_CHANGE_OUTCOME', 'ADDENDUM_APPLIED']) {
    testWidgets('M3_${type}_moDanhSachDeNghiDaGui', (tester) async {
      final n = {
        'id': 2,
        'level': 'LOW',
        'eventType': type,
        'title': 'Điều chỉnh hợp đồng $type',
        'content': const <Map<String, dynamic>>[],
        'hiddenParts': const <String>[],
        'identityOnly': false,
        'status': 'SENT',
        'sentAt': '2026-11-20T02:00:00Z',
        'viewedAt': null,
        'acknowledgedAt': null,
        'sourceRecord': {'type': 'M02.RESIDENCY_CHANGE', 'id': '12', 'canOpen': false},
      };
      final b = backend()
        ..on('GET', '/residents', 200, {
          'items': [
            {
              'id': 5,
              'personalInfo': {'fullName': 'Nguyễn Thị Lan'},
            },
          ],
        })
        ..on('GET', '/family-portal/residents/5/contract', 200, {'contracts': []})
        ..on('GET', '/me/notifications', 200, {
          'items': [n],
          'unreadCount': 1,
          'unacknowledgedUrgentCount': 0,
          'nextCursor': null,
        })
        ..on('GET', '/me/notifications/2', 200, n);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: FamilyInboxScreen(api: b.client())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Điều chỉnh hợp đồng $type').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Xem đề nghị đã gửi'));
      await tester.tap(find.text('Xem đề nghị đã gửi'));
      await tester.pumpAndSettle();
      expect(find.text('Bạn chưa gửi đề nghị điều chỉnh hợp đồng nào.'), findsOneWidget);
    });
  }
}
