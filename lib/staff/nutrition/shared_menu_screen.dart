import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';

/// Thực đơn chung đã công bố trên app nhân viên (011 FR-028, Q-445): mặc định hôm nay, chuyển sang cả tuần; mỗi bữa có
/// các món kèm mô tả, ảnh. Thực đơn chung cả viện, không theo chế độ ăn; khi phục vụ, nhân viên đối chiếu dị ứng, chế độ
/// ăn trong hồ sơ người cao tuổi (BR-M08-14).
class SharedMenuScreen extends StatefulWidget {
  const SharedMenuScreen({super.key, required this.api, this.today});

  final ApiClient api;

  /// Ngày hôm nay theo giờ Việt Nam; test đặt sẵn.
  final DateTime? today;

  @override
  State<SharedMenuScreen> createState() => _SharedMenuScreenState();
}

const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

class _SharedMenuScreenState extends State<SharedMenuScreen> {
  bool _week = false;
  List<Map<String, dynamic>>? _days;
  String? _error;

  DateTime get _today {
    final d = widget.today ?? DateTime.now().toUtc().add(const Duration(hours: 7));
    return DateTime.utc(d.year, d.month, d.day);
  }

  static String _iso(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final from = _week ? _today.subtract(Duration(days: _today.weekday - 1)) : _today;
    final to = _week ? from.add(const Duration(days: 6)) : _today;
    setState(() {
      _days = null;
      _error = null;
    });
    try {
      final rows = await widget.api.getList('/menus/shared?from=${_iso(from)}&to=${_iso(to)}');
      if (mounted) setState(() => _days = rows.cast<Map<String, dynamic>>());
    } on Exception catch (e) {
      if (mounted) setState(() => _error = backendMessage(e));
    }
  }

  String _dayLabel(String iso) {
    final d = DateTime.parse(iso);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${_weekdays[d.weekday - 1]}, ${two(d.day)}/${two(d.month)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = _days;
    return Scaffold(
      appBar: AppBar(title: const Text('Thực đơn')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Hôm nay')),
                ButtonSegment(value: true, label: Text('Cả tuần')),
              ],
              selected: {_week},
              onSelectionChanged: (s) {
                setState(() => _week = s.first);
                _load();
              },
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
            if (days == null && _error == null) const Center(child: CircularProgressIndicator()),
            if (days != null && days.isEmpty)
              Text('Chưa có thực đơn công bố cho ${_week ? 'tuần này' : 'hôm nay'}.', style: text.bodyMedium),
            for (final day in days ?? const <Map<String, dynamic>>[]) ...[
              if (_week)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(_dayLabel(day['date'] as String), style: text.titleMedium),
                ),
              for (final meal in ((day['meals'] as List?) ?? const []).cast<Map<String, dynamic>>()) _meal(meal, text),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meal(Map<String, dynamic> meal, TextTheme text) {
    final dishes = ((meal['dishes'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final time = meal['expectedTime'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(time == null ? '${meal['name']}' : '${meal['name']} · $time', style: text.titleMedium),
            const SizedBox(height: 8),
            for (final dish in dishes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dish['imageUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _DishImage(api: widget.api, url: dish['imageUrl'] as String),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${dish['name']}', style: text.bodyLarge),
                          if ((dish['description'] as String?)?.isNotEmpty ?? false)
                            Text('${dish['description']}', style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ảnh món tải qua phiên đăng nhập (`GET /files/{id}`, quyền tải ảnh món mở cho mọi người dùng; Q-445).
class _DishImage extends StatefulWidget {
  const _DishImage({required this.api, required this.url});

  final ApiClient api;
  final String url;

  @override
  State<_DishImage> createState() => _DishImageState();
}

class _DishImageState extends State<_DishImage> {
  late final Future<Uint8List> _bytes = widget.api.getBytes(widget.url.replaceFirst('/api/v1', ''));

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    height: 56,
    child: FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) => snap.hasData
          ? Image.memory(snap.data!, fit: BoxFit.cover, semanticLabel: 'Ảnh món')
          : ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
    ),
  );
}
