# Điều hướng app mobile theo vai trò — Kế hoạch triển khai

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mỗi vai trò nhân viên chỉ thấy chức năng mobile của mình trong khung Figma (Ca của tôi · tab 2 · Tra cứu · Thông báo · Thêm); người thân có 5 tab cố định theo việc; người cao tuổi giữ chức năng, sắp lại "Hôm nay".

**Architecture:** Một bảng cấu hình thuần Dart (`staff_navigation.dart`) nhận vai trò (`GET /me` → `roles`, lưu trên máy) và quyền (`/me/permissions`) rồi trả tab 2 và các mục "Thêm"; `StaffRoot` chỉ dựng giao diện từ kết quả đó. Phần người thân tách `FamilyRoot` thành 5 tab dùng chung một bộ chọn người cao tuổi. Không sửa backend.

**Tech Stack:** Flutter stable 3.x, Dart, ChangeNotifier, `lucide_icons_flutter`, `flutter_test` với `test/support/fake_backend.dart`.

**Spec:** [docs/superpowers/specs/2026-11-20-role-based-navigation-design.md](../specs/2026-11-20-role-based-navigation-design.md). Figma: file `Zj7ld822EmJDruIkhn4Rnf`, trang `3:4` "03 · App nhân viên".

## Global Constraints

- Không sửa backend, không đổi hợp đồng API.
- Vai trò chỉ thu hẹp: một mục không bao giờ hiện khi `/me/permissions` thiếu quyền của mục đó.
- Mã vai trò là mã actor: `AC-01` Quản lý viện, `AC-02` Trưởng tầng, `AC-03` Bác sĩ, `AC-04` Điều dưỡng, `AC-05` Nhân viên chăm sóc, `AC-07` Nhân viên bếp, `AC-09` Hành chính, `AC-14` Kế toán.
- Vai trò app nhân viên: {AC-02, AC-03, AC-04, AC-05, AC-07}. Thứ tự ưu tiên tab 2: AC-02 > AC-04 > AC-05 > AC-03 > AC-07.
- Thanh dưới nhân viên tối đa 5 mục (DESIGN.md 15.4); vùng bấm ≥ 48 logical px; trạng thái luôn có chữ (DESIGN.md 15.5).
- Chữ hiển thị theo spec: "Ca của tôi", "Checklist", "Tra cứu", "Thông báo", "Thêm", "Tầng hôm nay", "Người cao tuổi", "Phiếu bữa ăn", "Khẩn cấp", "Báo sự cố", "Lịch ca và đơn", "Đối chiếu liều thuốc", "Vai trò của bạn dùng trên web quản trị"; người thân "Hôm nay", "Lịch thăm", "Chi phí", "Thông báo", "Thêm".
- Người dùng tự commit: mỗi task kết thúc bằng `git add`, không `git commit`.
- Nhánh `impl/fix-all-UI-mobile-app` đang có thay đổi chưa commit ở `portal_screen.dart`, `today_screen.dart`, `my_shifts_screen.dart`, `sos_button.dart`, `app_theme.dart`: làm tiếp trên đó, không `git checkout`/`restore` các file này.
- File dùng CRLF; sửa bằng Edit, không `sed -i`.

## Review Focus

1. **Mở app khi mất mạng** với phiên nhân viên còn hạn: vai trò đọc từ máy, Điều dưỡng vẫn thấy tab Checklist → test ở Task 1 và Task 3.
2. **Tài khoản nhiều vai trò** (AC-02 + AC-04): tab 2 là "Tầng hôm nay", "Thêm" là hợp các mục, không trùng dòng → test ở Task 2.
3. **Quyền bị thu hẹp** (AC-04 thiếu `MEDICATION_RECEIPT:CREATE`): không có dòng Tiếp nhận thuốc → test ở Task 2.
4. **Người thân không phải đại diện, không có quyền nào**: vẫn đủ 5 tab, tab Chi phí và Lịch thăm hiện câu thiếu quyền, không có dòng chỉ cho đại diện trong Thêm → test ở Task 7.
5. **Đăng xuất rồi người khác đăng nhập trên máy dùng chung**: vai trò của người trước không còn trên máy → test ở Task 1.

