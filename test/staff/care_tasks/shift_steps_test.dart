import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/staff/care_tasks/shift_steps.dart';

// Luồng 2.2 SRS: dải Tiến trình ca dựng từ công việc, sự cố và bàn giao của ca.

Map<String, dynamic> task(String status, {int residentId = 77}) => {'status': status, 'residentId': residentId};

ShiftStep step(List<ShiftStep> steps, String key) => steps.firstWhere((s) => s.key == key);

void main() {
  test('dựng 5 bước đúng thứ tự', () {
    final steps = buildShiftSteps(tasks: const [], incidents: const [], handover: const ShiftHandover.none());
    expect(steps.map((s) => s.key), ['previous', 'plan', 'tasks', 'incidents', 'handover']);
  });

  test('chưa có công việc: không hiện là đã xong', () {
    final steps = buildShiftSteps(tasks: const [], incidents: const [], handover: const ShiftHandover.none());
    expect(step(steps, 'tasks').state, ShiftStepState.pending);
    expect(step(steps, 'tasks').summary, 'Chưa có công việc');
  });

  test('còn việc: đếm xong trên tổng và số quá hạn', () {
    final steps = buildShiftSteps(
      tasks: [task('COMPLETED'), task('OVERDUE'), task('DUE')],
      incidents: const [],
      handover: const ShiftHandover.none(),
    );
    expect(step(steps, 'tasks').state, ShiftStepState.current);
    expect(step(steps, 'tasks').summary, '1/3 xong, 1 quá hạn');
    expect(step(steps, 'handover').summary, 'Chưa lập, còn 2 việc chưa xong');
  });

  test('Q-417: hết việc mà chưa lập bàn giao thì ghi rõ chỉ bắt buộc khi còn việc, cảnh báo', () {
    final steps = buildShiftSteps(
      tasks: [task('COMPLETED')],
      incidents: const [],
      handover: const ShiftHandover.none(),
    );
    expect(step(steps, 'handover').summary, 'Chưa lập, chỉ bắt buộc khi ca còn việc hoặc cảnh báo mở');
  });

  test('sự cố đang mở của người cao tuổi trong ca', () {
    final steps = buildShiftSteps(
      tasks: [task('DUE')],
      incidents: [
        {
          'status': 'NEW',
          'content': {'residentId': 77},
        },
        {
          'status': 'CLOSED',
          'content': {'residentId': 77},
        },
        {
          'status': 'IN_PROGRESS',
          'content': {'residentId': 5},
        },
      ],
      handover: const ShiftHandover.none(),
    );
    expect(step(steps, 'incidents').state, ShiftStepState.current);
    expect(step(steps, 'incidents').summary, '1 sự cố đang mở');
  });

  test('sự cố, bàn giao chưa tải được thì ghi rõ, đang tải thì ghi Đang tải', () {
    final failed = buildShiftSteps(tasks: const [], incidents: null, handover: const ShiftHandover.failed());
    expect(step(failed, 'incidents').summary, 'Chưa tải được');
    expect(step(failed, 'handover').summary, 'Chưa tải được');
    final loading = buildShiftSteps(
      tasks: const [],
      incidents: null,
      incidentsLoading: true,
      handover: const ShiftHandover.loading(),
    );
    expect(step(loading, 'incidents').summary, 'Đang tải');
    expect(step(loading, 'handover').summary, 'Đang tải');
  });

  test('xong hết việc: bàn giao là bước đang làm; đã xác nhận thì xong', () {
    final pending = buildShiftSteps(
      tasks: [task('COMPLETED')],
      incidents: const [],
      handover: const ShiftHandover.of({'status': 'PREPARED'}),
    );
    expect(step(pending, 'handover').state, ShiftStepState.current);
    expect(step(pending, 'handover').summary, 'Đã lập');
    final confirmed = buildShiftSteps(
      tasks: [task('COMPLETED')],
      incidents: const [],
      handover: const ShiftHandover.of({'status': 'CONFIRMED'}),
    );
    expect(step(confirmed, 'handover').state, ShiftStepState.done);
  });
}
