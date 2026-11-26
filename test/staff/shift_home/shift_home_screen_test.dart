import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/shift_home/shift_home_screen.dart';
import 'package:mobile/staff/staff_dashboard_style.dart';

import '../../support/fake_backend.dart';

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
  late int inboxOpens;
  late List<String> opened;

  setUp(() {
    backend = FakeBackend()
      ..on('GET', '/me/notifications', 200, {'items': <Object>[], 'unacknowledgedUrgentCount': 0})
      ..on('GET', '/me/shifts', 200, [_shift('2026-11-16T00:00:00Z', '2026-11-16T08:00:00Z')]);
    inboxOpens = 0;
    opened = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    bool showSchedule = true,
    bool showDayCare = false,
    int urgentCount = 0,
  }) async {
    StaffShortcut shortcut(String title, String name) =>
        StaffShortcut(title, const Icon(Icons.list), StaffShortcutTone.blue, () async => opened.add(name));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ShiftHomeScreen(
            api: backend.client(),
            work: [
              shortcut('Checklist ca', 'checklist'),
              if (showSchedule) shortcut('Lịch ca và đơn', 'schedule'),
              shortcut('Bàn giao ca', 'handover'),
            ],
            tools: const [],
            other: [shortcut('Báo sự cố', 'incident'), if (showDayCare) shortcut('Điểm danh bán trú', 'dayCare')],
            urgentCount: urgentCount,
            onOpenInbox: () => inboxOpens++,
            refreshDashboard: () async {},
            clock: _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('trongCa_hienThoiGianVaTrangThai', (tester) async {
    await pump(tester);
    expect(find.text('07:00–15:00'), findsOneWidget);
    expect(find.text('Đang diễn ra'), findsOneWidget);
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
    await pump(tester, urgentCount: 1);
    await tester.tap(find.text('1 cảnh báo khẩn cấp'));
    expect(inboxOpens, 1);
  });

  testWidgets('khongKhanCap_vanCoBaoSuCo', (tester) async {
    await pump(tester);
    expect(find.textContaining('cảnh báo khẩn cấp'), findsNothing);
    await tester.tap(find.text('Báo sự cố'));
    await tester.pumpAndSettle();
    expect(opened, ['incident']);
  });

  testWidgets('checklistCa_moChecklist', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Checklist ca'));
    expect(opened, ['checklist']);
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

  testWidgets('FR_012_coQuyenDiemDanh_hienMucBanTru_moDiemDanh', (tester) async {
    await pump(tester, showDayCare: true);
    await tester.scrollUntilVisible(find.text('Điểm danh bán trú'), 200);
    expect(find.text('Nghiệp vụ khác'), findsOneWidget);
    await tester.tap(find.text('Điểm danh bán trú'));
    await tester.pumpAndSettle();
    expect(opened, ['dayCare']);
  });

  testWidgets('FR_012_khongQuyenDiemDanh_khongCoMucBanTru', (tester) async {
    await pump(tester);
    expect(find.text('Điểm danh bán trú'), findsNothing);
  });
}