---

## File Structure

| File | Vai trò |
|---|---|
| `lib/common/auth/session_controller.dart` (sửa) | `UserInfo.roles`; lưu, đọc, xóa vai trò trên máy |
| `lib/staff/staff_navigation.dart` (mới) | Bảng vai trò → tab 2, mục "Thêm"; hàm thuần, không widget |
| `lib/staff/staff_root.dart` (sửa) | Dựng thanh dưới, đầu màn có nút Khẩn cấp, "Thêm" hai nhóm, màn chỉ-web |
| `lib/staff/shift_home/shift_home_screen.dart` (mới) | Tab "Ca của tôi" (Figma `5:5`) |
| `lib/staff/care_tasks/care_checklist_screen.dart` (sửa) | Dòng liều thuốc bấm được, mở Đối chiếu liều thuốc |
| `lib/family/family_root.dart` (sửa) | 5 tab cố định, bộ chọn người cao tuổi |
| `lib/family/portal/family_selection.dart` (mới) | Danh sách người cao tuổi của người thân, người đang chọn, quyền |
| `lib/family/portal/family_today_tab.dart` (mới) | Tab "Hôm nay" |
| `lib/family/portal/family_tabs.dart` (mới) | Tab "Lịch thăm", "Chi phí", "Thêm", câu thiếu quyền |
| `lib/resident/today/today_screen.dart` (sửa) | Khối "Sắp tới", SOS ở chân màn |
| `../Elder_Care_Frontend/DESIGN.md` (sửa, kho web) | Mục 15.4 |

`portal_screen.dart` giữ `HealthScreen` và các hằng nhãn; `PortalScreen`/`ResidentPortalScreen` không còn được gắn vào điều hướng sau Task 6 (không xóa, báo lại cho người dùng).

---

### Task 1: Vai trò trong phiên

**Files:**
- Modify: `lib/common/auth/session_controller.dart` (`UserInfo`, `_remember`, nhánh `ApiUnreachable` trong khởi động, `_clear`)
- Test: `test/common/auth/session_roles_test.dart`

**Interfaces:**
- Produces: `UserInfo.roles: Set<String>` (mã actor, rỗng khi backend không trả); `SessionController.rolesKey = 'session.roles'`.

- [ ] **Step 1: Viết test lỗi**

```dart
testWidgets('roles_docTuMe_luuTrenMay', ...)       // /me trả roles ['AC-02','AC-04'] → session.user!.roles == {'AC-02','AC-04'}; store.read('session.roles') != null
testWidgets('roles_matMang_docTuMay', ...)          // store có token, 'session.roles'='AC-04', /me ném ApiUnreachable → user.roles == {'AC-04'}
testWidgets('roles_dangXuat_xoaKhoiMay', ...)       // signOut() → store.read('session.roles') == null
```
Dùng `session(backend, MemoryStore(), FakeBiometric())` và `FakeBackend.on` như các test hiện có; xem `test/common/auth/session_guard_test.dart` để biết cách mô phỏng mất mạng.

- [ ] **Step 2: Chạy, thấy lỗi**

Run: `flutter test test/common/auth/session_roles_test.dart` — Expected: FAIL (`roles` chưa có).

- [ ] **Step 3: Cài**

`UserInfo` thêm `final Set<String> roles` (mặc định `const {}`), `fromJson` đọc `json['roles']` (danh sách chuỗi). `_remember` ghi `rolesKey` là chuỗi nối bằng dấu phẩy; nhánh `ApiUnreachable` đọc lại; `_clear` xóa `rolesKey` (và đường đăng xuất gọi `_clear`).

- [ ] **Step 4: Chạy lại, xanh**

Run: `flutter test test/common/auth/` — Expected: PASS toàn thư mục.

- [ ] **Step 5:** `git add lib/common/auth/session_controller.dart test/common/auth/session_roles_test.dart`

