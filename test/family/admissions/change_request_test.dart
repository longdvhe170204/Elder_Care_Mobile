import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/admissions/change_request_screen.dart';

import '../../support/fake_backend.dart';

// 004 T047 (US5; FR-037, FR-039): người đại diện gửi yêu cầu thay đổi loại lưu trú ở Nháp (mức chăm sóc theo đánh giá của
// Bác sĩ, FR-043j, người đại diện không chọn mức); hợp đồng lấy qua
// cổng người thân (api-012); thiếu hoặc sai trường báo tại ô (ngày không có thật, trước hôm nay, trùng giá trị hiện tại); có
// gợi ý ngày và lý do; 422 của backend hiện tại màn; chỉ trực tuyến.

final _today = DateTime(2026, 11, 20);

Future<void> pumpScreen(WidgetTester tester, FakeBackend backend) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ChangeRequestScreen(api: backend.client(), residentId: 5, today: _today),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String field, String option) async {
  await tester.tap(find.text(field));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Finder dateField() => find.widgetWithText(TextField, 'Ngày hiệu lực mong muốn (dd/MM/yyyy)');

Future<void> fillValid(WidgetTester tester) async {
  await choose(tester, 'Nội dung thay đổi', 'Loại lưu trú');
  await choose(tester, 'Giá trị mới', 'Nội trú ngắn ngày');
  await tester.enterText(dateField(), '25/11/2026');
  await tester.enterText(find.widgetWithText(TextField, 'Lý do'), 'Sau đợt đánh giá mới');
}

FakeBackend backendWithContract() => FakeBackend()
  ..on('GET', '/family-portal/residents/5/contract', 200, {
    'contracts': [
      {
        'id': 31,
        'contractNumber': 'HD-031',
        'status': 'ACTIVE',
        'residenceType': 'LONG_TERM_RESIDENTIAL',
        'careLevel': 'REGULAR',
        'startDate': '2026-01-01',
      },
    ],
  });

void main() {
  testWidgets('FR_037_thieuTruong_baoTaiO_vaChuaGui', (tester) async {
    final backend = backendWithContract();
    await pumpScreen(tester, backend);

    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();

    expect(find.text('Chọn nội dung thay đổi'), findsOneWidget);
    expect(find.text('Nhập ngày hiệu lực mong muốn'), findsOneWidget);
    expect(find.text('Nhập lý do'), findsOneWidget);
    expect(backend.calls('POST', '/residency-change-requests'), isEmpty);
  });

  testWidgets('FR_039_motHopDong_tuChon_hienGiaTriHienTai', (tester) async {
    await pumpScreen(tester, backendWithContract());

    expect(find.text('Hợp đồng HD-031'), findsOneWidget);
    expect(find.textContaining('Hiện tại: Nội trú dài hạn, mức Thường xuyên'), findsOneWidget);
    await tester.tap(find.text('Nội dung thay đổi'));
    await tester.pumpAndSettle();
    // FR-043j: người đại diện không chọn mức chăm sóc
    expect(find.text('Mức chăm sóc'), findsNothing);
    await tester.tap(find.text('Loại lưu trú').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Giá trị mới'));
    await tester.pumpAndSettle();
    // loại hiện tại không có trong danh sách chọn
    expect(find.text('Nội trú dài hạn'), findsNothing);
  });

  testWidgets('FR_040_ngaySai_ngayQuaKhu_baoTaiO', (tester) async {
    final backend = backendWithContract();
    await pumpScreen(tester, backend);
    await fillValid(tester);

    await tester.enterText(dateField(), '31/02/2026');
    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();
    expect(find.text('Ngày không hợp lệ, nhập theo dạng dd/MM/yyyy'), findsOneWidget);

    await tester.enterText(dateField(), '19/11/2026');
    await tester.pumpAndSettle();
    expect(find.text('Ngày hiệu lực không được trước hôm nay'), findsOneWidget);
    expect(backend.calls('POST', '/residency-change-requests'), isEmpty);
  });

  testWidgets('goiY_ngayMai_vaLyDo_dienVaoO', (tester) async {
    await pumpScreen(tester, backendWithContract());
    await choose(tester, 'Nội dung thay đổi', 'Loại lưu trú');

    await tester.tap(find.text('Ngày mai (21/11/2026)'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '21/11/2026'), findsOneWidget);

    await tester.tap(find.text('Gia đình đổi lịch sinh hoạt'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Gia đình đổi lịch sinh hoạt'), findsOneWidget);
  });

  testWidgets('FR_039_guiYeuCauDoiMuc_taoONhap_vaBaoHanhChinhHoanThien', (tester) async {
    final backend = backendWithContract()..on('POST', '/residency-change-requests', 201, {'id': 12, 'status': 'DRAFT'});
    await pumpScreen(tester, backend);
    await fillValid(tester);

    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();

    final call = backend.calls('POST', '/residency-change-requests').single;
    expect(jsonDecode(call.body), {
      'contractId': 31,
      'changeTypes': ['RESIDENCE_TYPE'],
      'newValue': {'residenceType': 'SHORT_TERM_RESIDENTIAL'},
      'requestedEffectiveDate': '2026-11-25',
      'reason': 'Sau đợt đánh giá mới',
    });
    expect(call.headers['Idempotency-Key'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(find.text('Đã gửi yêu cầu, Hành chính sẽ hoàn thiện và gửi Quản lý viện duyệt.'), findsOneWidget);
  });

  testWidgets('FR_037_khongCoHopDongHieuLuc_baoLienHeHanhChinh', (tester) async {
    final backend = FakeBackend()..on('GET', '/family-portal/residents/5/contract', 200, {'contracts': []});
    await pumpScreen(tester, backend);

    expect(find.textContaining('chưa có hợp đồng đang hiệu lực'), findsOneWidget);
    expect(find.text('Gửi yêu cầu'), findsNothing);
  });

  testWidgets('FR_040_422_hienLoiCuaBackend', (tester) async {
    final backend = backendWithContract()
      ..on('POST', '/residency-change-requests', 422, {
        'errorCode': 'INVALID_VALUE',
        'detail': 'Ngày hiệu lực sớm hơn ngày bắt đầu hợp đồng',
      });
    await pumpScreen(tester, backend);
    await fillValid(tester);

    await tester.tap(find.text('Gửi yêu cầu'));
    await tester.pumpAndSettle();

    expect(find.text('Ngày hiệu lực sớm hơn ngày bắt đầu hợp đồng'), findsOneWidget);
  });
}
