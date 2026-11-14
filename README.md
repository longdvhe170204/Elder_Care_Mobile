# Elder_Care app

Một app Flutter chung cho nhân viên, người thân và người cao tuổi; chức năng theo loại tài khoản đăng nhập. "App nhân viên", "app người thân", "app người cao tuổi" trong spec là ba phần của app này.

## Ba kho của hệ thống

| Kho | Nội dung |
| --- | --- |
| [Elder_Care](https://github.com/longdvhe170204/Elder_Care) | Backend (Spring Boot), đặc tả, hợp đồng API, tài liệu nghiệp vụ và quy ước chung |
| [Elder_Care_Frontend](https://github.com/longdvhe170204/Elder_Care_Frontend) | Web cho nhân viên và cổng người thân |
| Elder_Care_Mobile (kho này) | App Flutter |

App chỉ nói chuyện với backend qua API `/api/v1`; client API viết tay theo hợp đồng ở kho backend. Tách khỏi kho Elder_Care ngày 2026-11-14 (trước đó là thư mục `mobile/`), giữ lịch sử commit.

Đọc trước khi viết mã, đều ở kho backend: [AGENTS.md](https://github.com/longdvhe170204/Elder_Care/blob/develop/AGENTS.md), [DESIGN.md](https://github.com/longdvhe170204/Elder_Care/blob/develop/DESIGN.md) (mục 15 riêng cho Flutter, 15.6 phần người cao tuổi), [glossary](https://github.com/longdvhe170204/Elder_Care/blob/develop/specs/000-shared-foundation/glossary.md).

## Yêu cầu

Flutter stable 3.41.9 (Dart `^3.11.5`). Không cần backend để phân tích mã và chạy test.

## Lệnh

```bash
flutter pub get
flutter analyze                                # phải sạch trước khi mở PR
flutter test                                   # một file: flutter test test/<đường dẫn>_test.dart
flutter test --plain-name "<tên test>"
dart format <file>                             # dòng 120 ký tự
dart run build_runner build                    # sinh lại mã drift (*.g.dart) sau khi sửa bảng
```

Thêm package: nhờ A (người giữ `pubspec.yaml`).

CI (`.github/workflows/verify.yml`) chạy `flutter analyze` và `flutter test` khi có PR hoặc push vào `develop`, `main`.

### Lưu ý trên Windows

- **Đường dẫn Flutter có dấu cách** (ví dụ `C:\Users\ADMIN VIP\flutter`): `flutter test` báo `'C:\Users\ADMIN' is not recognized`. Gọi Flutter qua tên ngắn 8.3 (`C:\Users\ADMINV~1\flutter\bin\flutter.bat`) hoặc cài ở thư mục không có dấu cách.
- **Build Android báo "Unable to establish loopback connection"**: đặt `JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\eldercare-tmp` (thư mục phải có sẵn) rồi build lại.
- **`flutter pub get` sửa các file `generated_plugin_registrant`** ở `linux/`, `macos/`, `windows/`: không commit thay đổi đó nếu không thêm, bớt plugin.

### Nhận đẩy (FCM)

Kho công khai nên không có cấu hình Firebase. Muốn nhận đẩy, đặt `google-services.json` vào `android/app/` và `GoogleService-Info.plist` vào `ios/Runner/` (mã app `com.eldercare.mobile`). Thiếu file thì app vẫn build và chạy, chỉ không có đẩy.

## Cấu trúc `lib/`

| Thư mục | Nhiệm vụ |
| --- | --- |
| `main.dart`, `app.dart` | Dựng phiên, đăng nhập xong chuyển sang phần tương ứng với loại tài khoản |
| `common/` | Dùng chung: theme, widget, client API, phiên đăng nhập, hàng đợi ngoại tuyến, định dạng ngày giờ (A duyệt) |
| `staff/<feature>/` | Phần nhân viên; ghi được khi mất mạng |
| `family/<feature>/` | Phần người thân |
| `resident/<feature>/` | Phần người cao tuổi (chữ lớn, vùng bấm lớn, nút SOS) |

Tên thư mục feature giống web, đổi `-` thành `_` (`care_tasks`, `family_portal`…). Test đặt ở `test/` cùng đường dẫn với `lib/`, tên test có mã quy tắc ở đầu. File snake_case; hậu tố `_screen.dart`, `_sheet.dart`, `_form.dart`, `_card.dart`, `_labels.dart`.

## Luật bắt buộc

1. Không import chéo giữa thư mục feature hay giữa `staff/`, `family/`, `resident/`; dùng chung thì đưa lên `common/`.
2. Gọi API chỉ qua `common/api/api_client.dart`; lỗi theo Problem Details như web.
3. Màu, chữ, bo góc chỉ qua theme trong `common/`; không viết `Color(0x…)` hay cỡ chữ thô.
4. Ngày giờ hiển thị dd/MM/yyyy HH:mm giờ Việt Nam; gửi ISO-8601 có `+07:00`.
5. Lệnh ghi khi mất mạng (phần nhân viên) đi qua hàng đợi ngoại tuyến và `/sync`; lệnh bắt buộc trực tuyến thì báo cần mạng.
6. Chữ trên màn tiếng Việt; tên trong mã tiếng Anh theo glossary. Màn chỉ hiện trường có trong spec và hợp đồng.

## Quyết định kỹ thuật đã chốt

- Trạng thái: `ChangeNotifier`; điều hướng: `MaterialApp` đổi màn theo phiên, màn con dùng `Navigator`.
- Client API viết tay, không sinh từ hợp đồng.
- Token lưu bằng `flutter_secure_storage`; hàng đợi ngoại tuyến dùng drift.
- Theme theo DESIGN.md 15.2, font Be Vietnam Pro đóng gói ở `assets/fonts/`, biểu tượng `lucide_icons_flutter`.

Lịch sử các quyết định chi tiết (ngày chốt, task liên quan) xem trong lịch sử commit của file này.