---

### Task 2: Bảng điều hướng nhân viên

**Files:**
- Create: `lib/staff/staff_navigation.dart`
- Test: `test/staff/staff_navigation_test.dart`

**Interfaces:**
- Consumes: `UserInfo.roles` (Task 1).
- Produces:

```dart
enum StaffPrimary { checklist, floorToday, residents, mealSlips }   // tab 2
enum StaffFeature {
  // nhóm việc
  medicationIntake, incidents, alerts, servingConfirmation, mealSlipFloor, activitySessions, trips,
  assignments, beds, carePlanApproval, familyFood, residentLoginQr,
  // nhóm công cụ
  syncResults, pendingReview, earlyUnlock,
}
class StaffNavigation {
  final StaffPrimary? primary;            // null = không có vai trò app → màn chỉ-web
  final bool showLookupTab;               // false khi primary == residents
  final bool showHandover;                // dòng Bàn giao ca ở Ca của tôi
  final List<StaffFeature> work;          // "Thêm", nhóm 1, theo thứ tự bảng 5.2
  final List<StaffFeature> tools;         // "Thêm", nhóm 2
}
StaffNavigation buildStaffNavigation({required Set<String> roles, required Set<String> grants, required bool readinessDuty});
```

Bảng mục theo vai trò và điều kiện quyền (`grants` dạng `FUNCTION:OPERATION`):

| Mục | Vai trò | Điều kiện quyền |
|---|---|---|
| medicationIntake | AC-04 | `MEDICATION_RECEIPT:CREATE` |
| incidents | mọi vai trò app | `INCIDENT_EMERGENCY:VIEW` hoặc `:UPDATE` |
| alerts | AC-02, AC-03, AC-04 | `ALERT_HANDLING:VIEW` hoặc `:UPDATE` |
| servingConfirmation, mealSlipFloor | AC-05 | không (chỉ lọc vai trò) |
| activitySessions, trips | AC-02, AC-05 | `ACTIVITY_OUTING:VIEW` |
| assignments | AC-02 | `SHIFT_SCHEDULE:VIEW` |
| beds | AC-02 | `ROOM_BED_CONFIGURATION:VIEW` hoặc `readinessDuty` |
| carePlanApproval | AC-03 | không (mục 9 spec, giữ nguyên) |
| familyFood | AC-07 | không (mục 9 spec) |
| residentLoginQr | AC-04 | không (mục 9 spec) |
| syncResults, pendingReview | mọi vai trò app | không |
| earlyUnlock | AC-02, AC-04 | không (backend lọc) |
| showHandover | AC-02, AC-04, AC-05 | `SHIFT_HANDOVER:VIEW` |

Điều dưỡng làm việc của Nhân viên chăm sóc (nghiệp vụ 2.4) chỉ trong Checklist; các mục AC-05 ở "Thêm" không tự sang AC-04.

- [ ] **Step 1: Viết test bảng (lỗi)**

```dart
test('dieuDuong_tab2Checklist_coTiepNhanThuoc', ...)     // {'AC-04'} + MEDICATION_RECEIPT:CREATE → primary checklist, work chứa medicationIntake, không chứa servingConfirmation
test('dieuDuong_biThuHep_khongTiepNhanThuoc', ...)       // {'AC-04'}, grants rỗng → work không chứa medicationIntake
test('truongTangKiemDieuDuong_tab2TangHomNay_hopMuc', ...) // {'AC-02','AC-04'} → primary floorToday; work chứa assignments và medicationIntake (nếu có quyền); không mục nào lặp
test('bacSi_tab2NguoiCaoTuoi_anTraCuu', ...)             // {'AC-03'} → primary residents, showLookupTab false
test('bep_tab2PhieuBuaAn', ...)                          // {'AC-07'} → primary mealSlips, work == [familyFood] khi grants rỗng
test('chiHanhChinh_khongCoVaiTroApp', ...)                // {'AC-09'} → primary null
test('congCu_luonCoDongBoChoXemLai', ...)                // mọi vai trò app → tools bắt đầu bằng [syncResults, pendingReview]
```

