import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/balance/family_balance_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/fake_backend.dart';

// 017 T011 phần app người thân (FR-003): số dư, cọc, thông tin nộp tiền kèm mã QR VietQR không số tiền, giao dịch Đã
// xác nhận; chưa có tài khoản thu thì không có mã QR; không có quyền xem chi phí thì nói rõ.

Future<void> pump(WidgetTester tester, FakeBackend b) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: FamilyBalanceScreen(api: b.client(), residentId: 7, residentName: 'Nguyễn Thị Lan'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FR_003_soDu_thongTinNopTien_maQr_giaoDich', (tester) async {
    final b = FakeBackend()
      ..on('GET', '/family-portal/residents/7/balance', 200, {
        'balance': -9100000,
        'depositBalance': 10000000,
        'debt': 9100000,
        'transactions': [
          {'id': 3, 'type': 'STATEMENT_PAYMENT', 'ledger': 'BALANCE', 'amount': -9300000, 'at': '2026-11-01T01:00:00Z'},
        ],
        'paymentInstructions': {
          'bank': 'Vietcombank',
          'accountNumber': '0011004000123',
          'accountHolder': 'Viện dưỡng lão An Bình',
          'paymentCode': 'NCT7K2M9XA',
          'vietQr': '00020101021138570010A000000727',
        },
      });
    await pump(tester, b);

    expect(find.text('Còn nợ 9.100.000 đ'), findsOneWidget);
    expect(find.text('Tiền cọc 10.000.000 đ'), findsOneWidget);
    expect(find.text('NCT7K2M9XA'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Thanh toán bảng chi phí'), 200);
    expect(find.text('Thanh toán bảng chi phí'), findsOneWidget);
    expect(find.text('-9.300.000 đ'), findsOneWidget);
  });

  testWidgets('Q_460_taiBienNhan_chiKhoanNop', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final b = FakeBackend()
      ..on('GET', '/family-portal/residents/7/balance', 200, {
        'balance': 100,
        'depositBalance': 0,
        'transactions': [
          {'id': 3, 'type': 'STATEMENT_PAYMENT', 'ledger': 'BALANCE', 'amount': -100, 'at': '2026-11-01T01:00:00Z'},
          {'id': 2, 'type': 'CASH_PAYMENT', 'ledger': 'BALANCE', 'amount': 200, 'at': '2026-10-20T02:00:00Z'},
          {'id': 4, 'type': 'REFUND', 'ledger': 'BALANCE', 'amount': -50, 'at': '2026-10-19T02:00:00Z'},
        ],
      })
      ..on('GET', '/family-portal/balance-transactions/2/receipt', 200, {})
      ..on('GET', '/family-portal/balance-transactions/4/receipt', 200, {});
    final shared = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FamilyBalanceScreen(
            api: b.client(),
            residentId: 7,
            residentName: 'Nguyễn Thị Lan',
            share: (bytes, name, mimeType) async => shared.add('$name $mimeType'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // khoản nộp và khoản hoàn có biên nhận, trừ chi phí thì không
    expect(find.text('Tải biên nhận'), findsNWidgets(2));
    await tester.tap(find.text('Tải biên nhận').first);
    await tester.pumpAndSettle();

    expect(b.calls('GET', '/family-portal/balance-transactions/2/receipt'), hasLength(1));
    expect(shared, ['BN-000002.pdf application/pdf']);

    await tester.tap(find.text('Tải biên nhận').last);
    await tester.pumpAndSettle();
    expect(shared.last, 'HT-000004.pdf application/pdf');
  });

  testWidgets('FR_003_chuaCoTaiKhoanThu_khongCoMaQr', (tester) async {
    final b = FakeBackend()
      ..on('GET', '/family-portal/residents/7/balance', 200, {'balance': 0, 'depositBalance': 0, 'transactions': []});
    await pump(tester, b);
    expect(find.text('Liên hệ Kế toán để biết tài khoản nộp tiền.'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('FR_003_403_chuaCoQuyenXemChiPhi', (tester) async {
    final b = FakeBackend()
      ..on('GET', '/family-portal/residents/7/balance', 403, {'status': 403, 'errorCode': 'PERMISSION_DENIED'});
    await pump(tester, b);
    expect(find.textContaining('chưa có quyền xem chi phí'), findsOneWidget);
  });
}
