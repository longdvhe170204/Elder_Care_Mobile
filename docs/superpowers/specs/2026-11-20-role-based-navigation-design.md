# Điều hướng app mobile theo vai trò

Ngày 2026-11-20. Bản nháp trao đổi: [plan-fix-ui.md](../../../../plan-fix-ui.md) (gốc thư mục Project). Kho: Elder_Care_Mobile, nhánh `impl/fix-all-UI-mobile-app`.

## 1. Vì sao làm

App dùng chung cho nhân viên, người thân, người cao tuổi. Phần nhân viên hiện bày gần như mọi chức năng cho mọi vai trò: điều dưỡng thấy Phiếu bữa ăn, nhân viên bếp thấy Mã đăng nhập cho người cao tuổi, ba tab giữa của thanh dưới là màn kỹ thuật (Đồng bộ, Chờ xem lại, Mở khóa sớm). Người dùng trong ca không tìm thấy việc chính của mình. Phần người thân dồn mọi việc vào một chồng nút ở màn chi tiết và có màn đã làm nhưng không có đường vào.

Mục tiêu: mở app ra, mỗi vai trò thấy ngay việc chính của mình trên điện thoại, và chỉ những việc đó.

## 2. Mục tiêu, không làm, không được xảy ra

**Mục tiêu**

- Mỗi vai trò nhân viên có danh sách chức năng mobile riêng (mục 5), trong khung thanh dưới của Figma; tab 2 là việc chính của vai trò.
- Người thân có thanh dưới 5 tab cố định theo việc (mục 6); người cao tuổi giữ chức năng, sắp lại cách bày (mục 7).
- Màn đã làm mà chưa có đường vào được gắn vào (Tiến trình tiếp nhận, Yêu cầu thay đổi dịch vụ, Hợp đồng; thực đơn chung cho người thân).

**Không làm**

- Không sửa backend, không đổi hợp đồng API.
- Không thiết kế lại nội dung từng màn nghiệp vụ (checklist, phát thuốc, sự cố…) ngoài phần nói ở đây; làm lại bố cục từng màn là việc riêng theo DESIGN.md mục 0 "Mẫu màn".
- Ba mục để làm cuối (mục 9) không thiết kế lại.

**Không được xảy ra (dù chạy được vẫn là hỏng)**

- Một mục hiện ra mà tài khoản không có quyền backend tương ứng. Vai trò chỉ thu hẹp, không bao giờ mở rộng so với `/me/permissions` (DESIGN.md 15.4 cũ, Phụ lục 27: ma trận là quyền tối đa, Quản lý viện chỉ thu hẹp).
- Mất mạng lúc mở app thì nhân viên không vào được Checklist ca (nghiệp vụ 8.6: app nhân viên ghi ngoại tuyến). Danh sách vai trò phải đọc được khi không có mạng.
- Nút Hỗ trợ khẩn cấp bị giấu sau nhiều bước (Q-375).
- Người thân thấy dữ liệu sức khỏe khi quyền xem sức khỏe không có tác dụng (BR-M01-08).

## 3. Ràng buộc

