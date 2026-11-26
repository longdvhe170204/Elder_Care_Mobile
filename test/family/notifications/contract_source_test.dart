import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/api/api_client.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/admissions/contract_screen.dart';
import 'package:mobile/family/notifications/family_inbox_screen.dart';

import '../../support/fake_backend.dart';

// Demo 2026-11-25 (004 FR-026 bổ sung): người đại diện nhận thông báo hợp đồng sắp hết hạn, ngắn ngày tới hạn, quá hạn
// (nguồn M02.CONTRACT_*) thì có nút mở màn Hợp đồng; backend 009 chưa tính canOpen cho nguồn này nên luôn có nút.

Map<String, dynamic> notification(String type) => {
  'id': 1,
  'level': 'MEDIUM',
  'eventType': 'M02_FAMILY_$type',
  'title': 'Hợp đồng lưu trú',
  'content': const [
    {'informationType': 'CONTRACT', 'content': 'Hợp đồng lưu trú của Nguyễn Văn A sẽ hết hạn ngày 20/12/2026.'},
  ],
  'hiddenParts': const <String>[],
  'identityOnly': false,
  'status': 'SENT',
  'sentAt': '2026-11-20T02:00:00Z',
  'viewedAt': null,
  'acknowledgedAt': null,
  'sourceRecord': {'type': 'M02.$type', 'id': '33', 'canOpen': false},
};

Future<void> openNotification(WidgetTester tester, ApiClient api) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: FamilyInboxScreen(api: api)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Hợp đồng lưu trú').first);
  await tester.pumpAndSettle();
}

Finder button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

void main() {
  for (final type in ['CONTRACT_EXPIRING', 'SHORT_TERM_CONTRACT', 'CONTRACT_OVERDUE']) {
    testWidgets('FR_026_thongBao_${type}_coNutXemHopDong', (tester) async {
      final n = notification(type);
      final api =
          (FakeBackend()
                ..on('GET', '/residents', 403, {'errorCode': 'PERMISSION_DENIED'})
                ..on('GET', '/me/notifications', 200, {
                  'items': [n],
                  'unreadCount': 1,
                  'unacknowledgedUrgentCount': 0,
                  'nextCursor': null,
                })
                ..on('GET', '/me/notifications/1', 200, n))
              .client();
      await openNotification(tester, api);
      await tester.ensureVisible(button('Xem hợp đồng'));
      await tester.pumpAndSettle();
      await tester.tap(button('Xem hợp đồng'));
      await tester.pumpAndSettle();
      expect(find.byType(ContractScreen), findsOneWidget);
    });
  }
}
