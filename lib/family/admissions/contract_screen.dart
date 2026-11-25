import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';
import '../../common/widgets/status_pill.dart';

const _contractStatus = {
  'DRAFT': ('Nháp', StatusTone.neutral),
  'PENDING_SIGNATURE': ('Chờ ký', StatusTone.attention),
  'ACTIVE': ('Hiệu lực', StatusTone.settled),
  'ENDED': ('Kết thúc', StatusTone.neutral),
  'TERMINATED': ('Chấm dứt', StatusTone.neutral),
  'CANCELLED': ('Đã hủy', StatusTone.neutral),
};

const _residenceTypes = {
  'LONG_TERM_RESIDENTIAL': 'Nội trú dài hạn',
  'SHORT_TERM_RESIDENTIAL': 'Nội trú ngắn ngày',
  'DAY_CARE': 'Bán trú',
};

/// Hợp đồng của những người cao tuổi mà người đại diện đại diện (004 T038; FR-028). Lấy từ cổng người thân
/// (`GET /family-portal/residents`, rồi `GET /family-portal/residents/{id}/contract`) vì endpoint `/contracts` là của
/// nhân viên và trả 403 với người thân. Chỉ xem. Phụ lục và đặt cọc của người thân chưa có endpoint trên cổng người
/// thân (xem danh sách việc còn lại, mục B), nên màn chưa hiện phần đó.
class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  List<Map<String, dynamic>>? _contracts;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final residents = (await widget.api.getList('/family-portal/residents')).cast<Map<String, dynamic>>();
      final all = <Map<String, dynamic>>[];
      for (final resident in residents) {
        final body = await widget.api.get('/family-portal/residents/${resident['residentId']}/contract') ?? {};
        all.addAll((body['contracts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>());
      }
      if (!mounted) return;
      setState(() {
        _contracts = all;
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e);
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
            Text(backendMessage(_error!), style: text.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Tải lại')),
          ],
        ),
      );
    }
    final contracts = _contracts;
    if (contracts == null) return const Center(child: CircularProgressIndicator());
    if (contracts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Chưa có hợp đồng nào.', style: text.bodyMedium),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: contracts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ContractCard(contract: contracts[i]),
    );
  }
}

class _ContractCard extends StatelessWidget {
  const _ContractCard({required this.contract});

  final Map<String, dynamic> contract;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, tone) = _contractStatus[contract['status']] ?? ('${contract['status']}', StatusTone.neutral);
    final end = contract['endDate'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text('Hợp đồng ${contract['contractNumber'] ?? ''}', style: theme.textTheme.titleSmall),
                ),
                StatusPill(label: statusLabel, tone: tone),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_residenceTypes[contract['residenceType']] ?? contract['residenceType']}, '
              'từ ${formatDate(contract['startDate'] as String)}${end == null ? '' : ' đến ${formatDate(end)}'}',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
