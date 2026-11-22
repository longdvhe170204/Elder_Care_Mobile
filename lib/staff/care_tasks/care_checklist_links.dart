import 'package:flutter/widgets.dart';

/// Lối đi từ Checklist ca sang màn khác (bàn giao ca, kế hoạch chăm sóc, báo sự cố). Màn chứa checklist (có ApiClient)
/// cấp; màn Checklist ca chỉ gọi, nên test dùng bản giả được.
class CareChecklistLinks {
  const CareChecklistLinks({required this.openHandover, required this.openPlans, required this.reportIncident});

  final Future<void> Function(BuildContext context, int shiftId) openHandover;

  /// `residents`: {id, name} của người cao tuổi cần xem kế hoạch chăm sóc.
  final Future<void> Function(BuildContext context, List<Map<String, dynamic>> residents) openPlans;

  /// Mở form báo sự cố, chọn sẵn người cao tuổi nếu có; true khi đã ghi.
  final Future<bool> Function(BuildContext context, int? residentId) reportIncident;
}
