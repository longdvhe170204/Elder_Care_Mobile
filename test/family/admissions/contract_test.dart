import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/admissions/contract_screen.dart';

import '../../support/fake_backend.dart';

// 004 T038 (US3; FR-028): người đại diện xem hợp đồng trên app người thân qua cổng người thân; không có thao tác sửa;
// lỗi tải báo rõ kèm nút Tải lại. Phụ lục và đặt cọc chưa có trên cổng người thân (việc còn lại mục B), nên không test ở đây.

Future<void> pumpScreen(WidgetTester tester, FakeBackend backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ContractScreen(api: backend.client())),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> contract({int id = 31, String status = 'ACTIVE'}) => {
  'id': id,
  'contractNumber': 'HD-031',
  'residenceType': 'LONG_TERM_RESIDENTIAL',
  'startDate': '2026-11-10',
  'status': status,
};

FakeBackend withResident({List<dynamic> contracts = const []}) => FakeBackend()
  ..on('GET', '/family-portal/residents', 200, [
    {'residentId': 9, 'fullName': 'Nguyễn Văn An', 'representative': true},
  ])
  ..on('GET', '/family-portal/residents/9/contract', 200, {'contracts': contracts});

void main() {
  testWidgets('FR_028_hienHopDong_trangThai_vaKhongCoNutSua', (tester) async {
    final backend = withResident(contracts: [contract()]);
    await pumpScreen(tester, backend);

    expect(find.text('Hợp đồng HD-031'), findsOneWidget);
    expect(find.text('Hiệu lực'), findsOneWidget);
    expect(find.text('Nội trú dài hạn, từ 10/11/2026'), findsOneWidget);
    expect(find.text('Sửa'), findsNothing);
  });

  testWidgets('FR_028_khongGoiEndpointCuaNhanVien', (tester) async {
    final backend = withResident(contracts: [contract()]);
    await pumpScreen(tester, backend);

    expect(backend.requests.map((r) => r.url.path), isNot(contains('/api/v1/contracts')));
    expect(find.text('Xem phụ lục, đặt cọc'), findsNothing);
  });

  testWidgets('FR_028_chuaCoHopDong_bao', (tester) async {
    final backend = withResident();
    await pumpScreen(tester, backend);
    expect(find.text('Chưa có hợp đồng nào.'), findsOneWidget);
  });

  testWidgets('FR_028_matMang_baoVaTaiLai', (tester) async {
    final backend = FakeBackend()..down = true;
    await pumpScreen(tester, backend);
    expect(find.textContaining('Không kết nối được máy chủ'), findsOneWidget);

    backend
      ..down = false
      ..on('GET', '/family-portal/residents', 200, [
        {'residentId': 9, 'fullName': 'Nguyễn Văn An', 'representative': true},
      ])
      ..on('GET', '/family-portal/residents/9/contract', 200, {
        'contracts': [contract()],
      });
    await tester.tap(find.text('Tải lại'));
    await tester.pumpAndSettle();
    expect(find.text('Hợp đồng HD-031'), findsOneWidget);
  });
}
