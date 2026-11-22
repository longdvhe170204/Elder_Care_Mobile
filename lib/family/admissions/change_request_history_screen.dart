import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';

const _changeTypes = {
  'RESIDENCE_TYPE': 'Loại lưu trú',
  'CARE_LEVEL': 'Mức chăm sóc',
  'SERVICE': 'Dịch vụ',
  'DURATION': 'Thời hạn',
  'BED': 'Giường',
  'ARRIVAL_SCHEDULE': 'Lịch đến',
};
const _careLevels = {'BASIC': 'Cơ bản', 'REGULAR': 'Thường xuyên', 'SPECIAL': 'Đặc biệt'};
const _residenceTypes = {
  'LONG_TERM_RESIDENTIAL': 'Nội trú dài hạn',
  'SHORT_TERM_RESIDENTIAL': 'Nội trú ngắn ngày',
  'DAY_CARE': 'Bán trú',
};

/// Yêu cầu thay đổi lưu trú người đại diện đã gửi (004 FR-039; 000 FR-042: người lập xem được yêu cầu của mình), mới nhất
/// trước, theo từng hợp đồng của người thân (api-012 `GET /family-portal/residents/{residentId}/contract`, api-004
/// `GET /residency-change-requests?contractId=`). Trạng thái theo yêu cầu phê duyệt và phụ lục. Chỉ trực tuyến.
class ChangeRequestHistory extends StatefulWidget {
  const ChangeRequestHistory({super.key, required this.api, required this.residentId});

  final ApiClient api;
  final int residentId;

  @override
  State<ChangeRequestHistory> createState() => _ChangeRequestHistoryState();
}

class _ChangeRequestHistoryState extends State<ChangeRequestHistory> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final body = await widget.api.get('/family-portal/residents/${widget.residentId}/contract');
      final contracts = ((body?['contracts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final items = <Map<String, dynamic>>[];
      for (final c in contracts) {
        final rows = await widget.api.getList('/residency-change-requests?contractId=${c['id']}');
        items.addAll(rows.cast<Map<String, dynamic>>());
      }
      items.sort((a, b) => (b['approvalRequestId'] as int).compareTo(a['approvalRequestId'] as int));
      if (mounted) setState(() => _items = items);
    } on ApiUnreachable {
      if (mounted) setState(() => _error = 'Cần có mạng để xem yêu cầu đã gửi. Kiểm tra kết nối rồi thử lại.');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  static String _date(Object? iso) {
    final d = iso is String ? DateTime.tryParse(iso) : null;
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  static String _newValue(String type, Map<String, dynamic>? value) {
    switch (type) {
      case 'CARE_LEVEL':
        return _careLevels[value?['careLevel']] ?? '';
      case 'RESIDENCE_TYPE':
        return _residenceTypes[value?['residenceType']] ?? '';
      default:
        return '';
    }
  }

  /// Trạng thái hiển thị cho người thân: yêu cầu Đã duyệt thì theo phụ lục (chờ ký, chờ hiệu lực).
  static String status(Map<String, dynamic> r) {
    final addendum = r['addendum'] as Map<String, dynamic>?;
    switch (r['status']) {
      case 'DRAFT':
        return 'Hành chính đang hoàn thiện';
      case 'PENDING_APPROVAL':
        return 'Chờ Quản lý viện duyệt';
      case 'APPROVED':
        if (addendum?['status'] == 'PENDING_SIGNATURE') return 'Đã duyệt, chờ ký phụ lục với viện';
        return 'Đã duyệt, hiệu lực từ ${_date(addendum?['effectiveDate'] ?? r['requestedEffectiveDate'])}';
      case 'APPLIED':
        return 'Đã áp dụng từ ${_date(addendum?['effectiveDate'] ?? r['requestedEffectiveDate'])}';
      case 'APPLY_FAILED':
        return 'Không áp dụng được, liên hệ Hành chính';
      case 'REJECTED':
        return 'Không được duyệt';
      case 'CANCELLED':
        return 'Đã hủy';
      case 'SUPERSEDED':
        return 'Được thay thế bằng yêu cầu mới';
      default:
        return '${r['status']}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: text.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tải lại')),
          ],
        ),
      );
    }
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Bạn chưa gửi đề nghị điều chỉnh hợp đồng nào.', style: text.bodyMedium),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final r = items[i];
          final types = ((r['changeTypes'] as List?) ?? const []).cast<String>();
          final newValue = r['newValue'] as Map<String, dynamic>?;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final t in types)
                    Text(
                      [_changeTypes[t] ?? t, _newValue(t, newValue)].where((s) => s.isNotEmpty).join(': '),
                      style: text.titleSmall,
                    ),
                  const SizedBox(height: 4),
                  Text(status(r), style: text.bodyMedium),
                  const SizedBox(height: 4),
                  Text('Ngày hiệu lực mong muốn ${_date(r['requestedEffectiveDate'])}', style: text.bodySmall),
                  if (r['reason'] is String) Text('Lý do: ${r['reason']}', style: text.bodySmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Đích khi mở thông báo về yêu cầu điều chỉnh hợp đồng (004 M3: `RESIDENCY_CHANGE_SUBMITTED`, `RESIDENCY_CHANGE_OUTCOME`,
/// `ADDENDUM_APPLIED`, nguồn `M02.RESIDENCY_CHANGE`). Thông báo không mang mã người cao tuổi nên tra danh sách người thân
/// đại diện (`GET /residents`): một người thì mở thẳng lịch sử đề nghị, nhiều người thì chọn người. Chỉ trực tuyến.
class ChangeRequestHistoryFromNotice extends StatefulWidget {
  const ChangeRequestHistoryFromNotice({super.key, required this.api});

  final ApiClient api;

  @override
  State<ChangeRequestHistoryFromNotice> createState() => _ChangeRequestHistoryFromNoticeState();
}

class _ChangeRequestHistoryFromNoticeState extends State<ChangeRequestHistoryFromNotice> {
  List<Map<String, dynamic>>? _residents;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await widget.api.get('/residents');
      final items = ((page?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
      if (mounted) setState(() => _residents = items);
    } on ApiUnreachable {
      if (mounted) setState(() => _error = 'Cần có mạng để xem đề nghị. Kiểm tra kết nối rồi thử lại.');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  static String _name(Map<String, dynamic> r) =>
      ((r['personalInfo'] as Map<String, dynamic>?)?['fullName'] as String?) ?? 'Người thân của bạn';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final residents = _residents;
    Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: text.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tải lại')),
          ],
        ),
      );
    } else if (residents == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (residents.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Chưa có người cao tuổi nào để xem đề nghị.', style: text.bodyMedium),
      );
    } else if (residents.length == 1) {
      body = ChangeRequestHistory(api: widget.api, residentId: residents.single['id'] as int);
    } else {
      body = ListView(
        children: [
          for (final r in residents)
            ListTile(
              title: Text(_name(r)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text(_name(r))),
                    body: ChangeRequestHistory(api: widget.api, residentId: r['id'] as int),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Đề nghị đã gửi')),
      body: body,
    );
  }
}
