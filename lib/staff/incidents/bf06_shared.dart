import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/api/api_client.dart';

// Phần dùng chung của luồng BF-06 trên app nhân viên (cảnh báo, sự cố, nút hỗ trợ khẩn cấp): nhãn, biểu tượng, tra
// tên và phòng của người cao tuổi, ô chọn loại sự cố, gửi phiếu tóm tắt chuyển viện. Chỉ các màn BF-06 dùng file này.

String newIdempotencyKey() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

const levelNames = {'CRITICAL': 'Khẩn cấp', 'MEDIUM': 'Trung bình', 'LOW': 'Nhẹ'};
const levelOrder = ['CRITICAL', 'MEDIUM', 'LOW'];

/// Việc của từng mức (nghiep-vu.md 9.3), hiện ngay dưới nút chọn mức.
const levelMeaning = {
  'CRITICAL': 'Báo ngay bác sĩ trực, trưởng tầng, quản lý và người liên hệ chính.',
  'MEDIUM': 'Điều dưỡng xử lý, báo bác sĩ khi cần. Tiếp nhận trong 15 phút.',
  'LOW': 'Ghi nhận, điều dưỡng theo dõi trong ca.',
};

const alertStatusNames = {
  'NEW': 'Mới',
  'ESCALATED': 'Leo thang',
  'RECEIVED': 'Đã tiếp nhận',
  'IN_PROGRESS': 'Đang xử lý',
  'CLOSED': 'Đã đóng',
  'CONVERTED_TO_INCIDENT': 'Đã chuyển sự cố',
};

const incidentStatusNames = {
  'NEW': 'Mới',
  'IN_PROGRESS': 'Đang xử lý',
  'MONITORING': 'Đang theo dõi',
  'CLOSED': 'Đã đóng',
  'VOIDED': 'Đã hủy',
};

/// Nơi đã chọn của nút SOS, nút hỗ trợ (cùng chữ với app người cao tuổi).
const placeNames = {
  'ROOM': 'Ở phòng',
  'RESTROOM': 'Nhà vệ sinh',
  'CORRIDOR': 'Hành lang',
  'COMMON_ROOM': 'Phòng sinh hoạt chung',
  'YARD': 'Ngoài sân',
  'OTHER': 'Chỗ khác',
};

const placeIcons = {
  'ROOM': LucideIcons.bed,
  'RESTROOM': LucideIcons.toilet,
  'CORRIDOR': LucideIcons.doorOpen,
  'COMMON_ROOM': LucideIcons.sofa,
  'YARD': LucideIcons.trees,
  'OTHER': LucideIcons.mapPin,
};

/// Loại sự việc của nút hỗ trợ khẩn cấp (backend chỉ có bốn loại).
const assistEvents = [
  ('CARDIAC_ARREST_OR_FAINTING', 'Ngừng tim, ngất', LucideIcons.heartPulse),
  ('FALL', 'Ngã', LucideIcons.personStanding),
  ('AGITATION_OR_VIOLENCE', 'Kích động', LucideIcons.angry),
  ('OTHER', 'Khác', LucideIcons.stethoscope),
];

/// Thứ tự hiện loại sự cố từ trên xuống: việc thường gấp trước, đồ đạc và cơ sở vật chất sau; tên ngắn và biểu tượng.
const _typeOrder = [
  'BREATHING_OR_CONSCIOUSNESS',
  'CHOKING_OR_AIRWAY_OBSTRUCTION',
  'FALL',
  'MISSING_OR_NOT_RETURNED',
  'MEDICATION',
  'WRONG_MEAL_SERVED',
  'BEHAVIOR',
  'OTHER_INJURY',
  'SUSPECTED_INFECTION',
  'OTHER_HEALTH_CARE',
  'BELONGINGS_LOST',
  'BELONGINGS_DAMAGED',
  'FACILITY',
];