- [ ] **Step 2:** `flutter test test/staff/staff_navigation_test.dart` — Expected: FAIL (file chưa có).
- [ ] **Step 3:** Cài `buildStaffNavigation` theo bảng trên.
- [ ] **Step 4:** Chạy lại — Expected: PASS.
- [ ] **Step 5:** `git add lib/staff/staff_navigation.dart test/staff/staff_navigation_test.dart`

---

### Task 3: Khung `StaffRoot` theo Figma

**Files:**
- Modify: `lib/staff/staff_root.dart`
- Delete: `test/staff/staff_root_more_items_test.dart` (thay bằng file dưới)
- Test: `test/staff/staff_root_test.dart`

**Interfaces:**
- Consumes: `buildStaffNavigation`, `StaffNavigation`, `StaffPrimary`, `StaffFeature` (Task 2); `UserInfo.roles` (Task 1); `ShiftHomeScreen` (Task 4: đến khi Task 4 xong dùng `MyShiftsScreen` làm tab Ca của tôi).
- Produces: `StaffRoot` giữ chữ ký hiện có `StaffRoot({required SessionController session, required OfflineQueue queue, PushCoordinator? push})`; thêm phương thức nội bộ `void selectTab(StaffTab tab)` với `enum StaffTab { shift, primary, lookup, inbox, more }` để Task 4 chuyển tab.

Ánh xạ: tab 2 checklist → `CareTasksHomeScreen`; floorToday → `CareTasksHomeScreen` (đã có lối vào lập việc ca, việc quá hạn theo quyền); residents → `ResidentLookupScreen`; mealSlips → `MealSlipScreen`. Mục `StaffFeature` → màn hiện có trong `_moreItems` cũ (cùng tham số). Biểu tượng lucide theo Figma: `calendarDays`, `listChecks`, `users`, `bell`, `ellipsis`.

- [ ] **Step 1: Viết test widget (lỗi)**

```dart
testWidgets('dieuDuong_thanhDuoi_theoFigma', ...)      // /me roles ['AC-04'] → NavigationDestination có đúng 5 nhãn: 'Ca của tôi','Checklist','Tra cứu','Thông báo','Thêm'
testWidgets('bacSi_thanhDuoi_4Tab', ...)               // ['AC-03'] → nhãn 'Người cao tuổi', không có 'Tra cứu'
testWidgets('chiKeToan_manChiWeb', ...)                // ['AC-14'] → find.text('Vai trò của bạn dùng trên web quản trị'), không có NavigationBar, có nút 'Đăng xuất'
testWidgets('nutKhanCap_moiTab', ...)                  // ['AC-05'] → ở mỗi tab tìm được Semantics/nút nhãn 'Khẩn cấp'
testWidgets('them_haiNhom_coDangXuat', ...)            // ['AC-04'] → trong Thêm có 'Đồng bộ', 'Chờ xem lại', 'Đăng xuất'; không có 'Phê duyệt', 'Phát thuốc'
testWidgets('matMang_vaiTroDaLuu_vanCoChecklist', ...) // store có roles 'AC-04', /me và /me/permissions không tới được → có nhãn 'Checklist'
```
Đầu file test giữ hai test `T060_*` (mục Giường theo `/bed-readiness/beds`) chuyển sang roles `['AC-02']`.

- [ ] **Step 2:** `flutter test test/staff/staff_root_test.dart` — Expected: FAIL.
- [ ] **Step 3:** Viết lại `_tabs`/`_moreItems` từ `StaffNavigation`; `headerAppBar` của mọi tab có nút "Khẩn cấp" (màu `colorScheme.error`, `Icon(LucideIcons.siren)` kèm chữ) mở `EmergencyAssistScreen`; "Thêm" là `ListView` hai nhóm thẻ dòng như Figma `5:603`, dòng cuối "Đăng xuất"; dòng "Đồng bộ" có số bản ghi chưa đồng bộ của `OfflineQueue` bên phải khi > 0. Bỏ nút Đăng xuất trên thanh tiêu đề. Giữ huy hiệu Khẩn cấp ở tab Thông báo và `_UrgentBand`.
- [ ] **Step 4:** `flutter test test/staff/` — Expected: PASS.
- [ ] **Step 5:** `git rm test/staff/staff_root_more_items_test.dart` rồi `git add lib/staff/staff_root.dart test/staff/staff_root_test.dart`

