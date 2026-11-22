import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';

// Kế hoạch chăm sóc của người cao tuổi trong ca (luồng 2.2 SRS, bước "Xem kế hoạch chăm sóc"): chỉ xem phiên bản Đang
// hiệu lực (GET /residents/{id}/care-plans). Bác sĩ lập, ban hành kế hoạch trên web (Q-414, không còn duyệt). Chạm từng người mới tải.

const _roles = {
  'CAREGIVER': 'Nhân viên chăm sóc',
  'NURSING_STAFF': 'Điều dưỡng',
  'DOCTOR': 'Bác sĩ',
  'FLOOR_MANAGER': 'Trưởng tầng',
};
const _importance = {'IMPORTANT': 'Quan trọng', 'MANDATORY': 'Bắt buộc'};

String _hm(Object? time) {
  final value = time as String? ?? '';
  return value.length >= 5 ? value.substring(0, 5) : value;
}

String _frequency(Map<String, dynamic> item) {
  final times = (item['times'] as List? ?? []).map(_hm).join(', ');
  return switch (item['frequencyType']) {
    'TIMES_PER_DAY' =>
      '${item['timesPerDay'] ?? (item['times'] as List? ?? []).length} lần mỗi ngày'
          '${times.isEmpty ? '' : ': $times'}',
    'EVERY_N_HOURS' =>
      'Mỗi ${item['intervalHours']} giờ${item['startsAt'] == null ? '' : ' từ ${_hm(item['startsAt'])}'}',
    'DAYS_OF_WEEK' => 'Theo thứ trong tuần${times.isEmpty ? '' : ': $times'}',
    'ONCE_PER_SHIFT' => 'Mỗi ca một lần',
    final other => '$other',
  };
}

class CarePlansScreen extends StatelessWidget {
  const CarePlansScreen({super.key, required this.api, required this.residents});
  final ApiClient api;

  /// {id, name} của người cao tuổi có việc trong ca.
  final List<Map<String, dynamic>> residents;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kế hoạch chăm sóc')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (residents.isEmpty) const Text('Ca chưa có công việc của người cao tuổi nào.'),
        for (final r in residents)
          Card(
            child: ExpansionTile(
              title: Text(r['name'] as String? ?? 'Người cao tuổi ${r['id']}'),
              children: [_ResidentPlan(api: api, residentId: r['id'] as int)],
            ),
          ),
      ],
    ),
  );
}

class _ResidentPlan extends StatefulWidget {
  const _ResidentPlan({required this.api, required this.residentId});
  final ApiClient api;
  final int residentId;
  @override
  State<_ResidentPlan> createState() => _ResidentPlanState();
}

class _ResidentPlanState extends State<_ResidentPlan> {
  Map<String, dynamic>? _plan;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final plans = await widget.api.getList('/residents/${widget.residentId}/care-plans');
      if (!mounted) return;
      setState(() {
        _plan = plans
            .map((p) => Map<String, dynamic>.from(p as Map))
            .where((p) => p['status'] == 'EFFECTIVE')
            .firstOrNull;
        _loaded = true;
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = backendMessage(e);
          _loaded = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plan = _plan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Text(_error!)
          : plan == null
          ? const Text('Chưa có kế hoạch chăm sóc đang hiệu lực.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Kế hoạch lần ${plan['revision']}'
                  '${plan['effectiveFrom'] == null ? '' : ', hiệu lực từ ${formatDate(plan['effectiveFrom'] as String)}'}',
                  style: text.titleSmall,
                ),
                for (final item in (plan['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i as Map)))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['content'] as String? ?? '', style: text.bodyLarge),
                        Text(
                          [
                            _frequency(item),
                            _roles[item['performerRole']] ?? '${item['performerRole']}',
                            ?_importance[item['importance']],
                          ].join(' · '),
                          style: text.bodySmall,
                        ),
                        if (item['waterTargetMl'] != null)
                          Text('Mục tiêu nước ${item['waterTargetMl']} ml/ngày', style: text.bodySmall),
                      ],
                    ),
                  ),
                if ((plan['items'] as List? ?? []).isEmpty) const Text('Kế hoạch chưa có mục công việc.'),
              ],
            ),
    );
  }
}
