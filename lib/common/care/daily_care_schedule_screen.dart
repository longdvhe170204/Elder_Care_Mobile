import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/api_client.dart';
import '../api/problem_message.dart';
import '../format/date_time.dart';
import '../widgets/page_body.dart';
import '../widgets/status_pill.dart';

/// "Lịch chăm sóc hằng ngày" (012 FR-076, FR-083 (a); 005 FR-055; Q-416), dùng chung cho app người thân
/// (`/family-portal/residents/{id}/daily-care-schedule`) và app người cao tuổi (`/resident-channel/daily-care-schedule`).
/// Mốc chung, giờ bữa, hoạt động chỉ có giờ và tên; công việc chăm sóc có trạng thái rút gọn; giá trị đo chỉ khi backend
/// trả (người thân có quyền xem sức khỏe có tác dụng). Chỉ xem. Cùng chữ với web `family-portal/CareSchedulePage.jsx`.
const dailyCareStatusLabels = {'DONE': 'Hoàn thành', 'NOT_DONE': 'Chưa hoàn thành', 'NOT_PERFORMED': 'Không thực hiện'};

StatusTone dailyCareStatusTone(String status) => status == 'DONE' ? StatusTone.settled : StatusTone.neutral;

/// Ngày hôm nay theo giờ Việt Nam, dạng yyyy-MM-dd.
String todayInVietnam([DateTime? now]) {
  final vn = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
  return isoDate(vn);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class DailyCareScheduleScreen extends StatefulWidget {
  const DailyCareScheduleScreen({super.key, required this.api, required this.path, this.residentName, this.today});

  final ApiClient api;

  /// Đường dẫn API không kèm `?date=`.
  final String path;
  final String? residentName;

  /// Ngày mặc định (yyyy-MM-dd); để trống là hôm nay theo giờ Việt Nam.
  final String? today;

  @override
  State<DailyCareScheduleScreen> createState() => _DailyCareScheduleScreenState();
}

class _DailyCareScheduleScreenState extends State<DailyCareScheduleScreen> {
  late String _date = widget.today ?? todayInVietnam();
  Map<String, dynamic>? _data;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _data = null;
      _error = null;
    });
    try {
      final data = await widget.api.get('${widget.path}?date=$_date');
      if (mounted && request == _request) setState(() => _data = data ?? const {});
    } on Exception catch (e) {
      if (mounted && request == _request) setState(() => _error = backendMessage(e));
    }
  }

  void _shift(int days) {
    final d = DateTime.parse(_date).add(Duration(days: days));
    _date = isoDate(d);
    _load();
  }

  Future<void> _pick() async {
    final current = DateTime.parse(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 1, 12, 31),
    );
    if (picked == null) return;
    _date = isoDate(picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final items = ((_data?['items'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>();
    return PageBody(
      child: ListView(
        children: [
          if (widget.residentName != null) Text(widget.residentName!, style: text.titleMedium),
          Row(
            children: [
              IconButton(tooltip: 'Ngày trước', onPressed: () => _shift(-1), icon: const Icon(LucideIcons.chevronLeft)),
              Expanded(
                child: TextButton(
                  onPressed: _pick,
                  child: Text('Ngày ${formatDate(_date)}', style: text.titleMedium),
                ),
              ),
              IconButton(tooltip: 'Ngày sau', onPressed: () => _shift(1), icon: const Icon(LucideIcons.chevronRight)),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: text.bodyLarge)
          else if (_data == null)
            const Center(child: CircularProgressIndicator())
          else if (_data!['available'] == false)
            Text('Lịch chăm sóc chưa có dữ liệu, tính năng nguồn chưa hoạt động.', style: text.bodyLarge)
          else if (items.isEmpty)
            Text('Ngày này chưa có mục nào trong lịch.', style: text.bodyLarge)
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: ListTile.divideTiles(
                  context: context,
                  tiles: [
                    for (final item in items)
                      ListTile(
                        minTileHeight: 56,
                        leading: SizedBox(
                          width: 52,
                          child: Text(formatTime(DateTime.parse(item['at'] as String)), style: text.titleSmall),
                        ),
                        title: Text('${item['name'] ?? ''}'),
                        subtitle: item['measuredValue'] == null ? null : Text('Kết quả đo: ${item['measuredValue']}'),
                        trailing: item['status'] == null
                            ? null
                            : StatusPill(
                                label: dailyCareStatusLabels[item['status']] ?? '${item['status']}',
                                tone: dailyCareStatusTone(item['status'] as String),
                              ),
                      ),
                  ],
                ).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
