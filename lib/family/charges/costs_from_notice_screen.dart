import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/widgets/page_body.dart';
import 'family_costs_screen.dart';

/// Mở màn Chi phí từ thông báo bảng chi phí đã chốt (nguồn `M11.COST_STATEMENT`, mã là mã bảng; demo 2026-11-25).
/// Thông báo không mang mã người cao tuổi nên tìm bảng đó trong các người cao tuổi người thân theo dõi
/// (`GET /family-portal/residents`, rồi bảng đã chốt của từng người); chỉ theo dõi một người thì mở luôn người đó.
class CostsFromNoticeScreen extends StatefulWidget {
  const CostsFromNoticeScreen({super.key, required this.api, required this.statementId});

  final ApiClient api;
  final int statementId;

  @override
  State<CostsFromNoticeScreen> createState() => _CostsFromNoticeScreenState();
}

class _CostsFromNoticeScreenState extends State<CostsFromNoticeScreen> {
  int? _residentId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    try {
      final residents = (await widget.api.getList('/family-portal/residents')).cast<Map<String, dynamic>>();
      final ids = [for (final r in residents) r['residentId'] as int];
      int? found = ids.length == 1 ? ids.single : null;
      for (final id in ids) {
        if (found != null) break;
        try {
          final rows = await widget.api.getList('/residents/$id/costs/statements');
          if (rows.any((s) => (s as Map<String, dynamic>)['id'] == widget.statementId)) found = id;
        } on Exception {
          // Không xem được chi phí của người này: bỏ qua, xét người tiếp theo
        }
      }
      if (!mounted) return;
      setState(() => found == null ? _error = 'Không tìm thấy bảng chi phí của thông báo này.' : _residentId = found);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_residentId != null) return FamilyCostsScreen(api: widget.api, residentId: _residentId!);
    return Scaffold(
      appBar: AppBar(title: const Text('Chi phí')),
      body: PageBody(child: _error == null ? const Center(child: CircularProgressIndicator()) : Text(_error!)),
    );
  }
}