- Kênh theo Phụ lục 26.1 của nghiệp vụ: app nhân viên cho Trưởng tầng (AC-02), Bác sĩ (AC-03), Điều dưỡng (AC-04), Nhân viên chăm sóc (AC-05), Nhân viên bếp (AC-07). Quản lý viện (AC-01), Hành chính (AC-09), Kế toán (AC-14) chỉ có ở web (anh chốt 2026-11-20).
- `GET /me` trả `roles` là danh sách mã actor đã sắp (`["AC-02","AC-04"]`, [MeController.java](../../../../Elder_Care/backend/src/main/java/com/eldercare/backend/administration/account/web/MeController.java)). App hiện chưa đọc trường này ([session_controller.dart](../../../lib/common/auth/session_controller.dart) `UserInfo`).
- Quyền hiện hành: `GET /me/permissions`, dạng `CHUC_NANG:THAO_TAC`; app đã đọc ở `StaffRoot._loadPermissions`.
- Điều dưỡng làm được mọi việc thực hiện của Nhân viên chăm sóc (nghiệp vụ 2.4, Q-214); chiều ngược lại không.
- DESIGN.md (kho Elder_Care_Frontend) mục 15.4 hiện ghi điều hướng "lấy theo loại tài khoản và quyền backend trả". Phải sửa mục này cùng đợt với mã (luật của dự án: đổi quy định giao diện thì sửa DESIGN.md cùng PR ở kho web).
- Nhánh đang có thay đổi chưa commit ở `portal_screen.dart`, `today_screen.dart`, `my_shifts_screen.dart`, `sos_button.dart`, `app_theme.dart`; việc này làm trên nền đó, không ghi đè.
- Giao diện app nhân viên theo Figma trang 03 · App nhân viên (`Zj7ld822EmJDruIkhn4Rnf`, node `3:4`); chỗ lệch Figma ghi rõ ở mục 5.
- Người dùng tự commit; chỉ `git add`.

## 4. Cách làm đã chọn

**Các cách đã cân nhắc**

| Cách | Mô tả | Được | Mất |
|---|---|---|---|
| **A. Bảng cấu hình vai trò trong app** (chọn) | Một file Dart khai báo cho mỗi mã vai trò: tab đầu, các mục "Thêm", mỗi mục kèm điều kiện quyền. `StaffRoot` dựng thanh dưới từ bảng này giao với quyền | Không đụng backend; một chỗ duy nhất để xem và sửa "vai trò nào thấy gì"; test được bằng bảng | Đổi danh sách phải ra bản app mới |
| B. Backend trả menu | Thêm endpoint trả danh sách mục theo tài khoản | Đổi menu không cần ra bản app | Phải sửa backend, hợp đồng, glossary; ngoài phạm vi anh muốn |
| C. Mỗi vai trò một màn gốc riêng | `NurseRoot`, `KitchenRoot`… | Từng màn gốc đơn giản | Lặp mã thông báo, khẩn cấp, đồng bộ ở 5 chỗ; người nhiều vai trò không gộp được |

Chọn A vì không cần backend và gộp nhiều vai trò dễ. B, C bị loại vì lý do ở bảng. Đây là lựa chọn của người viết, anh đổi được.

**Luật dựng điều hướng nhân viên**

1. Đọc `roles` từ `GET /me`, lưu vào kho trên máy cùng `userType` (như `session.userType` hiện nay) để mở ngoại tuyến vẫn có.
2. Vai trò app nhân viên = `roles` ∩ {AC-02, AC-03, AC-04, AC-05, AC-07}. Rỗng (chỉ có AC-01, AC-09, AC-14) → màn "Vai trò của bạn dùng trên web" (mục 5.3).
3. Danh sách mục = hợp các mục của mọi vai trò app; mục trùng chỉ hiện một lần.
4. Mỗi mục chỉ hiện khi điều kiện quyền của nó đúng với `/me/permissions` (hoặc điều kiện nhiệm vụ, như `_readinessDuty` hiện nay). Chưa tải được quyền và không có bản lưu: chỉ hiện các mục không cần quyền (Thông báo, Hỗ trợ khẩn cấp) và Checklist ca nếu có bộ nhớ đệm ca (cách `CareTasksHomeScreen` đang làm khi `ApiUnreachable`).
5. Tab 2 lấy theo vai trò ưu tiên cao nhất mà tài khoản có: Trưởng tầng > Điều dưỡng > Nhân viên chăm sóc > Bác sĩ > Nhân viên bếp. Thứ tự này là lựa chọn của người viết (Trưởng tầng thường là người phụ trách ca, cần thấy cả tầng).

## 5. Nhân viên