---

### Task 4: Tab "Ca của tôi"

**Files:**
- Create: `lib/staff/shift_home/shift_home_screen.dart`
- Modify: `lib/staff/staff_root.dart` (thay `MyShiftsScreen` bằng `ShiftHomeScreen` ở tab Ca của tôi)
- Test: `test/staff/shift_home/shift_home_screen_test.dart`

**Interfaces:**
- Consumes: `StaffTab`, `selectTab` (Task 3); `NotificationApi(api).page()` → `NotificationPage.urgentCount`; `GET /me/shifts?from=yyyy-MM-dd&to=yyyy-MM-dd` (trường xem `MyShiftsController`).
- Produces: `ShiftHomeScreen({required ApiClient api, required bool showHandover, required void Function(StaffTab) onSelectTab, required WidgetBuilder handover, required WidgetBuilder schedule, required WidgetBuilder reportIncident})`.

Bố cục theo Figma `5:5`: đầu màn xanh đêm "Ca của tôi" + ngày ("Thứ Hai, 16/11/2026"); thẻ ca hiện tại (tầng, giờ, "Còn x giờ y phút", thanh tiến độ) hoặc ca sắp tới gần nhất ("Ca tiếp theo …"), không có ca thì "Chưa có ca trong hôm nay và ngày mai"; nhóm "Cần làm ngay" có dòng "{n} cảnh báo khẩn cấp" khi `urgentCount > 0` (bấm → `onSelectTab(StaffTab.inbox)`) và nút "Báo sự cố"; nhóm "Công việc trong ca": "Checklist ca" (→ `StaffTab.primary`, chỉ khi primary là checklist hoặc floorToday), "Bàn giao ca" (khi `showHandover`), "Lịch ca và đơn" (→ `schedule`, mở `MyShiftsScreen`).

- [ ] **Step 1: Test lỗi**

```dart
testWidgets('trongCa_hienConLai', ...)            // now trong ca 07:00–15:00 → find.textContaining('Còn')
testWidgets('coKhanCap_hienCanLamNgay', ...)       // /me/notifications trả unacknowledgedUrgentCount 1 → '1 cảnh báo khẩn cấp'
testWidgets('khongKhanCap_vanCoBaoSuCo', ...)      // urgentCount 0 → không có 'cảnh báo khẩn cấp', có 'Báo sự cố'
testWidgets('lichCaVaDon_moLichCa', ...)           // bấm 'Lịch ca và đơn' → builder schedule được gọi
```
Giờ hiện tại truyền qua tham số tùy chọn `DateTime Function()? clock` để test cố định.

- [ ] **Step 2:** chạy, FAIL. **Step 3:** cài. **Step 4:** `flutter test test/staff/` PASS.
- [ ] **Step 5:** `git add lib/staff/shift_home lib/staff/staff_root.dart test/staff/shift_home`

---

### Task 5: Liều thuốc trong Checklist

**Files:**
- Modify: `lib/staff/care_tasks/care_checklist_screen.dart` (khối `medicationDoses`, dòng 247), `lib/staff/care_tasks/care_tasks_home_screen.dart` (truyền repository xuống)
- Modify: `lib/staff/staff_root.dart` (tạo `MedicationRoundRepository` như `_moreItems` cũ, chỉ khi có `MEDICATION_ADMINISTRATION:VIEW` hoặc `:PROFESSIONAL`)
- Test: `test/staff/care_tasks/checklist_medication_test.dart`

