import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/medication/family_medication_screen.dart';
import 'package:mobile/staff/medication/medication_round_gateway.dart';
import 'package:mobile/staff/medication/medication_round_screen.dart';

import '../../support/fake_backend.dart';
import 'medication_fixtures.dart';

// Sửa BF-07 (Q-426 → Q-436): thuốc gia đình gửi (kiểm tra tiếp nhận, hoàn trả kèm người chứng kiến), Hoãn, Nhận liều,
// chỉ số đo trước khi dùng, ghi "đã dùng muộn" cho liều Bỏ lỡ bằng bản đính chính.

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
}

FakeBackend familyBackend() => FakeBackend()
  ..on('GET', '/residents', 200, {
    'items': [
      {
        'id': 5,
        'personalInfo': {'fullName': 'Nguyễn Thị Lan'},
      },
    ],
  })
  ..on('GET', '/residents/5/family-medications', 200, [
    {
      'id': 31,
      'customName': 'Paracetamol',
      'concentration': '500 mg',
      'quantity': 20,
      'unit': 'viên',
      'expiryDate': '2030-01-01',
      'status': 'PENDING_RECONCILIATION',
      'intakeChecks': {'labelOk': true, 'expiryOk': true, 'packagingOk': true, 'nameOk': false},
    },
    {
      'id': 32,
      'customName': 'Vitamin C',
      'concentration': '1 g',
      'quantity': 10,
      'unit': 'viên',
      'expiryDate': '2030-01-01',
      'status': 'HOLD_ONLY',
      'intakeChecks': {'labelOk': true, 'expiryOk': true, 'packagingOk': true, 'nameOk': true},
    },
  ])
  ..on('GET', '/residents/5/prescriptions', 200, <Object>[])
  ..on('POST', '/family-medications/32/return', 200, {});

Future<void> pumpFamily(WidgetTester tester, FakeBackend b) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: FamilyMedicationScreen(api: b.client(), newKey: () => 'key-1'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nguyễn Thị Lan'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('BR_M07_30_mucKhongDat_khongChonDuocDuocSuDung', (tester) async {
    await pumpFamily(tester, familyBackend());

    expect(find.textContaining('Đúng tên người cao tuổi không đạt'), findsOneWidget);
    final use = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Xác nhận sử dụng').first);
    expect(use.onPressed, isNull, reason: 'có mục Không đạt thì không dùng được');
  });

  testWidgets('BR_M07_30_hoanTra_guiNguoiChungKien', (tester) async {
    final b = familyBackend();
    await pumpFamily(tester, b);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Hoàn trả').last);
    await tester.pumpAndSettle();
    // Thiếu người chứng kiến thì chưa gửi
    await tester.enterText(find.widgetWithText(TextField, 'Số lượng đếm thực tế lúc trả'), '10');
    await tester.enterText(find.widgetWithText(TextField, 'Người nhận'), 'Con gái');
    await tester.tap(find.widgetWithText(FilledButton, 'Hoàn trả'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập đủ các ô bắt buộc.'), findsOneWidget);
    expect(b.calls('POST', '/family-medications/32/return'), isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Người chứng kiến'), 'Điều dưỡng Mai');
    await tester.tap(find.widgetWithText(FilledButton, 'Hoàn trả'));
    await tester.pumpAndSettle();

    final post = b.calls('POST', '/family-medications/32/return').single;
    final body = jsonDecode(post.body) as Map<String, dynamic>;
    expect(body['witness'], 'Điều dưỡng Mai');
    expect(body['quantity'], 10);
    expect((body['recipient'] as Map)['fullName'], 'Con gái');
    expect(post.headers['Idempotency-Key'], 'key-1');
  });

  group('vòng phát thuốc', () {
    late RoundFixture f;

    setUp(() {
      f = RoundFixture();
      serveRound(f.backend);
    });

    tearDown(() => f.cache.close());

    test('BR_M07_26_hoan_ghiOnline_matMangKhongVaoHangDoi', () async {
      final load = await f.repository.load(7);
      final item = load.round.items.firstWhere((i) => (i['dose'] as Map)['doseKey'] == '10-202611050800');
      f.backend.on('POST', '/medication-doses/10-202611050800/postpone', 200, {});

      await f.repository.record(
        accountId: 7,
        item: item,
        outcome: DoseOutcome.postponed,
        body: {'reason': 'Đang ăn'},
        key: 'k1',
      );
      expect(f.backend.calls('POST', '/medication-doses/10-202611050800/postpone'), hasLength(1));

      f.backend.down = true;
      await expectLater(
        f.repository.record(accountId: 7, item: item, outcome: DoseOutcome.postponed, body: {'reason': 'x'}, key: 'k2'),
        throwsA(anything),
      );
      expect(await f.queue.unsynced(7), isEmpty, reason: 'Hoãn chỉ ghi khi có mạng');
    });

    test('BR_M07_26_nhanLieu_guiClaimVaTraGioHetHan', () async {
      final load = await f.repository.load(7);
      final item = load.round.items.first;
      f.backend.on('POST', '/medication-doses/10-202611050800/claim', 200, {'claimExpiresAt': '2026-11-05T01:20:00Z'});

      final until = await f.repository.claim(load.round.items.firstWhere((i) => (i['dose'] as Map)['doseKey'] == '10-202611050800'), 'k');

      expect(until, DateTime.utc(2026, 11, 5, 1, 20));
      expect(item, isNotNull);
    });

    test('BR_M07_26_chiSo_vaoHangDoiNgoaiTuyen', () async {
      final load = await f.repository.load(7);
      final item = load.round.items.firstWhere((i) => (i['dose'] as Map)['doseKey'] == '10-202611050800');
      f.backend.down = true;

      await f.repository.record(
        accountId: 7,
        item: item,
        outcome: DoseOutcome.administered,
        body: {
          'administeredAt': '2026-11-05T08:05:00+07:00',
          'measurements': [
            {'code': 'HEART_RATE', 'value': 72},
          ],
        },
        key: 'k',
      );

      final queued = (await f.queue.unsynced(7)).single;
      expect((jsonDecode(queued.content) as Map)['measurements'], [
        {'code': 'HEART_RATE', 'value': 72},
      ]);
    });

    testWidgets('Q327_lieuBoLo_ghiDaDungMuon_guiBanDinhChinh', (tester) async {
      f.backend.on('GET', '/medication-doses/rounds', 200, [
        {
          ...dose('10-202611050800', prescriptionId: 10, status: 'MISSED', scheduled: '2026-11-05T01:00:00Z'),
          'result': {'id': 555, 'late': true},
        },
      ]);
      f.backend.on('POST', '/corrections/M07.DOSE_RESULT/555', 201, {'id': 1});

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MedicationRoundScreen(
            repository: f.repository,
            accountId: 7,
            newKey: () => 'late-key',
            clock: () => DateTime.utc(2026, 11, 5, 1, 5),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Ghi đã dùng muộn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Ghi đã dùng muộn'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập lý do.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Lý do đính chính (bắt buộc)'), 'Quên ghi, đã cho dùng');
      await tester.tap(find.widgetWithText(FilledButton, 'Ghi đã dùng muộn'));
      await settle(tester);

      final post = f.backend.calls('POST', '/corrections/M07.DOSE_RESULT/555').single;
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['type'], 'AMEND_CONTENT');
      expect((body['correctedContent'] as Map)['resultType'], 'ADMINISTERED');
      expect(body['reason'], 'Quên ghi, đã cho dùng');
      expect(post.headers['Idempotency-Key'], 'late-key');
    });
  });
}