Khung theo Figma "Elder Care — Thiết kế lại Web + App Base", trang **03 · App nhân viên** (`Zj7ld822EmJDruIkhn4Rnf`, node `3:4`), anh chốt 2026-11-20 "Figma + bổ sung": giữ bố cục, thanh dưới và các màn của Figma, bổ sung phần Figma chưa vẽ (đánh dấu **[bổ sung]**). Figma mới vẽ cho nhân viên làm tại tầng (Điều dưỡng, Nhân viên chăm sóc); vai trò khác dùng cùng khung, thay tab 2.

### 5.1. Khung chung

- **Thanh dưới (Figma):** **Ca của tôi · [tab 2 theo vai trò] · Tra cứu · Thông báo · Thêm**. Tab 2 mặc định là **Checklist** (Checklist ca); vai trò khác xem 5.2.
- **Ca của tôi** = trang chủ của ca (Figma node `5:5`), không phải lịch ca:
  - Thẻ ca hiện tại: "Ca sáng · Tầng 2", giờ ca, "Còn x giờ", thanh tiến độ (DESIGN.md 15.4). Ngoài ca: ca sắp tới gần nhất.
  - **Cần làm ngay**: cảnh báo khẩn cấp chưa tiếp nhận (mở màn Cảnh báo khẩn cấp, node `5:404`), kèm nút **Báo sự cố** (`RecordIncidentScreen`) **[bổ sung]**.
  - **Công việc trong ca**: Checklist ca ("2 việc quá hạn"), Bàn giao ca, và **Lịch ca và đơn** **[bổ sung]** mở `MyShiftsScreen` (lịch ca), từ đó sang `ShiftSwapsScreen` (gửi đơn đổi ca, nghỉ; duyệt với người có quyền).
  - Figma có dòng **Phát thuốc** ở đây: **bỏ** theo quyết định gộp vào checklist (mục 5.2 ghi chú).
- **Hỗ trợ khẩn cấp [bổ sung]** (Q-375): nút đỏ trên đầu màn của mọi màn có thanh dưới, mở `EmergencyAssistScreen`. Figma chưa vẽ; người làm đặt ở góc phải khối đầu màn xanh đêm, nhãn chữ "Khẩn cấp" kèm biểu tượng, vùng bấm ≥ 48.
- **Tra cứu** (Figma `5:438`, `10:68`): `ResidentLookupScreen`, tìm theo họ tên, mã, phòng trong phạm vi phụ trách; bấm dòng mở hồ sơ.
- **Thông báo** (Figma `5:328`): `StaffInboxScreen`, nhóm "Cần xử lý" / "Đã tiếp nhận"; giữ huy hiệu Khẩn cấp và dải đỏ khi ở tab khác như hiện nay.
- **Thêm** (Figma `5:603`): hai nhóm dòng như Figma. Nhóm 1 việc trong ca theo vai trò (5.2); nhóm 2 công cụ: Đồng bộ (`SyncResultsScreen`), Chờ xem lại (`PendingReviewScreen`), Mở khóa sớm (`EarlyUnlockScreen`), Mã đăng nhập (mục 9). Dòng Đồng bộ, Chờ xem lại có số đếm bên phải khi có bản ghi. Figma có **Phê duyệt**: **bỏ** (việc của Quản lý viện, chỉ ở web); duyệt đổi ca và nghỉ đã nằm trong `ShiftSwapsScreen`.
- **Sự cố, cảnh báo**: không có tab riêng (Figma không có). Vào qua Cần làm ngay ở Ca của tôi, qua Thông báo; danh sách đầy đủ (`IncidentsScreen`, `AlertsScreen`) là dòng trong Thêm với người có quyền `INCIDENT_EMERGENCY` hoặc `ALERT_HANDLING`.
- **Đăng xuất**: Figma không vẽ trên các tab; đặt cuối danh sách Thêm (máy dùng chung tại tầng vẫn cần thoát nhanh).
- Dải "Đang ngoại tuyến. Bản ghi sẽ đồng bộ khi có mạng." theo Figma (`5:142`) và DESIGN.md 15.5.

