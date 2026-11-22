import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/family/admissions/change_request_history_screen.dart';

import '../../support/fake_backend.dart';

// 004 FR-039: người đại diện xem các yêu cầu thay đổi lưu trú đã gửi theo hợp đồng của người thân, mới nhất trước, kèm
// trạng thái theo yêu cầu phê duyệt và phụ lục.

Future<void> pump(WidgetTester tester, FakeBackend backend) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: ChangeRequestHistory(api: backend.client(), residentId: 5)),
    ),
  );
  await tester.pumpAndSettle();
}

FakeBackend backend(List<Map<String, dynamic>> rows) => FakeBackend()
  ..on('GET', '/family-portal/residents/5/contract', 200, {
    'contracts': [
      {'id': 31, 'contractNumber': 'HD-2026-000031', 'status': 'ACTIVE'},
    ],
  })
  ..on('GET', '/residency-change-requests', 200, rows);

void main() {
  testWidgets('FR_039_lichSuYeuCau_moiNhatTruoc_trangThaiTheoPhuLuc', (tester) async {
    final b = backend([
      {
        'approvalRequestId': 6,
        'contractId': 31,
        'changeTypes': ['RESIDENCE_TYPE'],
        'newValue': {'residenceType': 'DAY_CARE'},
        'requestedEffectiveDate': '2026-12-01',
        'reason': 'Gia đình đổi lịch sinh hoạt',
        'status': 'PENDING_APPROVAL',
      },
      {
        'approvalRequestId': 9,
        'contractId': 31,
        'changeTypes': ['RESIDENCE_TYPE'],
        'newValue': {'residenceType': 'SHORT_TERM_RESIDENTIAL'},
        'requestedEffectiveDate': '2026-12-05',
        'reason': 'Ở lại qua đêm',
        'status': 'APPROVED',
        'addendum': {'status': 'PENDING_SIGNATURE', 'effectiveDate': '2026-12-05'},
      },
    ]);
    await pump(tester, b);

    expect(b.calls('GET', '/residency-change-requests').single.url.queryParameters['contractId'], '31');
    expect(find.text('Loại lưu trú: Nội trú ngắn ngày'), findsOneWidget);
    expect(find.text('Đã duyệt, chờ ký phụ lục với viện'), findsOneWidget);
    expect(find.text('Chờ Quản lý viện duyệt'), findsOneWidget);
    final newer = tester.getTopLeft(find.text('Loại lưu trú: Nội trú ngắn ngày')).dy;
    final older = tester.getTopLeft(find.text('Loại lưu trú: Bán trú')).dy;
    expect(newer, lessThan(older));
  });

  testWidgets('M3_moTuThongBao_motNguoi_moThangLichSu', (tester) async {
    final b = backend([])
      ..on('GET', '/residents', 200, {
        'items': [
          {
            'id': 5,
            'personalInfo': {'fullName': 'Nguyễn Thị Lan'},
          },
        ],
      });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeRequestHistoryFromNotice(api: b.client()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bạn chưa gửi đề nghị điều chỉnh hợp đồng nào.'), findsOneWidget);
    expect(b.calls('GET', '/family-portal/residents/5/contract'), hasLength(1));
  });

  testWidgets('M3_moTuThongBao_nhieuNguoi_chonNguoiRoiXemLichSu', (tester) async {
    final b = backend([])
      ..on('GET', '/residents', 200, {
        'items': [
          {
            'id': 5,
            'personalInfo': {'fullName': 'Nguyễn Thị Lan'},
          },
          {
            'id': 6,
            'personalInfo': {'fullName': 'Trần Văn Bình'},
          },
        ],
      })
      ..on('GET', '/family-portal/residents/5/contract', 200, {
        'contracts': [
          {'id': 31, 'contractNumber': 'HD-031', 'status': 'ACTIVE'},
        ],
      });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ChangeRequestHistoryFromNotice(api: b.client()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trần Văn Bình'), findsOneWidget);
    await tester.tap(find.text('Nguyễn Thị Lan'));
    await tester.pumpAndSettle();
    expect(find.text('Bạn chưa gửi đề nghị điều chỉnh hợp đồng nào.'), findsOneWidget);
  });

  testWidgets('FR_039_chuaGuiYeuCau_baoRong', (tester) async {
    await pump(tester, backend([]));
    expect(find.text('Bạn chưa gửi đề nghị điều chỉnh hợp đồng nào.'), findsOneWidget);
  });
}