const _typeShortNames = {
  'BREATHING_OR_CONSCIOUSNESS': 'Khó thở, mất ý thức',
  'CHOKING_OR_AIRWAY_OBSTRUCTION': 'Sặc, nghẹn',
  'FALL': 'Ngã',
  'MISSING_OR_NOT_RETURNED': 'Đi lạc, không về',
  'MEDICATION': 'Thuốc',
  'WRONG_MEAL_SERVED': 'Suất ăn',
  'BEHAVIOR': 'Kích động',
  'OTHER_INJURY': 'Chấn thương',
  'SUSPECTED_INFECTION': 'Lây nhiễm',
  'OTHER_HEALTH_CARE': 'Sức khỏe khác',
  'BELONGINGS_LOST': 'Đồ thất lạc',
  'BELONGINGS_DAMAGED': 'Đồ hư hỏng',
  'FACILITY': 'Cơ sở vật chất',
};

const _typeIcons = {
  'BREATHING_OR_CONSCIOUSNESS': LucideIcons.heartPulse,
  'CHOKING_OR_AIRWAY_OBSTRUCTION': LucideIcons.wind,
  'FALL': LucideIcons.personStanding,
  'MISSING_OR_NOT_RETURNED': LucideIcons.mapPinOff,
  'MEDICATION': LucideIcons.pill,
  'WRONG_MEAL_SERVED': LucideIcons.utensils,
  'BEHAVIOR': LucideIcons.angry,
  'OTHER_INJURY': LucideIcons.bandage,
  'SUSPECTED_INFECTION': LucideIcons.biohazard,
  'OTHER_HEALTH_CARE': LucideIcons.stethoscope,
  'BELONGINGS_LOST': LucideIcons.packageSearch,
  'BELONGINGS_DAMAGED': LucideIcons.packageX,
  'FACILITY': LucideIcons.building2,
};

String typeShortName(Map<String, dynamic> type) => _typeShortNames[type['code']] ?? '${type['name'] ?? 'Sự cố'}';

IconData typeIcon(String? code) => _typeIcons[code] ?? LucideIcons.circleAlert;

/// Danh mục loại sự cố còn dùng, xếp theo [_typeOrder].
Future<List<Map<String, dynamic>>> loadIncidentTypes(ApiClient api) async {
  final rows = (await api.getList(
    '/incident-types',
  )).map((t) => Map<String, dynamic>.from(t as Map)).where((t) => t['status'] != 'INACTIVE').toList();
  int rank(Map<String, dynamic> t) {
    final i = _typeOrder.indexOf(t['code'] as String? ?? '');
    return i < 0 ? _typeOrder.length : i;
  }

  rows.sort((a, b) => rank(a).compareTo(rank(b)));
  return rows;
}

/// Tên, phòng, tầng của người cao tuổi theo `GET /incident-residents` (chỉ họ tên, mã, phòng, tầng); nhớ trong phiên.
class ResidentInfo {
  const ResidentInfo({required this.id, required this.name, this.room, this.floor});
  final int id;
  final String name;
  final String? room;
  final String? floor;

  String get place => [room, floor].whereType<String>().join(' · ');
}

class ResidentDirectory {
  ResidentDirectory(this.api);
  final ApiClient api;
  final Map<int, ResidentInfo> _cache = {};
  Map<int, String>? _names;

  Future<ResidentInfo?> lookup(int? id) async {
    if (id == null) return null;
    final cached = _cache[id];
    if (cached != null) return cached;
    try {
      _names ??= {
        for (final r in ((await api.get('/residents'))?['items'] as List? ?? const []).cast<Map<String, dynamic>>())
          r['id'] as int: '${(r['personalInfo'] as Map?)?['fullName'] ?? 'Người cao tuổi ${r['id']}'}',
      };
      final name = _names![id];
      if (name == null) return null;
      final rows = await search(name);
      final found = rows.where((r) => r.id == id).firstOrNull;
      return _cache[id] = found ?? ResidentInfo(id: id, name: name);
    } on Exception {
      return null;
    }
  }

