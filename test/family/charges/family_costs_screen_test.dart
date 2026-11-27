import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/common/api/api_client.dart';
import 'package:mobile/family/charges/family_costs_screen.dart';

void main() {
  testWidgets('FR_037_038_bang_chot_va_tam_tinh_thieu_gia', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient((request) async {
        final Object body = request.url.path.endsWith('provisional')
            ? {'label': 'tạm tính, chưa chốt', 'totalsByType': <Object>[], 'hasUnpricedItems': true}
            : [
                {'id': 1, 'period': '2026-10', 'total': 300, 'items': <Object>[], 'totalsByType': <Object>[]},
              ];
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    await tester.pumpWidget(MaterialApp(home: FamilyCostsScreen(api: api, residentId: 7)));
    await tester.pumpAndSettle();
    expect(find.textContaining('10/2026'), findsOneWidget);
    await tester.tap(find.text('Xem tạm tính'));
    await tester.pumpAndSettle();
    expect(find.text('Còn khoản chưa có đơn giá'), findsOneWidget);
  });

  // Demo 2026-11-25: tiền dạng xxx.xxx.xxx đ; bảng kỳ cuối nói rõ đã trừ vào số dư để người thân biết khoản phải trả
  testWidgets('FR_037_tien_ngan_nghin_va_bang_ky_cuoi_da_tru_so_du', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient((request) async {
        final Object body = [
          {
            'id': 2,
            'period': '2026-11',
            'total': 1550000,
            'finalPeriod': true,
            'statementType': 'REGULAR',
            'items': [
              {
                'description': 'Phí lưu trú',
                'incurredOn': '2026-11-20',
                'quantity': 1,
                'unit': 'ngày',
                'unitPrice': 300000,
                'amount': 300000,
              },
            ],
            'totalsByType': <Object>[],
          },
        ];
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    await tester.pumpWidget(MaterialApp(home: FamilyCostsScreen(api: api, residentId: 7)));
    await tester.pumpAndSettle();
    expect(find.text('Kỳ 11/2026 · 1.550.000 đ'), findsOneWidget);
    expect(find.textContaining('đồng'), findsNothing);
    await tester.tap(find.text('Kỳ 11/2026 · 1.550.000 đ'));
    await tester.pumpAndSettle();
    expect(
      find.text('Tổng bảng kỳ cuối đã được trừ vào số dư. Xem số dư, còn nợ và cách nộp tiền ở mục Số dư.'),
      findsOneWidget,
    );
    expect(find.text('300.000 đ'), findsOneWidget);
    expect(find.textContaining('Đơn giá 300.000 đ'), findsOneWidget);
  });

  testWidgets('FR_043_403_khong_hien_du_lieu_chi_phi', (tester) async {
    final api = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({'errorCode': 'PERMISSION_DENIED'}),
          403,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(home: FamilyCostsScreen(api: api, residentId: 7)));
    await tester.pumpAndSettle();
    expect(find.text('Bạn không có quyền xem chi phí của người cao tuổi này.'), findsOneWidget);
    expect(find.text('Xem tạm tính'), findsNothing);
  });

  // Góp ý demo BF-10 (B16, chọn A): khoảng ngày lọc cả khoản trong bảng đã chốt theo ngày phát sinh
  testWidgets('B16_khoang_ngay_loc_ca_bang_da_chot', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Map<String, Object> item(String description, String date, int amount) => {
      'description': description,
      'incurredOn': date,
      'quantity': 1,
      'unit': 'lần',
      'unitPrice': amount,
      'amount': amount,
    };
    final api = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient((request) async {
        final Object body = [
          {
            'id': 2,
            'period': '2026-11',
            'total': 300000,
            'items': [item('Khám ngoài', '2026-11-05', 100000), item('Phục hồi', '2026-11-24', 200000)],
            'totalsByType': <Object>[],
          },
        ];
        return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FamilyCostsScreen(
          api: api,
          residentId: 7,
          initialRange: DateTimeRange(start: DateTime(2026, 11, 20), end: DateTime(2026, 11, 25)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Đang xem các khoản phát sinh từ 20/11/2026 đến 25/11/2026.'), findsOneWidget);
    await tester.tap(find.text('Kỳ 11/2026 · trong khoảng 200.000 đ'));
    await tester.pumpAndSettle();
    expect(find.text('Phục hồi'), findsOneWidget);
    expect(find.text('Khám ngoài'), findsNothing);

    await tester.tap(find.text('Bỏ chọn khoảng ngày'));
    await tester.pumpAndSettle();
    expect(find.text('Kỳ 11/2026 · 300.000 đ'), findsOneWidget);
  });
}
