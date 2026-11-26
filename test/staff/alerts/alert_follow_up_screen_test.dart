import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/alerts/alert_follow_up_screen.dart';

import '../../support/fake_backend.dart';

// 005 FR-057, 007 FR-087 (Q-419): từ nhãn "Đang theo dõi" của checklist mở "Theo dõi cảnh báo"; xem các lần theo dõi,
// ghi kết quả theo dõi khi có lệnh `follow-up`, ô trống thì không gửi.

Map<String, dynamic> _alert(List<String> commands) => {
  'id': 9,
  'type': 'CHI_SO',
  'status': 'IN_PROGRESS',
  'followUps': [
    {'content': 'Đo lại 150/90', 'at': '2026-11-22T01:00:00Z', 'recordedBy': '[Điều dưỡng 1]'},
  ],
  'allowedCommands': commands,
};

Future<void> pump(WidgetTester tester, FakeBackend b) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AlertFollowUpScreen(api: b.client(), alertIds: const [9]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('followingAlertIds_chiLayCanhBaoCuaNguoiCaoTuoi', () {
    final open = [
      {'id': 9, 'residentId': 7, 'type': 'CHI_SO'},
      {'id': 10, 'residentId': 8, 'type': 'WEIGHT_LOSS'},
    ];
    expect(followingAlertIds(open, 7), [9]);
    expect(followingAlertIds(open, 99), isEmpty);
    expect(followingAlertIds(null, 7), isEmpty);
  });

  testWidgets('FR_057_ghiKetQuaTheoDoi_oTrongKhongGui', (tester) async {
    final b = FakeBackend()
      ..on('GET', '/alerts/9', 200, _alert(['follow-up']))
      ..on('POST', '/alerts/9/follow-ups', 201, <String, dynamic>{});
    await pump(tester, b);
    expect(find.text('Đang theo dõi: Chỉ số vượt ngưỡng'), findsOneWidget);
    expect(find.textContaining('Đo lại 150/90'), findsOneWidget);

    await tester.tap(find.text('Lưu theo dõi'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập kết quả theo dõi.'), findsOneWidget);
    expect(b.calls('POST', '/alerts/9/follow-ups'), isEmpty);

    await tester.enterText(find.byType(TextField), 'Đo lại 140/85, đã ổn hơn');
    await tester.tap(find.text('Lưu theo dõi'));
    await tester.pumpAndSettle();
    expect(b.calls('POST', '/alerts/9/follow-ups'), hasLength(1));
    expect(b.calls('POST', '/alerts/9/follow-ups').single.body, contains('Đo lại 140/85'));
  });

  testWidgets('FR_057_khongCoLenhThiChiXem', (tester) async {
    final b = FakeBackend()..on('GET', '/alerts/9', 200, _alert(const []));
    await pump(tester, b);
    expect(find.textContaining('Đo lại 150/90'), findsOneWidget);
    expect(find.text('Lưu theo dõi'), findsNothing);
  });
}