### 5.2. Theo vai trò

| Vai trò | Tab 2 | "Thêm", nhóm việc |
|---|---|---|
| Điều dưỡng (AC-04) | **Checklist** (Figma `5:100`): nhóm Quá hạn / Bây giờ / Sau đó; gồm liều thuốc | Tiếp nhận thuốc (`SuppliedIntakeScreen`, quyền `MEDICATION_RECEIPT:CREATE`), Sự cố, Cảnh báo |
| Nhân viên chăm sóc (AC-05) | **Checklist**: checklist, đo chỉ số (Figma `5:208`), ghi việc ngoài kế hoạch, điểm danh bán trú | Xác nhận phục vụ suất ăn (`ServingConfirmationScreen`), Nhận phiếu bữa ăn tại tầng (`MealSlipScreen`), Điểm danh hoạt động (`SessionListScreen`), Chuyến ngoài viện (`TripListScreen`), Sự cố |
| Trưởng tầng (AC-02) | **Tầng hôm nay** **[bổ sung]**: việc quá hạn của tầng (`OverdueTasksScreen`), lập việc cho ca (`ShiftTaskPlanningScreen`), kiểm tra chất lượng; cùng kiểu dòng của Checklist | Phân công (`AssignmentsScreen`), Giường chờ sẵn sàng (`BedsScreen`), Hoạt động và chuyến, Sự cố, Cảnh báo |
| Bác sĩ (AC-03) | **Người cao tuổi** **[bổ sung]**: tra cứu kèm sức khỏe, đánh giá, dấu nguy kịch (`ResidentLookupScreen` → màn sức khỏe, `AssessmentScreen`, `CriticalCareScreen`). Tab Tra cứu của khung bỏ với vai trò này để không trùng | Cảnh báo, Sự cố, Duyệt kế hoạch chăm sóc (mục 9) |
| Nhân viên bếp (AC-07) | **Phiếu bữa ăn** **[bổ sung]** (`MealSlipScreen`): chuẩn bị, dán nhãn, giao, xác nhận phát sinh | Sự cố, Đồ ăn gia đình (mục 9) |

- Bàn giao ca (Figma `5:558`) mở từ Ca của tôi; có ở Điều dưỡng, Nhân viên chăm sóc, Trưởng tầng khi có quyền `SHIFT_HANDOVER:VIEW`.
- Mở khóa sớm ở nhóm công cụ của Thêm cho Trưởng tầng và Điều dưỡng (Người phụ trách ca phải có một trong hai vai trò, nghiệp vụ 2.4). Backend lọc người được mở (`GET /early-unlock-candidates`), ngoài ca phụ trách màn chỉ báo danh sách trống.
- Bác sĩ: thanh dưới còn 4 tab (Ca của tôi · Người cao tuổi · Thông báo · Thêm).
- Mọi mục vẫn qua điều kiện quyền như `StaffRoot` hiện nay; mục hiện chưa có điều kiện (Tra cứu, Xác nhận phục vụ suất ăn, Phiếu bữa ăn…) nay chỉ hiện ở vai trò có trong bảng. Người làm gán điều kiện quyền nếu backend có mã chức năng tương ứng; không có thì chỉ lọc theo vai trò.
- **Phát thuốc** không còn là mục riêng (anh chốt, khác Figma). Liều thuốc là dòng trong Checklist, nhãn "Quá hạn"/giờ dự kiến như các việc khác, có dấu đã xong ([care_checklist_screen.dart:247](../../../lib/staff/care_tasks/care_checklist_screen.dart) đang chỉ hiện chữ). Bấm dòng thuốc mở màn **Đối chiếu liều thuốc** của Figma (`5:290`: người cao tuổi, dị ứng, liều theo y lệnh, giờ dự kiến), dùng phần ghi liều hiện có (`dose_sheet.dart`, API thuốc). Màn danh sách Phát thuốc của Figma (`5:242`) không dùng. Backend vẫn tách liều thuốc khỏi công việc (`MEDICATION_IS_NOT_A_TASK`, nghiệp vụ 11.3), nên giữ luật riêng: lý do không cho uống, liều kiểm soát đặc biệt phải có mạng, đối chiếu.
- Thực đơn tuần, danh mục món, duyệt thực đơn: chỉ ở web.
- Không còn đường vào trên app: Phê duyệt chung (`ApprovalInboxScreen`), Đón người cao tuổi (`pickups/`), Tiếp nhận đồ gửi (`belongings/`). Mã giữ nguyên, chỉ không gắn vào điều hướng.

