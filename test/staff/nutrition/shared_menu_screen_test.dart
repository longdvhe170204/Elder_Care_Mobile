import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/nutrition/shared_menu_screen.dart';

import '../../support/fake_backend.dart';

// 011 T062 (FR-028, Q-445): nhân viên xem thực đơn chung đã công bố hôm nay, chuyển sang cả tuần.

Map<String, dynamic> day(String date) => {
  'date': date,
  'meals': [
    {
      'mealId': 1,
      'name': 'Bữa trưa',
      'expectedTime': '11:00',
      'dishes': [
        {'id': 30, 'name': 'Cá kho tộ', 'description': 'Cá basa kho tộ', 'imageUrl': null},
      ],
    },
  ],
};

Future<void> open(WidgetTester tester, FakeBackend b) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: SharedMenuScreen(api: b.client(), today: DateTime.utc(2026, 11, 25)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mặc định hôm nay, hiện món, mô tả của bữa', (tester) async {
    final b = FakeBackend()..on('GET', '/menus/shared', 200, [day('2026-11-25')]);
    await open(tester, b);
    expect(b.calls('GET', '/menus/shared').single.url.query, 'from=2026-11-25&to=2026-11-25');
    expect(find.text('Bữa trưa · 11:00'), findsOneWidget);
    expect(find.text('Cá kho tộ'), findsOneWidget);
    expect(find.text('Cá basa kho tộ'), findsOneWidget);
  });

  testWidgets('cả tuần đọc từ thứ Hai tới chủ nhật, có nhãn ngày', (tester) async {
    final b = FakeBackend()..on('GET', '/menus/shared', 200, [day('2026-11-25')]);
    await open(tester, b);
    await tester.tap(find.text('Cả tuần'));
    await tester.pumpAndSettle();
    expect(b.calls('GET', '/menus/shared').last.url.query, 'from=2026-11-23&to=2026-11-29');
    expect(find.text('Thứ Tư, 25/11'), findsOneWidget);
  });

  testWidgets('chưa có thực đơn công bố thì báo rỗng', (tester) async {
    final b = FakeBackend()..on('GET', '/menus/shared', 200, []);
    await open(tester, b);
    expect(find.text('Chưa có thực đơn công bố cho hôm nay.'), findsOneWidget);
  });
}
