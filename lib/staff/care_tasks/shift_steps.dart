// Dải Tiến trình ca theo swimlane 2.2 SRS (như web Elder_Care_Frontend src/features/care-tasks/shiftSteps.js): nhận bàn
// giao ca trước → kế hoạch chăm sóc → công việc trong ca → sự cố → bàn giao cho ca sau. Bước nhận bàn giao, kế hoạch
// chỉ dẫn đường (chưa có API "bàn giao đến ca này"). Khác web: ca chưa có công việc không tính là đã xong.

enum ShiftStepState { done, current, pending, info }

class ShiftStep {
  const ShiftStep(this.key, this.label, this.state, this.summary);
  final String key;
  final String label;
  final ShiftStepState state;
  final String summary;
}

/// Bàn giao của ca: đang tải, chưa tải được, chưa lập (404) hoặc bản đã có.
class ShiftHandover {
  const ShiftHandover.loading() : loaded = false, failed = false, body = null;
  const ShiftHandover.failed() : loaded = true, failed = true, body = null;
  const ShiftHandover.none() : loaded = true, failed = false, body = null;
  const ShiftHandover.of(Map<String, dynamic> this.body) : loaded = true, failed = false;
  final bool loaded;
  final bool failed;
  final Map<String, dynamic>? body;
}

const _closed = {'COMPLETED', 'COMPLETED_LATE', 'NOT_PERFORMED', 'CANCELLED'};
const _openIncident = {'NEW', 'IN_PROGRESS', 'MONITORING'};
const _handoverStatus = {
  'DRAFT': 'Bản nháp',
  'PREPARED': 'Đã lập',
  'HAS_COMMENTS': 'Có ý kiến',
  'CONFIRMED': 'Đã xác nhận',
};

/// `incidents` null: chưa tải được (hoặc đang tải khi `incidentsLoading`). Sự cố chỉ đếm của người cao tuổi có việc
/// trong ca; ca chưa có việc thì đếm mọi sự cố đọc được.
List<ShiftStep> buildShiftSteps({
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>>? incidents,
  bool incidentsLoading = false,
  required ShiftHandover handover,
}) {
  final done = tasks.where((t) => _closed.contains(t['status'])).length;
  final overdue = tasks.where((t) => t['status'] == 'OVERDUE').length;
  final remaining = tasks.length - done;
  final work = tasks.isEmpty
      ? const ShiftStep('tasks', 'Công việc trong ca', ShiftStepState.pending, 'Chưa có công việc')
      : ShiftStep(
          'tasks',
          'Công việc trong ca',
          remaining == 0 ? ShiftStepState.done : ShiftStepState.current,
          '$done/${tasks.length} xong${overdue > 0 ? ', $overdue quá hạn' : ''}',
        );

  final residents = {for (final t in tasks) t['residentId']}..remove(null);
  ShiftStep incidentStep;
  if (incidents == null) {
    incidentStep = ShiftStep(
      'incidents',
      'Sự cố',
      incidentsLoading ? ShiftStepState.pending : ShiftStepState.info,
      incidentsLoading ? 'Đang tải' : 'Chưa tải được',
    );
  } else {
    final open = incidents.where((i) {
      if (!_openIncident.contains(i['status'])) return false;
      return residents.isEmpty || residents.contains((i['content'] as Map?)?['residentId']);
    }).length;
    incidentStep = open == 0
        ? const ShiftStep('incidents', 'Sự cố', ShiftStepState.done, 'Không có sự cố đang mở')
        : ShiftStep('incidents', 'Sự cố', ShiftStepState.current, '$open sự cố đang mở');
  }

  ShiftStep handoverStep;
  if (!handover.loaded) {
    handoverStep = const ShiftStep('handover', 'Bàn giao cho ca sau', ShiftStepState.pending, 'Đang tải');
  } else if (handover.failed) {
    handoverStep = const ShiftStep('handover', 'Bàn giao cho ca sau', ShiftStepState.info, 'Chưa tải được');
  } else if (handover.body?['status'] == 'CONFIRMED') {
    handoverStep = const ShiftStep('handover', 'Bàn giao cho ca sau', ShiftStepState.done, 'Đã xác nhận');
  } else {
    final status = handover.body?['status'] as String?;
    final label = status == null ? 'Chưa lập' : (_handoverStatus[status] ?? status);
    handoverStep = ShiftStep(
      'handover',
      'Bàn giao cho ca sau',
      work.state == ShiftStepState.done ? ShiftStepState.current : ShiftStepState.pending,
      remaining > 0
          ? '$label, còn $remaining việc chưa xong'
          // Q-417: bàn giao chỉ bắt buộc khi phạm vi ca còn việc chưa đóng hoặc cảnh báo đang mở.
          : status == null
          ? 'Chưa lập, chỉ bắt buộc khi ca còn việc hoặc cảnh báo mở'
          : label,
    );
  }

  return [
    const ShiftStep('previous', 'Nhận bàn giao ca trước', ShiftStepState.info, 'Xác nhận ở màn Bàn giao ca'),
    const ShiftStep('plan', 'Kế hoạch chăm sóc', ShiftStepState.info, 'Xem kế hoạch của người cao tuổi trong ca'),
    work,
    incidentStep,
    handoverStep,
  ];
}
