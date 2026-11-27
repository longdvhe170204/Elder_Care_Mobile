import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/care_tasks/care_plans_screen.dart';

import '../../support/fake_backend.dart';

// Luồng 2.2 SRS: nhân viên trong ca xem kế hoạch chăm sóc đang hiệu lực của người cao tuổi mình chăm (chỉ xem).

Future<void> show(WidgetTester tester, FakeBackend backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: CarePlansScreen(
        api: backend.client(),
        residents: const [
          {'id': 77, 'name': 'Người kiểm thử'},
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('chamNguoiCaoTuoi_hienKeHoachDangHieuLuc', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/residents/77/care-plans', 200, [
        {
          'id': 1,
          'revision': 1,
          'status': 'EXPIRED',
          'items': [
            {
              'content': 'Mục cũ',
              'frequencyType': 'ONCE_PER_SHIFT',
              'performerRole': 'CAREGIVER',
              'importance': 'NORMAL',
            },
          ],
        },
        {
          'id': 2,
          'revision': 2,
          'status': 'EFFECTIVE',
          'effectiveFrom': '2026-11-08',
          'items': [
            {
              'content': 'Mời uống nước, ghi số ml',
              'frequencyType': 'TIMES_PER_DAY',
              'timesPerDay': 2,
              'times': ['09:00:00', '15:00:00'],
              'performerRole': 'CAREGIVER',
              'importance': 'NORMAL',
              'waterTargetMl': 1200,
            },
            {
              'content': 'Kiểm tra tình trạng',
              'frequencyType': 'EVERY_N_HOURS',
              'intervalHours': 4,
              'startsAt': '08:00:00',
              'performerRole': 'NURSING_STAFF',
              'importance': 'IMPORTANT',
            },
          ],
        },
      ]);
    await show(tester, backend);
    await tester.tap(find.text('Người kiểm thử'));
    await tester.pumpAndSettle();
    // Q-447: không hiện số phiên bản
    expect(find.text('Hiệu lực từ 08/11/2026'), findsOneWidget);
    expect(find.textContaining('Kế hoạch lần'), findsNothing);
    expect(find.text('Mời uống nước, ghi số ml'), findsOneWidget);
    expect(find.text('2 lần mỗi ngày: 09:00, 15:00 · Nhân viên chăm sóc'), findsOneWidget);
    expect(find.text('Mục tiêu nước 1200 ml/ngày'), findsOneWidget);
    expect(find.text('Mỗi 4 giờ từ 08:00 · Điều dưỡng · Quan trọng'), findsOneWidget);
    expect(find.text('Mục cũ'), findsNothing);
  });

  testWidgets('chuaCoKeHoachDangHieuLuc_ghiRo', (tester) async {
    final backend = FakeBackend()..on('GET', '/residents/77/care-plans', 200, <dynamic>[]);
    await show(tester, backend);
    await tester.tap(find.text('Người kiểm thử'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có kế hoạch chăm sóc đang hiệu lực.'), findsOneWidget);
  });

  testWidgets('khongCoQuyen_hienLyDoBackend', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/residents/77/care-plans', 403, {'status': 403, 'detail': 'Không có quyền xem kế hoạch'});
    await show(tester, backend);
    await tester.tap(find.text('Người kiểm thử'));
    await tester.pumpAndSettle();
    expect(find.text('Không có quyền xem kế hoạch'), findsOneWidget);
  });

  testWidgets('caChuaCoNguoiCaoTuoi_ghiRo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CarePlansScreen(api: FakeBackend().client(), residents: const []),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ca chưa có công việc của người cao tuổi nào.'), findsOneWidget);
  });
}
