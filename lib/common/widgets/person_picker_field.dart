import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Một người để chọn: mã (ghi vào ô) và nhãn hiện ra.
typedef PersonOption = ({String id, String label});

/// Nhân viên đang làm việc (api-008 `GET /staff`), nhãn "Họ tên (chức vụ)".
Future<List<PersonOption>> loadStaffOptions(ApiClient api) async {
  final rows = (await api.getList('/staff?status=WORKING')).cast<Map<String, dynamic>>();
  return [
    for (final s in rows)
      (id: '${s['id']}', label: s['position'] == null ? '${s['fullName']}' : '${s['fullName']} (${s['position']})'),
  ];
}

/// Người thân có quan hệ Hiệu lực với người cao tuổi (api-012 `GET /residents/{id}/relationships`).
Future<List<PersonOption>> loadFamilyOptions(ApiClient api, int residentId) async {
  final rows = (await api.getList('/residents/$residentId/relationships')).cast<Map<String, dynamic>>();
  return [
    for (final r in rows)
      if (r['status'] == null || r['status'] == 'ACTIVE')
        (
          id: '${(r['familyMember'] as Map<String, dynamic>)['id']}',
          label: '${(r['familyMember'] as Map<String, dynamic>)['fullName']}',
        ),
  ];
}

/// Ô chọn người theo tên thay cho ô nhập mã (demo 2026-11-25, góp ý nhóm). Tải được danh sách thì hiện ô chọn; đang tải
/// hoặc không tải được (thiếu quyền, mất mạng) thì giữ ô nhập mã với [fallbackLabel] như trước. Giá trị luôn ghi vào
/// [controller] (mã dạng chuỗi) để phần gửi lệnh của màn không phải đổi.
class PersonPickerField extends StatefulWidget {
  const PersonPickerField({
    super.key,
    required this.load,
    required this.controller,
    required this.label,
    required this.fallbackLabel,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.enabled = true,
  });

  final Future<List<PersonOption>> Function() load;
  final TextEditingController controller;
  final String label;
  final String fallbackLabel;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  @override
  State<PersonPickerField> createState() => _PersonPickerFieldState();
}

class _PersonPickerFieldState extends State<PersonPickerField> {
  List<PersonOption> _options = const [];

  @override
  void initState() {
    super.initState();
    widget.load().then((options) {
      if (mounted) setState(() => _options = options);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_options.isEmpty) {
      return TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.fallbackLabel,
          helperText: widget.helperText,
          errorText: widget.errorText,
        ),
      );
    }
    final current = widget.controller.text.trim();
    return DropdownButtonFormField<String>(
      initialValue: _options.any((o) => o.id == current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: widget.label, helperText: widget.helperText, errorText: widget.errorText),
      items: [for (final o in _options) DropdownMenuItem(value: o.id, child: Text(o.label))],
      onChanged: widget.enabled
          ? (value) {
              widget.controller.text = value ?? '';
              widget.onChanged?.call(widget.controller.text);
            }
          : null,
    );
  }
}
