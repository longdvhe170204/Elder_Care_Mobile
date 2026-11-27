import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/staff/staff_navigation.dart';

// Trang chủ chọn lối vào chính và các mục nghiệp vụ theo vai trò và quyền.

StaffNavigation _nav(Set<String> roles, [Set<String> grants = const {}, bool readinessDuty = false]) =>
    buildStaffNavigation(roles: roles, grants: grants, readinessDuty: readinessDuty);

void main() {
  test('dieuDuong_tab2Checklist_coTiepNhanThuoc', () {
    final nav = _nav({'AC-04'}, {'MEDICATION_RECEIPT:CREATE'});
    expect(nav.primary, StaffPrimary.checklist);
    expect(nav.work, contains(StaffFeature.medicationIntake));
    expect(nav.work, isNot(contains(StaffFeature.sharedMenu)));
  });

  test('dieuDuong_biThuHep_khongTiepNhanThuoc', () {
    expect(_nav({'AC-04'}).work, isNot(contains(StaffFeature.medicationIntake)));
  });

  test('truongTangKiemDieuDuong_tab2TangHomNay_hopMuc', () {
    final nav = _nav({'AC-02', 'AC-04'}, {'SHIFT_SCHEDULE:VIEW', 'MEDICATION_RECEIPT:CREATE'});
    expect(nav.primary, StaffPrimary.floorToday);
    expect(nav.work, containsAll([StaffFeature.assignments, StaffFeature.medicationIntake]));
    expect(nav.work.toSet(), hasLength(nav.work.length));
    expect(nav.tools.toSet(), hasLength(nav.tools.length));
  });

  test('bacSi_loiVaoChinhNguoiCaoTuoi', () {
    final nav = _nav({'AC-03'});
    expect(nav.primary, StaffPrimary.residents);
  });

  test('bep_tab2PhieuBuaAn', () {
    final nav = _nav({'AC-07'});
    expect(nav.primary, StaffPrimary.mealSlips);
    expect(nav.work, [StaffFeature.familyFood]);
  });

  test('chiHanhChinh_khongCoVaiTroApp', () {
    expect(_nav({'AC-09'}).primary, isNull);
    expect(_nav({}).primary, isNull);
  });

  test('congCu_luonCoDongBoChoXemLai', () {
    for (final role in ['AC-02', 'AC-03', 'AC-04', 'AC-05', 'AC-07']) {
      expect(_nav({role}).tools.take(2), [StaffFeature.syncResults, StaffFeature.pendingReview], reason: role);
    }
  });

  test('moKhoaSom_chiTruongTangDieuDuong', () {
    expect(_nav({'AC-02'}).tools, contains(StaffFeature.earlyUnlock));
    expect(_nav({'AC-04'}).tools, contains(StaffFeature.earlyUnlock));
    expect(_nav({'AC-05'}).tools, isNot(contains(StaffFeature.earlyUnlock)));
  });

  test('giuong_truongTang_theoQuyenHoacNhiemVu', () {
    expect(_nav({'AC-02'}).work, isNot(contains(StaffFeature.beds)));
    expect(_nav({'AC-02'}, {}, true).work, contains(StaffFeature.beds));
    expect(_nav({'AC-02'}, {'ROOM_BED_CONFIGURATION:VIEW'}).work, contains(StaffFeature.beds));
  });

  test('banGiao_theoQuyenVaVaiTro', () {
    expect(_nav({'AC-05'}, {'SHIFT_HANDOVER:VIEW'}).showHandover, isTrue);
    expect(_nav({'AC-05'}).showHandover, isFalse);
    expect(_nav({'AC-07'}, {'SHIFT_HANDOVER:VIEW'}).showHandover, isFalse);
  });

  test('suCo_theoQuyen', () {
    expect(_nav({'AC-07'}, {'INCIDENT_EMERGENCY:VIEW'}).work, contains(StaffFeature.incidents));
    expect(_nav({'AC-07'}).work, isNot(contains(StaffFeature.incidents)));
  });
}