**Interfaces:**
- Consumes: `MedicationRoundRepository.load(int accountId) → MedicationRoundLoad` (các dòng theo người cao tuổi, mỗi item có `dose` với `doseKey`, `status`; `queued`), `doseRecordable(String?)`, `DoseSheet(repository, accountId, items, newKey, clock)` → `DoseSheetResult`.
- Produces: `CareChecklistScreen` thêm tham số tùy chọn `MedicationRoundRepository? medication`; `CareTasksHomeScreen` thêm `MedicationRoundRepository? medication` và chuyển xuống.

Dòng liều: tiêu đề thuốc, phụ đề "Họ tên · P. phòng · HH:mm", bên phải nhãn chữ ("Quá hạn" / "Chờ ghi nhận" / "Đã ghi nhận" / "Chưa đồng bộ" theo `dose.status` và `queued`). Có `medication` và liều ghi được → bấm mở trang đầy đủ tiêu đề "Đối chiếu liều thuốc" (Figma `5:290`) chứa `DoseSheet` với các item cùng `doseKey`; lưu xong tải lại checklist. `medication == null` → dòng chỉ xem, không mũi tên.

- [ ] **Step 1: Test lỗi**

```dart
testWidgets('lieuThuoc_bamMoDoiChieu', ...)        // checklist có medicationDoses [{doseKey:'d1',...}], repository giả có item doseKey 'd1' → bấm dòng → find.text('Đối chiếu liều thuốc')
testWidgets('lieuThuoc_khongQuyen_chiXem', ...)    // medication null → bấm dòng không mở trang mới
```
- [ ] **Step 2–4:** FAIL → cài → `flutter test test/staff/care_tasks/ test/staff/medication/` PASS.
- [ ] **Step 5:** `git add` các file trên.

---

### Task 6: Khung người thân 5 tab và bộ chọn

**Files:**
- Create: `lib/family/portal/family_selection.dart`
- Modify: `lib/family/family_root.dart`
- Test: `test/family/family_root_test.dart`

**Interfaces:**
- Consumes: `GET /family-portal/residents` → mỗi dòng `{residentId, fullName, relationship, representative, primaryContact, rights: {VIEW_HEALTH, VIEW_COSTS, RECEIVE_URGENT, REGISTER_VISITS, PICKUP_ALLOWED, REQUEST_SERVICES: bool}, canViewBelongings}` (rights là quyền **có tác dụng**).
- Produces:

```dart
class FamilyResident { final int id; final String fullName; final bool representative; final Map<String,bool> rights; final bool canViewBelongings;
  bool can(String right); bool get belongings; }   // belongings = representative || canViewBelongings || can('PICKUP_ALLOWED')
class FamilySelection extends ChangeNotifier { FamilySelection(ApiClient api);
  List<FamilyResident>? residents; FamilyResident? current; String? error;
  Future<void> load(); void select(int residentId); }
```

`FamilyRoot`: `NavigationBar` cố định 5 mục "Hôm nay", "Lịch thăm", "Chi phí", "Thông báo", "Thêm" (biểu tượng `heartHandshake`, `calendarDays`, `wallet`, `bell`, `ellipsis`). Đầu màn có ô chọn người cao tuổi khi `residents.length > 1`; một người thì chỉ tên. Danh sách rỗng → câu hiện có "Chưa có người cao tuổi nào có quan hệ Hiệu lực với tài khoản này." ở mọi tab trừ Thông báo, Thêm. Tab Thông báo dùng `FamilyInboxScreen` như cũ. Ba tab còn lại tạm là chỗ trống có tiêu đề đến khi Task 7 xong.

- [ ] **Step 1: Test lỗi**

```dart
testWidgets('nguoiThan_luonDu5Tab', ...)           // residents 1 người, rights toàn false → đủ 5 nhãn
testWidgets('haiNguoiCaoTuoi_coOChon', ...)         // 2 dòng → có ô chọn; chọn người 2 → selection.current.id == id người 2
```
- [ ] **Step 2–4:** FAIL → cài → `flutter test test/family/` PASS.
- [ ] **Step 5:** `git add lib/family/family_root.dart lib/family/portal/family_selection.dart test/family/family_root_test.dart`

