import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/common/theme/app_theme.dart';
import 'package:mobile/staff/care_tasks/care_checklist_cache.dart';
import 'package:mobile/staff/care_tasks/care_checklist_repository.dart';
import 'package:mobile/staff/care_tasks/care_checklist_screen.dart';

import '../medication/medication_fixtures.dart';
import 'care_checklist_cache_test.dart' show FixtureChecklistGateway;

// Liều thuốc là một dòng trong Checklist ca (spec 2026-11-20 mục 5.2, anh chốt bỏ mục Phát thuốc riêng): bấm dòng mở
// "Đối chiếu liều thuốc" (Figma 5:290) dùng khung ghi liều hiện có; không có quyền phát thuốc thì dòng chỉ xem.

void main() {
  late CareChecklistCache cache;
  late FixtureChecklistGateway gateway;
  late RoundFixture round;

  setUp(() {
    cache = CareChecklistCache(NativeDatabase.memory());
    gateway = FixtureChecklistGateway();
    gateway.body['tasks'] = <Object>[];
    gateway.body['medicationDoses'] = [
      {
        'doseKey': '10-202611050800',
        'medication': {'description': 'Paracetamol 500 mg'},
      },
    ];
    round = RoundFixture();
    serveRound(round.backend);
  });

  tearDown(() async {
    await cache.close();
    await round.cache.close();
  });

  Future<void> view(WidgetTester tester, {required bool canRecord}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CareChecklistScreen(
          repository: CareChecklistRepository(gateway, cache),
          accountId: 7,
          shiftId: 9,
          medication: canRecord ? round.repository : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lieuThuoc_bamMoDoiChieu', (tester) async {
    await view(tester, canRecord: true);
    await tester.tap(find.text('Paracetamol 500 mg'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Đối chiếu liều thuốc'), findsOneWidget);
    expect(find.text('Nguyễn Thị Lan'), findsWidgets);
  });

  testWidgets('lieuThuoc_khongQuyen_chiXem', (tester) async {
    await view(tester, canRecord: false);
    await tester.tap(find.text('Paracetamol 500 mg'));
    await tester.pumpAndSettle();
    expect(find.text('Đối chiếu liều thuốc'), findsNothing);
  });
}
