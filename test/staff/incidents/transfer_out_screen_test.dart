import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/incidents/transfer_out_screen.dart';

import '../../support/fake_backend.dart';

// Chuyển viện từ sự cố (007 FR-049, FR-050; BR-M05-14): bắt buộc nơi chuyển đến, người đi cùng; phiếu điều trị yêu cầu hỏi
// trước thì phải chọn đã liên hệ chưa; xong thì gửi phiếu tóm tắt PDF (cùng tệp backend dựng như web).

final shared = <String>[];

Future<void> pumpScreen(WidgetTester tester, FakeBackend backend) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: TransferOutScreen(
        api: backend.client(),
        incidentId: 2,
        residentName: 'Hoàng Văn Em',
        dial: (_) async => true,
        share: (Uint8List bytes, String name) async => shared.add(name),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeBackend backend;
  setUp(() {
    shared.clear();
    backend = FakeBackend()
      ..on('GET', '/incidents/2/transfer-out/info', 200, {
        'mustAskFirst': true,
        'isEmergency': false,
        'endOfLifeWish': {'notRecorded': true},
        'primaryContact': {'fullName': 'Hoàng Thị Én', 'phoneNumber': '0911000103'},
      })
      ..on('GET', '/staff', 200, [
        {'id': 9005, 'fullName': 'Hoàng Thị Dung', 'position': 'Điều dưỡng'},
      ]);
  });

  testWidgets('BR_M05_14_thieuO_khongGui', (tester) async {
    await pumpScreen(tester, backend);
    await tester.tap(find.text('Xác nhận chuyển viện'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập nơi chuyển đến'), findsOneWidget);
    expect(backend.calls('POST', '/incidents/2/transfer-out'), isEmpty);
  });

  testWidgets('BR_M05_14_guiDungBody_roiGuiPhieuPdf', (tester) async {
    backend
      ..on('POST', '/incidents/2/transfer-out', 201, {'id': 31, 'receivingFacility': 'Bệnh viện Xanh Pôn'})
      ..on('GET', '/transfer-summaries/31/document', 200, 'PDF');
    await pumpScreen(tester, backend);
    await tester.enterText(find.widgetWithText(TextField, 'Chuyển đến (bệnh viện)'), 'Bệnh viện Xanh Pôn');
    await tester.enterText(
      find.widgetWithText(TextField, 'Người đi cùng (họ tên, chức danh)'),
      'Hoàng Thị Dung, điều dưỡng',
    );
    await tester.tap(find.text('Đã liên hệ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xác nhận chuyển viện'));
    await tester.pumpAndSettle();

    final call = backend.calls('POST', '/incidents/2/transfer-out').single;
    expect(call.headers['Idempotency-Key'], isNotEmpty);
    expect(jsonDecode(call.body), {
      'transferUnit': 'Bệnh viện Xanh Pôn',
      'companion': 'Hoàng Thị Dung, điều dưỡng',
      'requiredContactReached': true,
    });
    expect(find.text('Hoàng Văn Em đã chuyển đến Bệnh viện Xanh Pôn'), findsOneWidget);

    await tester.tap(find.text('Gửi phiếu tóm tắt (PDF)'));
    await tester.pumpAndSettle();
    expect(shared, ['phieu-chuyen-vien-31.pdf']);
  });
}
