import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/shift_home/shift_home_screen.dart';
import 'package:mobile/staff/staff_navigation.dart';

import '../../support/fake_backend.dart';

// Tab "Ca của tôi" (Figma 03 · App nhân viên node 5:5; spec 2026-11-20 mục 5.1): thẻ ca hiện tại, Cần làm ngay (cảnh báo
// khẩn cấp, Báo sự cố), Công việc trong ca (Checklist ca, Bàn giao ca, Lịch ca và đơn).

// 10:00 giờ Việt Nam ngày 16/11/2026.
DateTime _now() => DateTime.utc(2026, 11, 16, 3);

Map<String, dynamic> _shift(String startsAt, String endsAt) => {
  'id': 1,
  'startsAt': startsAt,
  'endsAt': endsAt,
  'status': 'IN_PROGRESS',
  'staff': <Object>[],
};

void main() {
  late FakeBackend backend;
  late List<StaffTab> selected;
  late List<String> opened;

  setUp(() {
    backend = FakeBackend()
      ..on('GET', '/me/notifications', 200, {'items': <Object>[], 'unacknowledgedUrgentCount': 0})
      ..on('GET', '/me/shifts', 200, [_shift('2026-11-16T00:00:00Z', '2026-11-16T08:00:00Z')]);
    selected = [];
    opened = [];
  });

  Future<void> pump(WidgetTester tester, {bool showSchedule = true}) async {
    Widget page(String name) => Text('màn $name');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ShiftHomeScreen(
            api: backend.client(),
            showChecklist: true,
            showHandover: true,
            showSchedule: showSchedule,
            onSelectTab: selected.add,
            open: (name) {
              opened.add(name);
              return page(name);
            },
            clock: _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('trongCa_hienConLai', (tester) async {
    await pump(tester);
    expect(find.text('07:00–15:00 · Còn 5 giờ 0 phút'), findsOneWidget);
  });

  testWidgets('ngoaiCa_hienCaTiepTheo', (tester) async {
    backend.on('GET', '/me/shifts', 200, [_shift('2026-11-17T00:00:00Z', '2026-11-17T08:00:00Z')]);
    await pump(tester);
    expect(find.text('Ca tiếp theo'), findsOneWidget);
    expect(find.textContaining('17/11/2026'), findsOneWidget);
  });

  testWidgets('khongCoCa_baoChuaCo', (tester) async {
    backend.on('GET', '/me/shifts', 200, <Object>[]);
    await pump(tester);
    expect(find.text('Chưa có ca trong hôm nay và ngày mai.'), findsOneWidget);
  });

  testWidgets('coKhanCap_hienCanLamNgay', (tester) async {
    backend.on('GET', '/me/notifications', 200, {'items': <Object>[], 'unacknowledgedUrgentCount': 1});
    await pump(tester);
    await tester.tap(find.text('1 cảnh báo khẩn cấp'));
    expect(selected, [StaffTab.inbox]);
  });

  testWidgets('khongKhanCap_vanCoBaoSuCo', (tester) async {
    await pump(tester);
    expect(find.textContaining('cảnh báo khẩn cấp'), findsNothing);
    await tester.tap(find.text('Báo sự cố'));
    await tester.pumpAndSettle();
    expect(opened, ['incident']);
  });

  testWidgets('checklistCa_chuyenTab2', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Checklist ca'));
    expect(selected, [StaffTab.primary]);
  });

  testWidgets('lichCaVaDon_moLichCa', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Lịch ca và đơn'), 200);
    await tester.tap(find.text('Lịch ca và đơn'));
    await tester.pumpAndSettle();
    expect(opened, ['schedule']);
  });

  testWidgets('FR_054_khongQuyenXemLich_khongCoLichCa', (tester) async {
    await pump(tester, showSchedule: false);
    expect(find.text('Lịch ca và đơn'), findsNothing);
  });
}
