import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/notifications/notification_inbox.dart';
import '../../common/notifications/push_coordinator.dart';
import '../admissions/change_confirmation_screen.dart';
import '../admissions/change_request_history_screen.dart';
import '../belongings/recipient_confirmation_screen.dart';

/// Tab Thông báo của người thân (009 T031): hộp thông báo chung, kèm nút mở màn nguồn mà app người thân có. Thông báo
/// `RECIPIENT_CONFIRMATION_REQUESTED` có nguồn `M12.RECIPIENT_CONFIRMATION` mở màn xác nhận người nhận (013 T019; FR-017,
/// FR-030); thông báo có nguồn `M02.CHANGE_CONFIRMATION` (đề nghị, nhắc xác nhận thay đổi lưu trú) mở màn xác nhận thay
/// đổi lưu trú (004 T120; FR-043c); nguồn không mở được (`canOpen` false) thì không có nút. Riêng
/// `M02.CHANGE_CONFIRMATION` luôn có nút vì backend 009 chưa tính `canOpen` (luôn false); màn xác nhận tự báo khi đề nghị
/// không còn chờ hoặc không có quyền. Thông báo nguồn `M02.RESIDENCY_CHANGE` (gửi duyệt, kết quả, phụ lục đã áp dụng; 004 M3)
/// mở danh sách đề nghị đã gửi, cùng lý do không dựa vào `canOpen`.
class FamilyInboxScreen extends StatelessWidget {
  const FamilyInboxScreen({super.key, required this.api, this.push});

  final ApiClient api;
  final PushCoordinator? push;

  Widget? _sourceAction(BuildContext context, Map<String, dynamic> n) {
    final source = n['sourceRecord'] as Map<String, dynamic>?;
    if (source == null) return null;
    const alwaysOpen = {'M02.CHANGE_CONFIRMATION', 'M02.RESIDENCY_CHANGE'};
    if (source['canOpen'] == false && !alwaysOpen.contains(source['type'])) return null;
    final id = int.tryParse(source['id'] as String? ?? '');
    if (id == null) return null;
    final Widget screen;
    final String label;
    switch (source['type']) {
      case 'M12.RECIPIENT_CONFIRMATION':
        screen = RecipientConfirmationScreen(api: api, confirmationId: id);
        label = 'Xem yêu cầu xác nhận';
      case 'M02.CHANGE_CONFIRMATION':
        screen = ChangeConfirmationScreen(api: api, confirmationId: id);
        label = 'Xem chi tiết thay đổi';
      case 'M02.RESIDENCY_CHANGE':
        screen = ChangeRequestHistoryFromNotice(api: api);
        label = 'Xem đề nghị đã gửi';
      default:
        return null;
    }
    return OutlinedButton(
      onPressed: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen)),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) => NotificationInbox(api: api, push: push, sourceAction: _sourceAction);
}