---

### Task 7: Nội dung tab người thân

**Files:**
- Create: `lib/family/portal/family_today_tab.dart`, `lib/family/portal/family_tabs.dart`
- Modify: `lib/family/family_root.dart` (gắn tab)
- Test: `test/family/portal/family_tabs_test.dart`

**Interfaces:**
- Consumes: `FamilySelection`, `FamilyResident` (Task 6); `GET /family-portal/residents/{id}/general` → `{status, location, visits, absences, dayCareSchedule, incidents, menu: [{date, mealName, dishName}], unavailable: [String]}`; `HealthScreen(api, residentId, residentName)` ở `portal_screen.dart`; các màn hiện có `VisitRegistrationScreen`, `FamilyBalanceScreen`, `FamilyCostsScreen`, `PurchaseConsentScreen`, `RightChangeRequestsScreen`, `ChangeRequestScreen`, `ContractScreen`, `FamilyBelongingsScreen`, `FeedbackScreen`, `FamilyProfileScreen`, `FamilyActivitiesScreen`.
- Produces: `FamilyTodayTab({api, resident})`, `FamilyVisitsTab({api, resident})`, `FamilyCostsTab({api, resident})`, `FamilyMoreTab({api, resident, onSignOut})`, `Widget noRightNotice(String what, String residentName)` → câu "Bạn chưa được cấp quyền {what} của {residentName}. Liên hệ người đại diện hoặc viện để được cấp."

Nội dung theo bảng mục 6 spec:
- **Hôm nay:** trạng thái (nhãn `_statusLabels`, chuyển hằng này ra dùng chung), lịch sinh hoạt/hoạt động (lối vào `FamilyActivitiesScreen`), khối "Bữa ăn" nhóm `menu` theo ngày (hôm nay trước; `unavailable` chứa `menu` → "Chưa có thực đơn"), sự cố phần chung (số trong 30 ngày), khối Sức khỏe: `can('VIEW_HEALTH')` → nút mở `HealthScreen` (chế độ ăn riêng nằm trong đó), không thì `_healthLock`.
- **Lịch thăm:** `can('REGISTER_VISITS')` → lượt thăm sắp tới (`general.visits`) + `VisitRegistrationScreen`; không thì `noRightNotice('đăng ký thăm', …)`.
- **Chi phí:** `can('VIEW_COSTS')` → số dư, bảng chi phí (chứng từ mở từ màn số dư như hiện có); không thì `noRightNotice('xem chi phí', …)`. `representative` → thêm dòng "Đề nghị mua hộ" ở cả hai trường hợp.
- **Thêm:** `representative` → "Yêu cầu chờ xác nhận", "Yêu cầu thay đổi dịch vụ", "Hợp đồng"; `belongings` → "Đồ gửi"; mọi người → "Phản hồi", "Hồ sơ", "Đăng xuất". Tiến trình tiếp nhận: `AdmissionProgressScreen` cần `applicationId`; nếu dòng trả về từ `/contracts` có `applicationId` thì thêm nút trên thẻ hợp đồng, nếu không thì để chưa gắn và ghi vào báo cáo cuối.

- [ ] **Step 1: Test lỗi**