### 5.3. Vai trò chỉ có ở web

Tài khoản nhân viên không có vai trò app (mục 4 luật 2): sau đăng nhập hiện một màn đơn: "Vai trò của bạn dùng trên web quản trị", địa chỉ web nếu app có cấu hình, nút Đăng xuất. Không thanh dưới, không gọi API nghiệp vụ.

## 6. Người thân

Thanh dưới **cố định 5 tab** (anh chốt): **Hôm nay · Lịch thăm · Chi phí · Thông báo · Thêm**. Ai cũng thấy đủ 5 tab cùng vị trí. Tab thiếu quyền vẫn mở được, nội dung là một câu nói rõ lý do và cách được cấp, ví dụ: "Bạn chưa được cấp quyền xem chi phí của bà Lan. Liên hệ người đại diện hoặc viện để được cấp."

Người thân của nhiều người cao tuổi: chọn người ở đầu màn (thay cho danh sách ở `PortalScreen`); mọi tab và quyền tính theo người đang chọn; chỉ một người thì không có ô chọn.

| Chức năng | Tab | Ai thấy |
|---|---|---|
| Tình trạng chăm sóc, lịch sinh hoạt, hoạt động hôm nay | Hôm nay | Mọi người thân có quan hệ Hiệu lực |
| Bữa ăn: thực đơn chung 7 ngày tới | Hôm nay | Mọi người thân (012 FR-046; có trong `GET /family-portal/residents/{id}/general`, app chưa hiện) |
| Bữa ăn: chế độ ăn riêng | Hôm nay | Quyền xem sức khỏe có tác dụng (đang ở mục `diet` của màn Sức khỏe) |
| Sự cố gần đây, phần chung | Hôm nay | Mọi người thân (Q-105, Q-352) |
| Sức khỏe | Hôm nay, khối riêng mở `HealthScreen` | Quyền xem sức khỏe có tác dụng; không có thì dòng giải thích `_healthLock` hiện có, không có nút |
| Đăng ký thăm, lượt thăm của tôi | Lịch thăm (`VisitRegistrationScreen`) | Quyền đăng ký thăm |
| Số dư, bảng chi phí, chứng từ, thông tin nộp tiền | Chi phí (`FamilyBalanceScreen`, `FamilyCostsScreen`, `FamilyDocumentsScreen`) | Quyền xem chi phí |
| Đồng ý đề nghị mua hộ | Chi phí (`PurchaseConsentScreen`), huy hiệu khi có đề nghị chờ | Chỉ người đại diện |
| Thông báo, kể cả xác nhận người nhận đồ gửi | Thông báo (`FamilyInboxScreen`) | Mọi người thân |
| Yêu cầu chờ xác nhận | Thêm (`RightChangeRequestsScreen`), huy hiệu | Chỉ người đại diện |
| Yêu cầu thay đổi dịch vụ | Thêm (`ChangeRequestScreen`, hiện chưa có đường vào) | Chỉ người đại diện (BR-M10-01) |
| Hợp đồng, Tiến trình tiếp nhận | Thêm (`ContractScreen`, `AdmissionProgressScreen`, hiện chưa có đường vào) | Chỉ người đại diện |
| Đồ gửi | Thêm (`FamilyBelongingsScreen`) | Người đại diện hoặc có quyền được phép đón (điều kiện `_belongings` hiện có) |
| Phản hồi | Thêm (`FeedbackScreen`) | Mọi người thân |
| Hồ sơ, đổi mật khẩu, đăng xuất | Thêm (`FamilyProfileScreen`) | Mọi người thân |

