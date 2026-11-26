import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/api/api_client.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/charges/family_costs_screen.dart';
import 'package:mobile/family/notifications/family_inbox_screen.dart';

import '../../support/fake_backend.dart';

// Demo 2026-11-25: thông báo bảng chi phí đã chốt (nguồn M11.COST_STATEMENT, mã là mã bảng) có nút mở màn Chi phí của
// đúng người cao tuổi; thông báo không mang mã người cao tuổi nên app tìm bảng đó trong các người cao tuổi mình theo dõi.

final _notice = {
  'id': 1,
  'level': 'MEDIUM',
  'eventType': 'COST_STATEMENT_FINALIZED',
  'title': 'Chi phí',
  'content': const [
    {'informationType': 'COSTS', 'content': 'Bảng chi phí kỳ cuối tháng 11/2026 đã chốt: tổng 1.550.000 đ.'},
  ],
  'hiddenParts': const <String>[],
  'identityOnly': false,
  'status': 'SENT',
  'sentAt': '2026-11-25T02:00:00Z',
  'viewedAt': null,
  'acknowledgedAt': null,
  'sourceRecord': {'type': 'M11.COST_STATEMENT', 'id': '31', 'canOpen': false},
};

Finder button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton));

void main() {
  testWidgets('FR_037_thongBaoChotBang_moManChiPhiDungNguoiCaoTuoi', (tester) async {
    final ApiClient api =
        (FakeBackend()
              ..on('GET', '/residents', 403, {'errorCode': 'PERMISSION_DENIED'})
              ..on('GET', '/me/notifications', 200, {
                'items': [_notice],
                'unreadCount': 1,
                'unacknowledgedUrgentCount': 0,
                'nextCursor': null,
              })
              ..on('GET', '/me/notifications/1', 200, _notice)
              ..on('GET', '/family-portal/residents', 200, [
                {'residentId': 5, 'fullName': 'Nguyễn Văn A'},
                {'residentId': 7, 'fullName': 'Trần Thị B'},
              ])
              ..on('GET', '/residents/5/costs/statements', 200, [
                {'id': 30, 'period': '2026-11', 'total': 100, 'items': <Object>[], 'totalsByType': <Object>[]},
              ])
              ..on('GET', '/residents/7/costs/statements', 200, [
                {'id': 31, 'period': '2026-11', 'total': 1550000, 'items': <Object>[], 'totalsByType': <Object>[]},
              ]))
            .client();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: FamilyInboxScreen(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chi phí').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(button('Xem chi phí'));
    await tester.pumpAndSettle();
    await tester.tap(button('Xem chi phí'));
    await tester.pumpAndSettle();
    final screen = tester.widget<FamilyCostsScreen>(find.byType(FamilyCostsScreen));
    expect(screen.residentId, 7);
    expect(find.text('Kỳ 11/2026 · 1.550.000 đ'), findsOneWidget);
  });
}