  /// Tìm trong toàn viện (ít nhất 2 ký tự, tối đa 5 người).
  Future<List<ResidentInfo>> search(String q) async {
    if (q.trim().length < 2) return const [];
    final rows = await api.getList('/incident-residents?q=${Uri.encodeQueryComponent(q.trim())}');
    final found = [
      for (final r in rows.cast<Map<String, dynamic>>())
        ResidentInfo(
          id: r['id'] as int,
          name: '${r['fullName']}',
          room: r['roomName'] as String?,
          floor: r['floorName'] as String?,
        ),
    ];
    for (final r in found) {
      _cache[r.id] = r;
    }
    return found;
  }

  /// Người cao tuổi trong phạm vi của nhân viên (danh sách gợi ý trước khi gõ tìm).
  Future<List<ResidentInfo>> inScope() async {
    final rows = ((await api.get('/residents'))?['items'] as List? ?? const []).cast<Map<String, dynamic>>();
    final list = <ResidentInfo>[];
    for (final r in rows) {
      final id = r['id'] as int;
      list.add(
        _cache[id] ?? ResidentInfo(id: id, name: '${(r['personalInfo'] as Map?)?['fullName'] ?? 'Người cao tuổi $id'}'),
      );
    }
    return list;
  }
}

String hhmm(String? iso) {
  if (iso == null) return '';
  final t = DateTime.parse(iso).toUtc().add(const Duration(hours: 7));
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Giờ Việt Nam dạng ISO có múi giờ, như web `vietnamIso`.
String vietnamIso(DateTime local) {
  final vn = local.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${vn.year}-${two(vn.month)}-${two(vn.day)}T${two(vn.hour)}:${two(vn.minute)}:00+07:00';
}

Future<bool> openDirections(double lat, double lng) => launchUrl(
  Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
  mode: LaunchMode.externalApplication,
);

/// Gửi phiếu PDF qua bảng chia sẻ của máy (Zalo, email, lưu, in). Cùng tệp backend dựng như bản trên web.
Future<void> sharePdf(Uint8List bytes, String name) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: name)],
      fileNameOverrides: [name],
    ),
  );
}

/// Nhãn mức có màu: đỏ chỉ cho Khẩn cấp (DESIGN.md mục 1 điều 4).
class LevelPill extends StatelessWidget {
  const LevelPill(this.level, {super.key});
  final String? level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final critical = level == 'CRITICAL';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: critical ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Text(
          levelNames[level] ?? '$level',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: critical ? scheme.onErrorContainer : scheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Ô chọn lớn: biểu tượng trên, chữ dưới; vùng bấm tối thiểu 72.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.minHeight = 88,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 28, color: selected ? scheme.onPrimary : scheme.primary),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lưới ô chọn [columns] cột; hàng cao theo nội dung để chữ phóng to không tràn.
class ChoiceGrid extends StatelessWidget {
  const ChoiceGrid({super.key, required this.children, this.columns = 3});
  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i += columns) ...[
        if (i > 0) const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = i; j < i + columns; j++) ...[
                if (j > i) const SizedBox(width: 8),
                Expanded(child: j < children.length ? children[j] : const SizedBox.shrink()),
              ],
            ],
          ),
        ),
      ],
    ],
  );
}

/// Chọn loại sự cố bằng ô lớn (dùng khi chuyển cảnh báo thành sự cố). Trả `null` khi bỏ.
Future<Map<String, dynamic>?> pickIncidentType(BuildContext context, List<Map<String, dynamic>> types) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Chuyện gì đã xảy ra?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ChoiceGrid(
              children: [
                for (final t in types)
                  ChoiceTile(
                    icon: typeIcon(t['code'] as String?),
                    label: typeShortName(t),
                    onTap: () => Navigator.of(context).pop(t),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

/// Hỏi một dòng chữ (kết quả xử lý, ghi chú); `null` khi bỏ.
Future<String?> askText(BuildContext context, {required String title, required String label, String action = 'Lưu'}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (context, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              decoration: InputDecoration(labelText: label),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(action),
            ),
          ],
        ),
      ),
    ),
  );
}
