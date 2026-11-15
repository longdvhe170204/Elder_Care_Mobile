import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/api/api_client.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/notifications/family_inbox_screen.dart';

import '../../support/fake_backend.dart';

// 013 T019, 009 (spec 013 FR-017, FR-030): người đại diện mở thông báo RECIPIENT_CONFIRMATION_REQUESTED (nguồn
// M12.RECIPIENT_CONFIRMATION, mã là mã yêu cầu) rồi vào màn xác nhận người nhận để thấy người nhận trước khi quyết định.

Map<String, dynamic> notification({Map<String, dynamic>? sourceRecord}) => {
  'id': 1,
  'level': 'MEDIUM',
  'eventType': 'RECIPIENT_CONFIRMATION_REQUESTED',
  'title': 'Có yêu cầu xác nhận người nhận đồ gửi',
  'content': const <Map<String, dynamic>>[],
  'hiddenParts': const <String>[],
  'identityOnly': false,
  'status': 'SENT',
  'sentAt': '2026-11-15T02:00:00Z',
  'viewedAt': null,
  'acknowledgedAt': null,
  'sourceRecord': sourceRecord,
};

const _confirmationSource = {'type': 'M12.RECIPIENT_CONFIRMATION', 'id': '61', 'canOpen': true};

const _request = {
  'id': 61,
  'recipientName': 'Trần Thị N',
  'recipientIdDocument': '999',
  'belongingIds': [90, 91],
  'status': 'PENDING_CONFIRMATION',
};

FakeBackend backend(Map<String, dynamic>? sourceRecord) {
  final n = notification(sourceRecord: sourceRecord);
  return FakeBackend()
    ..on('GET', '/residents', 403, {'errorCode': 'PERMISSION_DENIED'})
    ..on('GET', '/me/notifications', 200, {
      'items': [n],
      'unreadCount': 1,
      'unacknowledgedUrgentCount': 0,
      'nextCursor': null,
    })
    ..on('GET', '/me/notifications/1', 200, n)
    ..on('GET', '/family-portal/recipient-confirmations/61', 200, _request);
}

Future<void> openNotification(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: FamilyInboxScreen(api: api)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Có yêu cầu xác nhận người nhận đồ gửi').first);
  await tester.pumpAndSettle();
}

Finder button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

void main() {
  testWidgets('FR_017_thongBaoYeuCauXacNhan_moManXacNhanNguoiNhan', (tester) async {
    await openNotification(tester, backend(_confirmationSource).client());

    await tester.ensureVisible(button('Xem yêu cầu xác nhận'));
    await tester.pumpAndSettle();
    await tester.tap(button('Xem yêu cầu xác nhận'));
    await tester.pumpAndSettle();

    expect(find.text('Người nhận: Trần Thị N'), findsOneWidget);
    expect(find.text('Xác nhận người nhận'), findsOneWidget);
  });

  testWidgets('FR_017_nguonKhacHoacKhongMoDuoc_khongCoNut', (tester) async {
    await openNotification(tester, backend({'type': 'M12.BELONGING', 'id': '61', 'canOpen': true}).client());
    expect(button('Xem yêu cầu xác nhận'), findsNothing);

    await openNotification(tester, backend({..._confirmationSource, 'canOpen': false}).client());
    expect(button('Xem yêu cầu xác nhận'), findsNothing);
  });
}
