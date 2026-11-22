import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/care/daily_care_schedule_screen.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/resident/channel/channel_screens.dart';

import '../../support/fake_backend.dart';

// 012 FR-076, FR-083 (a) (Q-416): Lịch chăm sóc hằng ngày trên app người thân (đổi ngày, giá trị đo khi backend trả) và
// "Chăm sóc hôm nay" của người cao tuổi (trạng thái, không kết quả đo).

const _path = '/family-portal/residents/7/daily-care-schedule';

Map<String, dynamic> _schedule(String date) => {
  'date': date,
  'measurementsShown': true,
  'available': true,
  'items': [
    {'at': '${date}T00:00:00Z', 'kind': 'ROUTINE', 'name': 'Thức dậy', 'status': null, 'measuredValue': null},
    {'at': '${date}T01:00:00Z', 'kind': 'CARE_TASK', 'name': 'Đo huyết áp', 'status': 'DONE', 'measuredValue': '125'},
    {
      'at': '${date}T01:30:00Z',
      'kind': 'CARE_TASK',
      'name': 'Hỗ trợ đi lại',
      'status': 'NOT_DONE',
      'measuredValue': null,
    },
  ],
};

void main() {
  testWidgets('FR_076_nguoiThan_xemTheoGio_doiNgay', (tester) async {
    final b = FakeBackend()..on('GET', _path, 200, _schedule('2026-11-22'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DailyCareScheduleScreen(
            api: b.client(),
            path: _path,
            residentName: 'Nguyễn Văn Bình',
            today: '2026-11-22',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ngày 22/11/2026'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.text('Thức dậy'), findsOneWidget);
    expect(find.text('Hoàn thành'), findsOneWidget);
    expect(find.text('Chưa hoàn thành'), findsOneWidget);
    expect(find.text('Kết quả đo: 125'), findsOneWidget);
    expect(b.calls('GET', _path).single.url.queryParameters['date'], '2026-11-22');

    await tester.tap(find.byTooltip('Ngày trước'));
    await tester.pumpAndSettle();
    expect(find.text('Ngày 21/11/2026'), findsOneWidget);
    expect(b.calls('GET', _path).last.url.queryParameters['date'], '2026-11-21');
  });

  testWidgets('FR_083_nguoiCaoTuoi_chamSocHomNay_coTrangThai', (tester) async {
    final b = FakeBackend()..on('GET', '/resident-channel/daily-care-schedule', 200, _schedule('2026-11-22'));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CareScheduleScreen(api: b.client()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chăm sóc hôm nay'), findsOneWidget);
    expect(find.text('07:00 Thức dậy'), findsOneWidget);
    expect(find.text('08:00 Đo huyết áp'), findsOneWidget);
    expect(find.text('Hoàn thành'), findsOneWidget);
  });

  test('todayInVietnam_theoGioViet', () {
    expect(todayInVietnam(DateTime.utc(2026, 11, 21, 18)), '2026-11-22');
  });
}