```dart
testWidgets('khongQuyenChiPhi_hienCauThieuQuyen', ...)   // rights VIEW_COSTS false → find.textContaining('chưa được cấp quyền xem chi phí')
testWidgets('daiDien_khongQuyenChiPhi_vanCoMuaHo', ...)  // representative true, VIEW_COSTS false → 'Đề nghị mua hộ'
testWidgets('khongDaiDien_khongCoMucDaiDien', ...)       // representative false → không có 'Yêu cầu chờ xác nhận', 'Yêu cầu thay đổi dịch vụ', 'Hợp đồng'
testWidgets('homNay_hienThucDon', ...)                    // menu [{date: hôm nay, mealName:'Trưa', dishName:'Cá kho'}] → 'Cá kho'
testWidgets('homNay_khongQuyenSucKhoe_khongNut', ...)     // VIEW_HEALTH false → không có 'Xem sức khỏe', có câu _healthLock
```
- [ ] **Step 2–4:** FAIL → cài → `flutter test test/family/` PASS (sửa `portal_screen_test.dart`, `hidden_health_test.dart` nếu chúng mở `FamilyRoot`; test gọi thẳng `ResidentPortalScreen` giữ nguyên).
- [ ] **Step 5:** `git add lib/family test/family`

---

### Task 8: "Hôm nay" của người cao tuổi

**Files:**
- Modify: `lib/resident/today/today_screen.dart` (đang có thay đổi chưa commit: đọc `git diff` trước, giữ phần đã làm)
- Test: `test/resident/today/today_screen_test.dart`

**Interfaces:**
- Consumes: dữ liệu `TodayScreen` đã tải (lịch hôm nay, bữa ăn, lượt thăm), `SosButton` (`lib/resident/sos/sos_button.dart`).
- Produces: không đổi chữ ký `TodayScreen`.

Khối "Sắp tới" đầu màn: một việc có giờ ≥ hiện tại gần nhất trong lịch, bữa ăn, lượt thăm (ví dụ "Bữa trưa · 11:00", "Cháu đến thăm · 15:00"); không có → không hiện khối. SOS cố định ở chân màn (ngoài vùng cuộn). Không thêm chức năng.

- [ ] **Step 1: Test lỗi**

```dart
testWidgets('sapToi_viecGanNhat', ...)      // clock 10:00, lịch có 09:00 và 11:00 → khối 'Sắp tới' chứa '11:00', không chứa '09:00'
testWidgets('sos_coDinhChanMan', ...)       // cuộn tới cuối danh sách → SosButton vẫn hit-testable
```
- [ ] **Step 2–4:** FAIL → cài → `flutter test test/resident/` PASS.
- [ ] **Step 5:** `git add lib/resident/today/today_screen.dart test/resident/today/today_screen_test.dart`

---

### Task 9: DESIGN.md 15.4 và kiểm tra cuối

**Files:**
- Modify: `../Elder_Care_Frontend/DESIGN.md` mục 15.4 gạch đầu dòng "Điều hướng" (kho web)

- [ ] **Step 1:** Thay gạch đầu dòng "Điều hướng" của 15.4 bằng: nhân viên theo khung Figma "Ca của tôi · [việc chính của vai trò] · Tra cứu · Thông báo · Thêm", vai trò (`GET /me` `roles`) chọn mục, quyền backend lọc, vai trò chỉ thu hẹp; Quản lý viện, Hành chính, Kế toán không có phần nhân viên trên app; người thân 5 tab cố định "Hôm nay · Lịch thăm · Chi phí · Thông báo · Thêm", tab thiếu quyền hiện câu giải thích; dẫn tới spec này. Tăng phiên bản DESIGN.md theo cách file đang ghi phiên bản.
- [ ] **Step 2:** `flutter analyze` — Expected: `No issues found!`
- [ ] **Step 3:** `flutter test` — Expected: mọi test PASS.
- [ ] **Step 4:** Chạy app với backend profile demo và `demo-full-data.sql`; đăng nhập một tài khoản mỗi vai trò AC-02, AC-03, AC-04, AC-05, AC-07, một tài khoản AC-09, `dd.nguoithan01` (hai người cao tuổi), một người cao tuổi; chụp màn đầu từng tài khoản; so với Figma `5:5`, `5:603`.
- [ ] **Step 5:** `git add` DESIGN.md ở kho web; báo người dùng: danh sách file đã add ở hai kho, màn không còn đường vào (`PortalScreen`, `ApprovalInboxScreen`, `pickups/`, `belongings/` phía nhân viên, màn danh sách Phát thuốc), việc còn lại ở mục 9 spec.