Tab Chi phí với người đại diện không có quyền xem chi phí: vẫn hiện phần Đề nghị mua hộ, chỉ phần số dư, bảng chi phí thay bằng câu thiếu quyền.

## 7. Người cao tuổi

Giữ đúng chức năng hiện có của `TodayScreen` (nghiệp vụ 14.6a, BR-M10-11): Lịch hôm nay, Bữa ăn, Hoạt động, Người đến thăm, Đồ của tôi, Góp ý với viện, Thông báo, SOS. Không thêm sức khỏe, chi phí, số dư, đăng ký thăm.

- Nút SOS to, cố định ở chân màn, dùng được khi chưa mở khóa (như `sos_button.dart`).
- Khối "Sắp tới" ở đầu: một việc gần giờ hiện tại nhất lấy từ lịch, bữa ăn, lượt thăm đã tải.
- Các mục còn lại là dòng chữ lớn, mỗi mục một việc, theo DESIGN.md 15.6.
- `today_screen.dart` đang có thay đổi chưa commit; làm tiếp trên đó.

## 8. Kiểm chứng

- Test bảng cho luật dựng điều hướng: với mỗi tổ hợp vai trò (từng vai trò; AC-02+AC-04; chỉ AC-09; AC-04 bị thu hẹp mất `MEDICATION_RECEIPT:CREATE`) ra đúng tab 2 và đúng tập mục. Thay `staff_root_more_items_test.dart` hiện có.
- Test ngoại tuyến: không có mạng, có vai trò đã lưu và bộ nhớ đệm ca → Điều dưỡng vào được Ca hôm nay.
- Test người thân: đủ 5 tab với mọi tổ hợp quyền; tab thiếu quyền hiện câu giải thích; người không phải đại diện không thấy ba mục chỉ cho đại diện.
- `flutter analyze`, `flutter test` xanh.
- Chạy app với dữ liệu demo (`demo-full-data.sql`): đăng nhập `dd.nguoithan01` (2 người cao tuổi), một tài khoản mỗi vai trò nhân viên, chụp màn đầu từng vai trò.

## 9. Để làm cuối (anh hoãn 2026-11-20)

Ba mục chưa chốt có lên mobile không: Mã đăng nhập cho người cao tuổi (Điều dưỡng), Duyệt kế hoạch chăm sóc (Bác sĩ, `care_plans_screen.dart`), Đồ ăn gia đình (Bếp, `FamilyFoodScreen`). Trong lúc chờ: giữ trong "Thêm" của vai trò ghi ở bảng 5.2, vẫn lọc theo quyền, không thiết kế lại.

## 10. Để người làm tự quyết

- Tên file, cấu trúc bảng cấu hình vai trò (gợi ý `lib/staff/staff_navigation.dart`).
- Bố cục chi tiết của "Tầng hôm nay", "Phiếu bữa ăn" làm tab, nút Hỗ trợ khẩn cấp trên đầu màn và khối "Sắp tới" của người cao tuổi, theo Figma, DESIGN.md mục 0 và 15. Nên vẽ bổ sung lên Figma trước khi làm mã.
- Câu chữ của các dòng thiếu quyền, theo giọng văn DESIGN.md.
- Đoạn sửa DESIGN.md 15.4: điều hướng theo loại tài khoản, vai trò (bảng ở tài liệu này) giao với quyền backend; thanh dưới người thân cố định 5 tab.
