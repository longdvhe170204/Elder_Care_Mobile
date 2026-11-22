import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/staff/alerts/alert_labels.dart';

// 005 FR-057, Q-419: nhãn "Đang theo dõi" từ `openAlerts` của checklist
void main() {
  test('co canh bao dang mo thi co nhan theo loai', () {
    final alerts = [
      {'id': 1, 'residentId': 9, 'type': 'CHI_SO'},
      {'id': 2, 'residentId': 9, 'type': 'LOW_WATER_INTAKE'},
      {'id': 3, 'residentId': 10, 'type': 'CHI_SO'},
    ];
    expect(followingLabel(alerts, 9), 'Đang theo dõi: Chỉ số vượt ngưỡng, Uống nước chưa đủ');
  });

  test('khong co canh bao thi khong co nhan', () {
    expect(followingLabel(const [], 9), isNull);
    expect(followingLabel(null, 9), isNull);
    expect(followingLabel([{'id': 1, 'residentId': 10, 'type': 'CHI_SO'}], 9), isNull);
  });
}
