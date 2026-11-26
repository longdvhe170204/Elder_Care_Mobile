// Tên loại cảnh báo do hệ thống tạo (mã loại trong api-007 `Alert.type`), như web Elder_Care_Frontend
// src/features/alerts/alertView.js; cảnh báo thủ công mang mã loại sự cố nên hiện "Cảnh báo".
const _alertTypeNames = {
  'CHI_SO': 'Chỉ số vượt ngưỡng',
  'WEIGHT_LOSS': 'Sụt cân',
  'MISSED_MEASUREMENT': 'Bỏ lỡ lần đo theo lịch',
  'MEDICATION_REFUSAL': 'Từ chối thuốc liên tiếp',
  'PROLONGED_INSOMNIA': 'Mất ngủ kéo dài',
  'LOW_WATER_INTAKE': 'Uống nước chưa đủ',
  'PROLONGED_POOR_EATING': 'Ăn kém kéo dài',
  'PROLONGED_NEGATIVE_MOOD': 'Tâm trạng tiêu cực kéo dài',
  'OVERDUE_CARE_TASK': 'Công việc Bắt buộc quá hạn',
  'MISSING_ON_RETURN': 'Thiếu người khi về',
  'BO_LO_LIEU': 'Bỏ lỡ liều thuốc',
  'XUNG_DOT_DI_UNG': 'Xung đột dị ứng thuốc',
  'PHAN_UNG_THUOC': 'Phản ứng thuốc',
  'POSSIBLE_DUPLICATE_DOSE': 'Nghi dùng trùng liều',
  'CHUA_DOI_CHIEU': 'Thuốc chưa đối chiếu',
  'DIET_ALLERGY_CONFLICT': 'Xung đột dị ứng với chế độ ăn',
  'CRITICAL_CONDITION': 'Tình trạng nguy kịch',
  'RESIDENT_HELP_REQUEST': 'Người cao tuổi bấm nút SOS',
  'STAFF_ASSIST_REQUEST': 'Nhân viên bấm nút hỗ trợ khẩn cấp',
};

String alertTypeName(String? type) => _alertTypeNames[type] ?? 'Cảnh báo';

/// Nhãn "Đang theo dõi" của một người cao tuổi từ `openAlerts` của checklist (005 FR-057, Q-419); null khi không có.
String? followingLabel(List<dynamic>? openAlerts, Object? residentId) {
  if (residentId == null || openAlerts == null) return null;
  final names = <String>{
    for (final a in openAlerts)
      if ((a as Map)['residentId'] == residentId) alertTypeName(a['type'] as String?),
  };
  return names.isEmpty ? null : 'Đang theo dõi: ${names.join(', ')}';
}
