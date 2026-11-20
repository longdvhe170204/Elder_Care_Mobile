import 'package:flutter/foundation.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';

/// Người cao tuổi của người thân kèm quyền **có tác dụng** tại lúc xem (`GET /family-portal/residents`, 012 FR-046).
class FamilyResident {
  const FamilyResident({
    required this.id,
    required this.fullName,
    required this.representative,
    required this.rights,
    required this.canViewBelongings,
  });

  factory FamilyResident.fromJson(Map<String, dynamic> json) => FamilyResident(
    id: json['residentId'] as int,
    fullName: json['fullName'] as String,
    representative: json['representative'] == true,
    rights: {
      for (final MapEntry(:key, :value) in ((json['rights'] as Map?) ?? const {}).entries) '$key': value == true,
    },
    canViewBelongings: json['canViewBelongings'] == true,
  );

  final int id;
  final String fullName;
  final bool representative;

  /// `VIEW_HEALTH`, `VIEW_COSTS`, `RECEIVE_URGENT`, `REGISTER_VISITS`, `PICKUP_ALLOWED`, `REQUEST_SERVICES`.
  final Map<String, bool> rights;
  final bool canViewBelongings;

  bool can(String right) => rights[right] == true;

  /// Như mục Đồ gửi của cổng web: người đại diện, người được phép đón (012 FR-046b; backend vẫn kiểm mỗi lần gọi).
  bool get belongings => representative || canViewBelongings || can('PICKUP_ALLOWED');
}

/// Danh sách người cao tuổi của người thân và người đang chọn (spec 2026-11-20 mục 6): mọi tab tính theo người đang chọn.
class FamilySelection extends ChangeNotifier {
  FamilySelection(this.api);

  final ApiClient api;
  List<FamilyResident>? residents;
  FamilyResident? current;
  String? error;

  Future<void> load() async {
    try {
      final rows = (await api.getList('/family-portal/residents')).cast<Map<String, dynamic>>();
      residents = rows.map(FamilyResident.fromJson).toList();
      current = residents!.where((r) => r.id == current?.id).firstOrNull ?? residents!.firstOrNull;
      error = null;
    } on Exception catch (e) {
      error = backendMessage(e);
    }
    notifyListeners();
  }

  void select(int residentId) {
    current = residents?.where((r) => r.id == residentId).firstOrNull ?? current;
    notifyListeners();
  }
}
