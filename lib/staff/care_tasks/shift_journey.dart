import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'shift_steps.dart';

/// Nguồn dữ liệu và lối đi của dải Tiến trình ca (luồng 2.2 SRS). Màn chứa checklist (có ApiClient) cấp; màn Checklist ca
/// chỉ gọi, nên test dùng bản giả được.
class ShiftJourneyLinks {
  const ShiftJourneyLinks({
    required this.incidents,
    required this.handover,
    required this.openHandover,
    required this.openPlans,
    required this.reportIncident,
  });

  /// Sự cố đọc được của nhân viên (mọi trạng thái mở).
  final Future<List<Map<String, dynamic>>> Function() incidents;

  /// Bàn giao của ca; null khi ca chưa lập bàn giao.
  final Future<Map<String, dynamic>?> Function(int shiftId) handover;
  final Future<void> Function(BuildContext context, int shiftId) openHandover;

  /// `residents`: {id, name} của người cao tuổi có việc trong ca.
  final Future<void> Function(BuildContext context, List<Map<String, dynamic>> residents) openPlans;

  /// Mở form báo sự cố, chọn sẵn người cao tuổi nếu có; true khi đã ghi.
  final Future<bool> Function(BuildContext context, int? residentId) reportIncident;
}

class ShiftJourney extends StatelessWidget {
  const ShiftJourney({super.key, required this.steps, required this.onAction});
  final List<ShiftStep> steps;
  final void Function(String key) onAction;

  static const _actions = {
    'previous': 'Mở bàn giao ca trước',
    'plan': 'Xem kế hoạch',
    'incidents': 'Báo sự cố',
    'handover': 'Mở bàn giao',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Tiến trình ca', style: text.titleMedium)),
            for (final (index, step) in steps.indexed)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: step.state == ShiftStepState.current ? scheme.primaryContainer.withValues(alpha: 0.4) : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_icon(step.state), color: _tone(step.state, scheme), size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${index + 1}. ${step.label}',
                            semanticsLabel: '${index + 1}. ${step.label}, ${_stateText(step.state)}',
                            style: text.titleSmall,
                          ),
                          Text(step.summary, style: text.bodySmall),
                          if (_actions[step.key] case final label?)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: step.state == ShiftStepState.current
                                  ? FilledButton(onPressed: () => onAction(step.key), child: Text(label))
                                  : OutlinedButton(onPressed: () => onAction(step.key), child: Text(label)),
                            ),
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

IconData _icon(ShiftStepState state) => switch (state) {
  ShiftStepState.done => LucideIcons.circleCheck,
  ShiftStepState.current => LucideIcons.circleDot,
  ShiftStepState.pending => LucideIcons.circle,
  ShiftStepState.info => LucideIcons.info,
};

Color _tone(ShiftStepState state, ColorScheme scheme) => switch (state) {
  ShiftStepState.done => Colors.green.shade700,
  ShiftStepState.current => scheme.primary,
  _ => scheme.onSurfaceVariant,
};

String _stateText(ShiftStepState state) => switch (state) {
  ShiftStepState.done => 'đã xong',
  ShiftStepState.current => 'đang làm',
  ShiftStepState.pending => 'chưa tới',
  ShiftStepState.info => 'tham khảo',
};
