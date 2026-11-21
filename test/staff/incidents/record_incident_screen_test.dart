import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/incidents/incidents_screen.dart';
import 'package:mobile/staff/incidents/record_incident_screen.dart';

import '../../support/fake_backend.dart';

// Luồng 2.2, 2.3 SRS: nhân viên báo sự cố từ app (POST /incidents như form Ghi nhận sự cố của web).

FakeBackend backendWithChoices() => FakeBackend()
  ..on('GET', '/incident-types', 200, [
    {'id': 3, 'name': 'Té ngã', 'status': 'ACTIVE', 'defaultLevel': 'MEDIUM', 'allowsNoResident': false},
    {'id': 4, 'name': 'Loại cũ', 'status': 'INACTIVE', 'defaultLevel': 'LOW', 'allowsNoResident': false},
  ])
  ..on('GET', '/residents', 200, {
    'items': [
      {
        'id': 77,
        'profileCode': 'NCT-0077',
        'personalInfo': {'fullName': 'Người kiểm thử'},
      },
      {
        'id': 78,
        'profileCode': 'NCT-0078',
        'personalInfo': {'fullName': 'Người thứ hai'},
      },
    ],
  });

Future<bool?> openForm(WidgetTester tester, FakeBackend backend, {int? residentId}) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  bool? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => RecordIncidentScreen(api: backend.client(), residentId: residentId),
                ),
              );
            },
            child: const Text('mở'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> pickType(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('incident-type')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Té ngã').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('thieuThongTin_baoTaiO_khongGoiApi', (tester) async {
    final backend = backendWithChoices();
    await openForm(tester, backend, residentId: 77);
    await tester.tap(find.text('Ghi nhận sự cố'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn loại sự cố'), findsOneWidget);
    expect(find.text('Nhập mô tả'), findsOneWidget);
    expect(backend.calls('POST', '/incidents'), isEmpty);
  });

  testWidgets('chonSanNguoiCaoTuoi_loaiDatMucMacDinh_guiDungBody', (tester) async {
    final backend = backendWithChoices()..on('POST', '/incidents', 201, {'id': 40});
    await openForm(tester, backend, residentId: 77);
    expect(find.text('Người kiểm thử (NCT-0077)'), findsOneWidget);
    expect(find.text('Loại cũ'), findsNothing);
    await pickType(tester);
    await tester.enterText(find.byKey(const Key('incident-description')), 'Ngã khi đứng dậy');
    await tester.tap(find.text('Ghi nhận sự cố'));
    await tester.pumpAndSettle();
    final calls = backend.calls('POST', '/incidents');
    expect(calls, hasLength(1));
    expect(calls.single.headers['Idempotency-Key'], isNotEmpty);
    final body = jsonDecode(calls.single.body) as Map<String, dynamic>;
    expect(body['residentId'], 77);
    expect(body['incidentTypeId'], 3);
    expect(body['level'], 'MEDIUM');
    expect(body['description'], 'Ngã khi đứng dậy');
    expect(body['discoveredAt'] as String, endsWith('+07:00'));
    expect(body.containsKey('lowerLevelReason'), isFalse);
    expect(find.text('mở'), findsOneWidget);
  });

  testWidgets('haMucThapHonMacDinh_batBuocLyDo', (tester) async {
    final backend = backendWithChoices()..on('POST', '/incidents', 201, {'id': 41});
    await openForm(tester, backend, residentId: 77);
    await pickType(tester);
    await tester.tap(find.text('Nhẹ'));
    await tester.enterText(find.byKey(const Key('incident-description')), 'Trượt chân');
    await tester.tap(find.text('Ghi nhận sự cố'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập lý do hạ mức'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('incident-lower-reason')), 'Không có tổn thương');
    await tester.tap(find.text('Ghi nhận sự cố'));
    await tester.pumpAndSettle();
    final body = jsonDecode(backend.calls('POST', '/incidents').single.body) as Map<String, dynamic>;
    expect(body['level'], 'LOW');
    expect(body['lowerLevelReason'], 'Không có tổn thương');
  });

  testWidgets('loiBackend_giuForm_hienChiTiet', (tester) async {
    final backend = backendWithChoices()
      ..on('POST', '/incidents', 409, {
        'status': 409,
        'errorCode': 'BLOCKED',
        'detail': 'Người cao tuổi đã kết thúc lưu trú',
      });
    await openForm(tester, backend, residentId: 77);
    await pickType(tester);
    await tester.enterText(find.byKey(const Key('incident-description')), 'Ngã');
    await tester.tap(find.text('Ghi nhận sự cố'));
    await tester.pumpAndSettle();
    expect(find.text('Người cao tuổi đã kết thúc lưu trú'), findsOneWidget);
    expect(find.text('Ghi nhận sự cố'), findsOneWidget);
  });

  testWidgets('manSuCo_coNutBaoSuCo', (tester) async {
    final backend = backendWithChoices()..on('GET', '/incidents', 200, <dynamic>[]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: IncidentsScreen(api: backend.client())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Báo sự cố'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordIncidentScreen), findsOneWidget);
  });
}
