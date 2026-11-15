import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/notifications/notification_inbox.dart';
import '../../common/notifications/push_coordinator.dart';
import '../belongings/recipient_confirmation_screen.dart';

/// Tab Thông báo của người thân (009 T031): hộp thông báo chung, kèm nút mở màn nguồn mà app người thân có. Thông báo
/// `RECIPIENT_CONFIRMATION_REQUESTED` có nguồn `M12.RECIPIENT_CONFIRMATION` mở màn xác nhận người nhận (013 T019; FR-017,
/// FR-030); nguồn không mở được (`canOpen` false) thì không có nút.
class FamilyInboxScreen extends StatelessWidget {
  const FamilyInboxScreen({super.key, required this.api, this.push});

  final ApiClient api;
  final PushCoordinator? push;

  Widget? _sourceAction(BuildContext context, Map<String, dynamic> n) {
    final source = n['sourceRecord'] as Map<String, dynamic>?;
    if (source == null || source['canOpen'] == false || source['type'] != 'M12.RECIPIENT_CONFIRMATION') return null;
    final id = int.tryParse(source['id'] as String? ?? '');
    if (id == null) return null;
    return OutlinedButton(
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => RecipientConfirmationScreen(api: api, confirmationId: id),
        ),
      ),
      child: const Text('Xem yêu cầu xác nhận'),
    );
  }

  @override
  Widget build(BuildContext context) => NotificationInbox(api: api, push: push, sourceAction: _sourceAction);
}
