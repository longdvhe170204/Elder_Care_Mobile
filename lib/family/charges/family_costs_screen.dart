import 'package:flutter/material.dart';
import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';
import '../../common/widgets/page_body.dart';

/// FR-037/038: A nối màn vào cổng; mọi dữ liệu và quyền do backend cung cấp.
class FamilyCostsScreen extends StatefulWidget {
  const FamilyCostsScreen({super.key, required this.api, required this.residentId, this.initialRange});
  final ApiClient api;
  final int residentId;

  /// Khoảng ngày chọn sẵn (test); người dùng đổi hoặc bỏ trên màn.
  final DateTimeRange? initialRange;
  @override
  State<FamilyCostsScreen> createState() => _FamilyCostsScreenState();
}

class _FamilyCostsScreenState extends State<FamilyCostsScreen> {
  List<Map<String, dynamic>>? _statements;
  Map<String, dynamic>? _summary;
  late DateTimeRange? _range = widget.initialRange;
  String? _error;
  bool _denied = false;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FamilyCostsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.residentId != widget.residentId) {
      _generation++;
      _statements = null;
      _summary = null;
      _range = null;
      _error = null;
      _denied = false;
      _busy = false;
      _load();
    }
  }

  void _failed(Object error) {
    _error = backendMessage(error);
    if (error is ApiProblem && error.status == 403) {
      _denied = true;
      _statements = null;
      _summary = null;
    }
  }

  Future<void> _load() async {
    final generation = _generation;
    try {
      final rows = await widget.api.getList('/residents/${widget.residentId}/costs/statements');
      if (mounted && generation == _generation) {
        setState(() {
          _statements = rows.cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _failed(error));
    }
  }

  String _iso(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _chooseRange() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDateRange: _range,
      helpText: 'Khoảng ngày trong kỳ đang mở',
      saveText: 'Chọn',
    );
    if (mounted && selected != null) {
      setState(() {
        _range = selected;
        _summary = null;
      });
    }
  }

  Future<void> _provisional() async {
    if (_busy) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _error = null;
      _summary = null;
    });
    final query = _range == null ? '' : '?from=${_iso(_range!.start)}&to=${_iso(_range!.end)}';
    try {
      final data = await widget.api.get('/residents/${widget.residentId}/costs/provisional$query');
      if (mounted && generation == _generation) setState(() => _summary = data);
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _failed(error));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  // Khoảng ngày lọc cả khoản đã chốt theo ngày phát sinh (góp ý demo BF-10, 2026-11-27)
  List<Map<String, dynamic>> _itemsInRange(Map<String, dynamic> statement) {
    final items = (statement['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final range = _range;
    if (range == null) return items;
    final from = _iso(range.start);
    final to = _iso(range.end);
    return items.where((i) {
      final date = i['incurredOn'] as String;
      return date.compareTo(from) >= 0 && date.compareTo(to) <= 0;
    }).toList();
  }

  List<Map<String, dynamic>> get _visibleStatements => [
    for (final row in _statements ?? <Map<String, dynamic>>[])
      if (_range == null || _itemsInRange(row).isNotEmpty) row,
  ];

  String _title(Map<String, dynamic> row) {
    final period = row['period'] as String;
    final label = 'Kỳ ${period.substring(5)}/${period.substring(0, 4)}';
    if (_range == null) return '$label · ${_money(row['total'])}';
    final sum = _itemsInRange(row).fold<num>(0, (total, i) => total + (i['amount'] as num? ?? 0));
    return '$label · trong khoảng ${_money(sum)}';
  }

  static const _types = {
    'RESIDENCY_FEE': 'Phí lưu trú',
    'DAY_CARE_SESSION_FEE': 'Phí buổi bán trú',
    'SERVICE': 'Dịch vụ',
    'CONSUMABLE': 'Vật phẩm tiêu hao',
    'ACTIVITY': 'Hoạt động',
    'MEDICATION': 'Thuốc',
    'FAMILY_OVERNIGHT_STAY': 'Người thân ở lại',
    'FAMILY_MEAL': 'Suất ăn người thân',
    'PURCHASE_ASSISTANCE': 'Mua hộ',
    'OTHER': 'Khoản khác',
  };
  // Demo 2026-11-25: tiền VND ngăn nghìn bằng dấu chấm, dạng 1.550.000 đ (NFR-11)
  static String _money(Object? value) {
    if (value is! num) return 'Chưa có số tiền';
    final digits = value.abs().round().toString();
    final grouped = digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
    return '${value < 0 ? '-' : ''}$grouped đ';
  }

  List<Widget> _totals(Object? raw) => (raw as List<dynamic>? ?? []).map((value) {
    final row = value as Map<String, dynamic>;
    return ListTile(title: Text(_types[row['type']] ?? 'Chi phí'), trailing: Text(_money(row['total'])));
  }).toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chi phí')),
    body: PageBody(
      child: _denied
          ? const Text('Bạn không có quyền xem chi phí của người cao tuổi này.')
          : ListView(
              children: [
                if (_error != null) ...[
                  Text(_error!, semanticsLabel: _error),
                  TextButton(onPressed: _load, child: const Text('Tải lại')),
                ],
                Text('Tạm tính, chưa chốt', style: Theme.of(context).textTheme.titleMedium),
                const Text('Khoảng ngày lọc cả tạm tính và bảng đã chốt. Để trống thì xem tạm tính từ đầu tháng.'),
                TextButton(
                  onPressed: _busy ? null : _chooseRange,
                  child: Text(
                    _range == null
                        ? 'Chọn khoảng ngày'
                        : '${formatDate(_iso(_range!.start))} – ${formatDate(_iso(_range!.end))}',
                  ),
                ),
                FilledButton(onPressed: _busy ? null : _provisional, child: Text(_busy ? 'Đang tải…' : 'Xem tạm tính')),
                if (_summary != null) ...[
                  ..._totals(_summary!['totalsByType']),
                  if (_summary!['hasUnpricedItems'] == true) const Text('Còn khoản chưa có đơn giá'),
                ],
                const Divider(),
                Text('Bảng đã chốt', style: Theme.of(context).textTheme.titleMedium),
                if (_range != null) ...[
                  Text(
                    'Đang xem các khoản phát sinh từ ${formatDate(_iso(_range!.start))} đến '
                    '${formatDate(_iso(_range!.end))}.',
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _range = null;
                      _summary = null;
                    }),
                    child: const Text('Bỏ chọn khoảng ngày'),
                  ),
                  if (_statements?.isNotEmpty == true && _visibleStatements.isEmpty)
                    const Text('Không có khoản đã chốt trong khoảng ngày này.'),
                ],
                if (_statements == null && _error == null) const Center(child: CircularProgressIndicator()),
                if (_statements?.isEmpty == true) const Text('Chưa có bảng chi phí đã chốt.'),
                for (final row in _visibleStatements)
                  ExpansionTile(
                    title: Text(_title(row)),
                    subtitle: Text(
                      row['statementType'] == 'SUPPLEMENTARY'
                          ? 'Bổ sung'
                          : row['finalPeriod'] == true
                          ? 'Kỳ cuối'
                          : 'Bảng thường',
                    ),
                    children: [
                      // 017 US4: bảng chốt được trừ vào số dư; người thân xem còn nợ, cách nộp tiền ở mục Số dư
                      if (_range == null && row['finalPeriod'] == true)
                        const ListTile(
                          title: Text(
                            'Tổng bảng kỳ cuối đã được trừ vào số dư. Xem số dư, còn nợ và cách nộp tiền ở mục Số dư.',
                          ),
                        ),
                      if (_range == null) ..._totals(row['totalsByType']),
                      for (final item in _itemsInRange(row)) _item(item),
                    ],
                  ),
              ],
            ),
    ),
  );
  Widget _item(Map<String, dynamic> item) => ListTile(
    title: Text(item['medicationName'] as String? ?? item['description'] as String? ?? 'Khoản chi phí'),
    subtitle: Text(
      '${formatDate(item['incurredOn'] as String)} · ${item['quantity']} ${item['unit']} · Đơn giá ${_money(item['unitPrice'])}'
      '${item['originalPeriod'] == null ? '' : '\nĐiều chỉnh kỳ ${item['originalPeriod']}'}',
    ),
    trailing: Text(_money(item['amount'])),
  );
}
