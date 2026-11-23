import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/api/problem_message.dart';
import '../../common/format/date_time.dart';
import '../../common/notifications/notification_api.dart';
import '../../common/theme/app_theme.dart';
import '../../common/widgets/header_app_bar.dart';
import '../care_tasks/weekly_checklist.dart' show shiftName;
import 'handover_cache.dart';

/// Màn Bàn giao ca (Figma "Prototype · Mobile" 117:1311 "Bàn giao ca · Ca vừa kết thúc"): thẻ ca và trạng thái, "Việc
/// còn lại của ca" (mục công việc đã có và việc chưa đóng của ca, mỗi việc cần lý do chưa hoàn thành), ghi chú cho ca
/// sau, thanh thao tác cuối màn. Mọi lệnh và quyền lấy từ backend (`allowedCommands`); sửa Bản nháp gửi If-Match theo
/// ETag của `GET /handovers/{id}` (FR-040). Bản lưu ngoại tuyến (FR-060) chỉ khi `/me/shifts` cho hạn phạm vi
/// `scopeEndsAt`; mất mạng thì xem bản lưu, không có lệnh.
class HandoverScreen extends StatefulWidget {
  const HandoverScreen({super.key, required this.api, this.initialShiftId, this.cache, this.onDone});

  final ApiClient api;
  final int? initialShiftId;
  final HandoverCache? cache;

  /// "Về Ca của tôi" sau khi gửi bàn giao; mặc định quay lại màn trước.
  final VoidCallback? onDone;

  @override
  State<HandoverScreen> createState() => _HandoverScreenState();
}

/// Lý do chưa hoàn thành và việc ca sau cần làm ghi chung trong `note` của mục bàn giao (API có một ô ghi chú).
const _nextMarker = '\nViệc ca sau cần làm: ';

(String, String) splitNote(String? note) {
  if (note == null) return ('', '');
  final at = note.indexOf(_nextMarker);
  return at < 0 ? (note, '') : (note.substring(0, at), note.substring(at + _nextMarker.length));
}

String joinNote(String reason, String next) => next.isEmpty ? reason : '$reason$_nextMarker$next';

class _HandoverScreenState extends State<HandoverScreen> {
  static const _states = {
    'DRAFT': 'Chờ bàn giao',
    'PREPARED': 'Chờ ca sau xác nhận',
    'HAS_COMMENTS': 'Có ý kiến',
    'CONFIRMED': 'Đã xác nhận',
  };
  static const _groups = {
    'DOSE': 'Liều thuốc',
    'VITAL_SIGN': 'Chỉ số vượt ngưỡng',
    'ALERT': 'Cảnh báo',
    'INCIDENT': 'Sự cố',
    'RESIDENT_CHANGE': 'Biến động người cao tuổi',
    'BED_AWAITING_READINESS': 'Giường chờ sẵn sàng',
    'STORED_BELONGING': 'Đồ gửi đang giữ',
    'FOLLOW_UP_ISSUE': 'Vấn đề cần theo dõi',
  };

  late DateTime month;
  List<Map<String, dynamic>> shifts = [], sources = [];
  Map<String, dynamic>? shift, record;
  Map<int, String> names = {};

  /// Chi tiết công việc của mục TASK (`GET /care-tasks/{id}`): tên việc, người cao tuổi · phòng, trạng thái.
  Map<String, Map<String, dynamic>> tasks = {};
  final comment = TextEditingController();
  final Map<int, String> replies = {};
  final Map<String, String> keys = {};
  int? selected;
  int generation = 0;
  bool loading = false, busy = false, sent = false;
  String? error, sourceError, etag;
  CachedHandover? offline;
  final assessment = TextEditingController();

  @override
  void initState() {
    super.initState();
    final vn = DateTime.now().toUtc().add(const Duration(hours: 7));
    month = DateTime.utc(vn.year, vn.month);
    selected = widget.initialShiftId;
    load();
  }

  @override
  void dispose() {
    generation++;
    comment.dispose();
    assessment.dispose();
    replies.clear();
    record = null;
    sources = [];
    names = {};
    tasks = {};
    super.dispose();
  }

  List<Map<String, dynamic>> maps(Object? data) => (data as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  String day(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-01';
  bool allowed(String command) =>
      offline == null && (record?['allowedCommands'] as List<dynamic>? ?? []).contains(command);

  DateTime? scopeEndsAt(int? shiftId) {
    final row = shifts.where((s) => s['id'] == shiftId).firstOrNull;
    return row?['scopeEndsAt'] is String ? DateTime.parse(row!['scopeEndsAt'] as String) : null;
  }

  /// Ca mặc định khi mở từ menu: ca gần nhất đã bắt đầu (ca vừa kết thúc hoặc đang làm).
  int? latestStarted() {
    final now = DateTime.now().toUtc();
    final started =
        shifts.where((s) => s['startsAt'] is String && !DateTime.parse(s['startsAt'] as String).isAfter(now)).toList()
          ..sort((a, b) => (b['startsAt'] as String).compareTo(a['startsAt'] as String));
    return started.firstOrNull?['id'] as int?;
  }

  Future<void> load({int move = 0, int? shiftId}) async {
    final request = ++generation;
    setState(() {
      month = DateTime.utc(month.year, month.month + move);
      if (move != 0) selected = null;
      selected = shiftId ?? selected;
      loading = true;
      error = null;
      sourceError = null;
      shift = null;
      record = null;
      sources = [];
      names = {};
      tasks = {};
      offline = null;
      etag = null;
    });
    try {
      await widget.cache?.purgeExpired();
      final grants = maps(await widget.api.getList('/me/permissions'));
      if (!grants.any((p) => p['function'] == 'SHIFT_HANDOVER' && p['operation'] == 'VIEW')) {
        throw ApiProblem(403, 'PERMISSION_DENIED', 'Bạn không có quyền xem bàn giao ca.');
      }
      if (widget.initialShiftId == null) {
        final manage = grants.any(
          (p) => p['function'] == 'SHIFT_SCHEDULE' && ['CREATE', 'UPDATE', 'APPROVE'].contains(p['operation']),
        );
        final rows = maps(
          await widget.api.getList(
            manage
                ? '/shift-schedules?month=${day(month).substring(0, 7)}'
                : '/me/shifts?from=${day(month)}&to=${day(DateTime.utc(month.year, month.month + 1))}',
          ),
        );
        if (!mounted || request != generation) return;
        shifts = manage ? [for (final schedule in rows) ...maps(schedule['shifts'])] : rows;
        if (!shifts.any((row) => row['id'] == selected)) selected = move == 0 ? latestStarted() : null;
      }
      if (selected == null) return;
      final current = await widget.api.get('/shifts/$selected');
      Map<String, dynamic>? value;
      try {
        value = await widget.api.get('/shifts/$selected/handovers');
      } on ApiProblem catch (p) {
        if (p.status != 404) rethrow;
      }
      if (value != null) {
        // ETag cho If-Match của lệnh sửa (FR-040); thân mới nhất của cùng bàn giao
        final full = await widget.api.requestResponse('GET', '/handovers/${value['id']}');
        if (full.body is Map<String, dynamic>) value = full.body as Map<String, dynamic>;
        etag = full.headers['etag'];
      }
      if (!mounted || request != generation) return;
      shift = current;
      record = value;
      assessment.text = (value?['generalAssessment'] as String?) ?? '';
      final endsAt = scopeEndsAt(selected);
      if (value == null) {
        await widget.cache?.remove(selected!);
        return;
      }
      if (endsAt != null) await widget.cache?.save(selected!, value, endsAt);
      List<Map<String, dynamic>> readSources = [];
      String? failedSource;
      try {
        readSources = maps(
          await widget.api.getList(
            '/handovers/${value['id']}/source-records?afterPreparation=${value['status'] != 'DRAFT'}',
          ),
        );
      } on ApiProblem catch (p) {
        if (p.status == 401 || p.status == 403 || p.status == 404) rethrow;
        failedSource = backendMessage(p);
      } on Object catch (e) {
        failedSource = backendMessage(e);
      }
      if (!mounted || request != generation) return;
      sources = readSources;
      sourceError = failedSource;
      final taskIds = {
        for (final row in [...maps(value['items']), ...readSources])
          if (row['group'] == 'TASK' && row['sourceId'] != null) '${row['sourceId']}',
      };
      for (final id in taskIds) {
        try {
          final task = await widget.api.get('/care-tasks/$id');
          if (mounted && request == generation && task != null) tasks[id] = task;
        } on Object {
          // Không xem được chi tiết công việc thì dùng nội dung của mục bàn giao.
        }
      }
      final people = {
        for (final row in [...maps(value['residentAssessments']), ...maps(value['items']), ...readSources])
          if (row['residentId'] is int) row['residentId'] as int,
      };
      for (final id in people) {
        try {
          final person = await widget.api.get('/residents/$id');
          if (mounted && request == generation && person?['fullName'] is String) {
            names[id] = person!['fullName'] as String;
          }
        } on Object {
          // Backend giới hạn tên theo quyền; không lấy tên từ nguồn khác.
        }
      }
    } on ApiUnreachable {
      final cached = selected == null ? null : await widget.cache?.read(selected!);
      if (mounted && request == generation) {
        offline = cached;
        record = cached?.record;
        error = cached == null ? 'Không kết nối được máy chủ và máy không có bản lưu của ca này.' : null;
      }
    } on Object catch (e) {
      if (e is ApiProblem && [401, 403, 404].contains(e.status) && selected != null) {
        await widget.cache?.remove(selected!);
      }
      if (mounted && request == generation) {
        error = backendMessage(e);
        shift = null;
        record = null;
        sources = [];
        names = {};
        tasks = {};
        if (e is ApiProblem && [401, 403, 404].contains(e.status)) {
          comment.clear();
          replies.clear();
          keys.clear();
          shifts = [];
        }
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<bool> confirmDialog(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Quay lại')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Tiếp tục')),
          ],
        ),
      ) ==
      true;

  Future<void> act(String command, {Map<String, dynamic> body = const {}}) async {
    final canCreate = (shift?['allowedCommands'] as List<dynamic>? ?? []).contains('createHandover');
    if (busy || loading || (command == 'create' ? !canCreate : !allowed(command))) return;
    final path = command == 'create'
        ? '/shifts/$selected/handovers'
        : '/handovers/${record!['id']}/${{'comment': 'comments', 'supplementAndResubmit': 'supplement-and-resubmit'}[command] ?? command}';
    if (command == 'complete' &&
        !await confirmDialog(
          'Xác nhận bàn giao',
          'Gửi bàn giao cho ca sau? Sau khi gửi, ca sau sẽ xem và xác nhận nội dung này.',
        )) {
      return;
    }
    if (command == 'confirm' &&
        !await confirmDialog('Nhận bàn giao', 'Bạn đã đọc đủ nội dung bàn giao của ca trước?')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final key = keys.putIfAbsent(jsonEncode([path, body]), newIdempotencyKey);
      await widget.api.post(path, body, headers: {'Idempotency-Key': key});
      if (!mounted) return;
      comment.clear();
      replies.clear();
      keys.clear();
      if (command == 'complete') sent = true;
      await load();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        error = backendMessage(e);
        if (e is ApiProblem && [401, 403, 404].contains(e.status)) {
          record = null;
          shift = null;
          sources = [];
          names = {};
          tasks = {};
          comment.clear();
          replies.clear();
          keys.clear();
        }
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Lệnh sửa Bản nháp hoặc thêm phát sinh sau khi lập (FR-040, FR-041): gửi If-Match theo ETag; 412 thì tải lại.
  Future<bool> edit(String method, String path, String? done, {Object? body}) async {
    if (busy || loading || etag == null) return false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final key = keys.putIfAbsent(jsonEncode([method, path, body]), newIdempotencyKey);
      await widget.api.requestJson(
        method,
        path,
        body: body,
        headers: {'If-Match': etag!, if (method != 'DELETE') 'Idempotency-Key': key},
      );
      keys.clear();
      await load();
      if (mounted && done != null) setState(() => error = done);
      return true;
    } on ApiProblem catch (e) {
      if (!mounted) return false;
      if (e.status == 412) {
        await load();
        if (mounted) setState(() => error = 'Bàn giao vừa được người khác sửa; đã tải lại, hãy làm lại thao tác.');
      } else {
        setState(() => error = backendMessage(e));
      }
    } on Object catch (e) {
      if (mounted) setState(() => error = backendMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
    return false;
  }

  /// Việc còn lại của ca: mục TASK đã có rồi việc chưa đóng chưa thành mục (chỉ người lập thêm được).
  List<_Leftover> leftovers() => _missingFirst([
    for (final item in maps(record?['items']))
      if (item['group'] == 'TASK') _Leftover(item: item),
    if (allowed('addItem'))
      for (final source in sources)
        if (source['group'] == 'TASK' && source['hasItem'] != true && source['dataUnavailable'] != true)
          _Leftover(source: source),
  ]);

  /// Việc thiếu lý do lên đầu (Figma "Thiếu lý do"), giữ thứ tự còn lại.
  static List<_Leftover> _missingFirst(List<_Leftover> rows) {
    bool missing(_Leftover r) => splitNote(r.item?['note'] as String?).$1.trim().isEmpty;
    return [...rows.where(missing), ...rows.where((r) => !missing(r))];
  }

  bool canWriteReason(_Leftover row) => row.item == null ? allowed('addItem') : allowed('updateItem');

  Future<void> openReason(_Leftover row) async {
    final (reason, next) = splitNote(row.item?['note'] as String?);
    final result = await Navigator.of(context).push<(String, String)>(
      MaterialPageRoute(
        builder: (_) =>
            _ReasonScreen(title: title(row), subtitle: who(row), tag: statusTag(row), reason: reason, next: next),
      ),
    );
    if (result == null || !mounted) return;
    final base = row.item ?? row.source!;
    final body = {
      'group': 'TASK',
      'sourceType': base['sourceType'],
      'sourceId': base['sourceId'],
      if (base['residentId'] != null) 'residentId': base['residentId'],
      if (base['roomId'] != null) 'roomId': base['roomId'],
      'description': base['description'] ?? title(row),
      'note': joinNote(result.$1, result.$2),
    };
    final id = record!['id'];
    await (row.item == null
        ? edit('POST', '/handovers/$id/items', null, body: body)
        : edit(
            'PUT',
            '/handovers/$id/items/${row.item!['id']}',
            null,
            body: {...body, 'resolved': row.item!['resolved']},
          ));
  }

  Map<String, dynamic>? taskOf(_Leftover row) => tasks['${(row.item ?? row.source)!['sourceId']}'];

  String title(_Leftover row) =>
      taskOf(row)?['taskType'] as String? ??
      (row.item ?? row.source)!['description'] as String? ??
      'Nội dung giới hạn theo quyền xem.';

  String who(_Leftover row) {
    final card = taskOf(row)?['residentCard'] as Map?;
    final resident = (row.item ?? row.source)!['residentId'];
    return [
      card?['fullName'] as String? ?? names[resident] ?? 'Người cao tuổi: chưa có tên được phép xem',
      if (card?['roomBed'] case final String room) room,
    ].join(' · ');
  }

  (String, bool)? statusTag(_Leftover row) {
    final status = taskOf(row)?['status'] as String? ?? (row.item ?? row.source)!['currentStatus'] as String?;
    return switch (status) {
      'OVERDUE' => ('Quá hạn', true),
      'DUE' => ('Đến hạn', false),
      'NOT_YET_DUE' => ('Chưa đến hạn', false),
      'COMPLETED' || 'COMPLETED_LATE' => ('Đã hoàn thành', false),
      'NOT_PERFORMED' => ('Không thực hiện', false),
      'CANCELLED' => ('Đã hủy', false),
      _ => null,
    };
  }

  /// Ghi chú cho ca sau là nhận định chung (Q-83 bắt buộc khi hoàn tất); lưu trước khi gửi nếu đã sửa.
  Future<void> complete() async {
    final general = assessment.text.trim();
    if (allowed('assess') && general != ((record!['generalAssessment'] as String?) ?? '').trim()) {
      final saved = await edit(
        'PUT',
        '/handovers/${record!['id']}/assessments',
        null,
        body: {
          'general': general,
          'byResident': [
            for (final a in maps(record!['residentAssessments']))
              {'residentId': a['residentId'], 'content': a['content']},
          ],
        },
      );
      if (!saved || !mounted) return;
    }
    await act('complete');
  }

  @override
  Widget build(BuildContext context) {
    if (sent && record?['status'] == 'PREPARED' && error == null && !loading) return _sentView(context);
    final rows = leftovers();
    final missing = rows.where((r) => splitNote(r.item?['note'] as String?).$1.trim().isEmpty).length;
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                if (widget.initialShiftId == null) _shiftPicker(context),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (error != null) ...[
                  Semantics(liveRegion: true, child: Text(error!)),
                  if (widget.initialShiftId != null) _reloadRow(context),
                  const SizedBox(height: 12),
                ],
                if (offline != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        'Bản lưu trên máy lúc ${formatDateTime(offline!.savedAt)}, chỉ xem khi mất mạng; '
                        'tự xóa lúc ${formatDateTime(offline!.scopeEndsAt)} khi hết phạm vi ca.',
                      ),
                    ),
                  ),
                if (!loading && shift != null) ...[
                  _ShiftCard(shift: shift!, status: statusLabel()),
                  const SizedBox(height: 13),
                ],
                if (!loading && error == null && record == null)
                  _Panel(
                    title: selected == null ? 'Chọn ca để xem bàn giao.' : 'Chưa có bàn giao được phép xem ở ca này.',
                  ),
                if (!loading && record != null) ..._content(context, rows),
              ],
            ),
          ),
        ),
        _bottomBar(context, rows, missing),
      ],
    );
  }

  String statusLabel() => record == null ? 'Chờ bàn giao' : _states[record!['status']] ?? 'Chưa đọc được trạng thái';

  Widget _reloadRow(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: busy || loading ? null : load,
      icon: const Icon(LucideIcons.refreshCw, size: 16),
      label: const Text('Tải lại'),
    ),
  );

  Widget _shiftPicker(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<int>(
          key: ValueKey('shift:$selected:${day(month)}'),
          initialValue: shifts.any((row) => row['id'] == selected) ? selected : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: 'Ca tháng ${month.month}/${month.year}', isDense: true),
          items: [
            for (final row in shifts)
              DropdownMenuItem(
                value: row['id'] as int,
                child: Text(
                  '${shiftName(row)} · ${formatDateTime(DateTime.parse(row['startsAt'] as String))}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: busy || loading ? null : (id) => id == null ? null : load(shiftId: id),
        ),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(onPressed: busy || loading ? null : () => load(move: -1), child: const Text('Tháng trước')),
            TextButton(onPressed: busy || loading ? null : () => load(move: 1), child: const Text('Tháng sau')),
            TextButton(onPressed: busy || loading ? null : load, child: const Text('Tải lại')),
          ],
        ),
      ],
    ),
  );

  List<Widget> _content(BuildContext context, List<_Leftover> rows) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final comments = maps(record!['comments']);
    final others = [
      for (final item in maps(record!['items']))
        if (item['group'] != 'TASK') item,
    ];
    final otherSources = [
      if (allowed('addItem'))
        for (final source in sources)
          if (source['group'] != 'TASK' && source['hasItem'] != true) source,
    ];
    return [
      Row(
        children: [
          Expanded(child: Text('Việc còn lại của ca', style: text.titleLarge)),
          Text('${rows.length} việc', style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
      const SizedBox(height: 8),
      if (rows.isEmpty)
        const _Panel(title: 'Không còn việc cần chuyển tiếp', body: 'Ghi chú cho ca sau rồi xác nhận bàn giao.'),
      for (final row in rows) ...[
        _LeftoverCard(
          title: title(row),
          subtitle: who(row),
          tag: statusTag(row),
          note: splitNote(row.item?['note'] as String?),
          section: row.item?['section'] as String?,
          onWrite: canWriteReason(row) && !busy ? () => openReason(row) : null,
        ),
        const SizedBox(height: 8),
      ],
      if (sourceError != null) Text('Chưa đọc được việc chưa đóng của ca: $sourceError'),
      const SizedBox(height: 5),
      Text('Ghi chú cho ca sau', style: text.titleMedium),
      const SizedBox(height: 6),
      if (allowed('assess'))
        TextField(
          controller: assessment,
          enabled: !busy,
          minLines: 1,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Nhập ghi chú chung cho ca sau'),
        )
      else
        _Panel(body: (record!['generalAssessment'] as String?) ?? 'Chưa có nội dung được phép xem.'),
      for (final a in maps(record!['residentAssessments'])) ...[
        const SizedBox(height: 8),
        _Panel(
          title: names[a['residentId']] ?? 'Người cao tuổi: chưa có tên được phép xem',
          body: (a['content'] as String?) ?? 'Nội dung giới hạn theo quyền xem.',
        ),
      ],
      if (others.isNotEmpty || otherSources.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Nội dung bàn giao khác', style: text.titleMedium),
        const SizedBox(height: 6),
        for (final item in others) ...[
          _Panel(
            title: _groups[item['group']] ?? 'Nội dung theo dõi',
            body: [
              if (item['residentId'] != null) names[item['residentId']] ?? 'Người cao tuổi: chưa có tên được phép xem',
              (item['description'] as String?) ?? 'Nội dung giới hạn theo quyền xem.',
              if (item['note'] is String) 'Ghi chú: ${item['note']}',
              if (item['section'] == 'AFTER_PREPARATION') 'Phát sinh sau khi lập',
              if (item['resolved'] == true) 'Đã xử lý',
            ].join('\n'),
            action: allowed('deleteItem') && item['id'] is int
                ? TextButton(
                    onPressed: busy
                        ? null
                        : () => edit('DELETE', '/handovers/${record!['id']}/items/${item['id']}', 'Đã bỏ mục'),
                    child: const Text('Bỏ mục'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
        ],
        for (final source in otherSources) ...[
          _Panel(
            title: _groups[source['group']] ?? 'Nội dung theo dõi',
            body: source['dataUnavailable'] == true
                ? 'Chưa đọc được nguồn.'
                : (source['description'] as String?) ?? 'Nội dung giới hạn theo quyền xem.',
            action: source['dataUnavailable'] != true && source['description'] is String
                ? TextButton(
                    onPressed: busy
                        ? null
                        : () => edit(
                            'POST',
                            '/handovers/${record!['id']}/items',
                            'Đã thêm mục',
                            body: {
                              'group': source['group'],
                              'sourceType': source['sourceType'],
                              'sourceId': source['sourceId'],
                              if (source['residentId'] != null) 'residentId': source['residentId'],
                              if (source['roomId'] != null) 'roomId': source['roomId'],
                              'description': source['description'],
                            },
                          ),
                    child: const Text('Thêm'),
                  )
                : null,
          ),
          const SizedBox(height: 8),
        ],
      ],
      if (comments.isNotEmpty || allowed('comment')) ...[
        const SizedBox(height: 20),
        Text('Ý kiến của ca sau', style: text.titleMedium),
        const SizedBox(height: 6),
      ],
      for (final row in comments) ...[
        _Panel(
          title: (row['sender'] as String?) ?? 'Ý kiến bàn giao',
          body: [
            (row['content'] as String?) ?? '',
            for (final reply in maps(row['replies'])) 'Phản hồi: ${reply['content'] ?? ''}',
          ].join('\n'),
        ),
        if (allowed('supplementAndResubmit')) ...[
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('reply:${row['id']}'),
            initialValue: replies[row['id']],
            decoration: const InputDecoration(labelText: 'Phản hồi ý kiến'),
            maxLines: 3,
            enabled: !busy,
            onChanged: (value) => setState(() => replies[row['id'] as int] = value),
          ),
        ],
        const SizedBox(height: 8),
      ],
      if (allowed('comment')) ...[
        TextField(
          controller: comment,
          decoration: const InputDecoration(labelText: 'Ý kiến bàn giao'),
          maxLines: 3,
          enabled: !busy,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: busy || comment.text.trim().isEmpty
                ? null
                : () => act('comment', body: {'content': comment.text.trim()}),
            child: const Text('Gửi ý kiến'),
          ),
        ),
      ],
    ];
  }

  /// Thanh cuối màn (Figma "Thao tác cuối màn"): dòng nhắc rồi một nút chính theo lệnh backend cho phép.
  Widget _bottomBar(BuildContext context, List<_Leftover> rows, int missing) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    String? hint;
    var danger = false;
    Widget? button;
    if (!loading && record == null && (shift?['allowedCommands'] as List<dynamic>? ?? []).contains('createHandover')) {
      button = FilledButton(onPressed: busy ? null : () => act('create'), child: const Text('Lập bàn giao'));
    } else if (!loading && allowed('complete')) {
      if (missing > 0) {
        hint = 'Còn $missing việc thiếu lý do';
        danger = true;
      } else if (rows.isNotEmpty) {
        hint = '${rows.length} việc sẽ được chuyển tiếp';
      }
      button = FilledButton(onPressed: busy || missing > 0 ? null : complete, child: const Text('Xác nhận bàn giao'));
    } else if (!loading && allowed('supplementAndResubmit')) {
      final comments = maps(record!['comments']);
      button = FilledButton(
        onPressed: busy || comments.any((row) => (replies[row['id']] ?? '').trim().isEmpty)
            ? null
            : () => act(
                'supplementAndResubmit',
                body: {
                  'replies': [
                    for (final row in comments) {'commentId': row['id'], 'content': replies[row['id']]!.trim()},
                  ],
                },
              ),
        child: const Text('Bổ sung và gửi lại'),
      );
    } else if (!loading && allowed('confirm')) {
      button = FilledButton(onPressed: busy ? null : () => act('confirm'), child: const Text('Nhận bàn giao'));
    }
    if (button == null) return const SizedBox.shrink();
    return _BottomBar(
      hint: hint == null
          ? null
          : Text(
              hint,
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(
                color: danger ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
      button: button,
    );
  }

  /// Figma "Đã gửi bàn giao": thẻ xác nhận giữa màn, nút "Về Ca của tôi".
  Widget _sentView(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    final starts = shift?['startsAt'] is String ? DateTime.parse(shift!['startsAt'] as String) : null;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: scheme.surfaceContainerHighest,
                        child: Icon(LucideIcons.check, color: tones.settledInk, size: 28),
                      ),
                      const SizedBox(height: 16),
                      Text('Đã gửi bàn giao', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      if (starts != null)
                        Text(
                          '${shiftName(shift!)} · ${formatDate(starts.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10))}',
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      const SizedBox(height: 10),
                      _Pill(label: 'Chờ ca sau xác nhận', fill: scheme.secondaryContainer, ink: scheme.secondary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _BottomBar(
          button: FilledButton(
            onPressed: widget.onDone ?? () => Navigator.of(context).maybePop(),
            child: const Text('Về Ca của tôi'),
          ),
        ),
      ],
    );
  }
}

/// Một việc còn lại: mục bàn giao đã có ([item]) hoặc việc chưa đóng của ca chưa thành mục ([source]).
class _Leftover {
  const _Leftover({this.item, this.source});

  final Map<String, dynamic>? item;
  final Map<String, dynamic>? source;
}

/// Thẻ ca (Figma "Ca vừa kết thúc"): nền xanh trời nhạt, tên ca, ngày và giờ, nhãn trạng thái bàn giao.
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({required this.shift, required this.status});

  final Map<String, dynamic> shift;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = shift['startsAt'] is String ? DateTime.parse(shift['startsAt'] as String) : null;
    final end = shift['endsAt'] is String ? DateTime.parse(shift['endsAt'] as String) : null;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 11, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    start == null ? 'Ca làm việc' : shiftName(shift),
                    style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                  ),
                  if (start != null && end != null)
                    Text(
                      '${formatDate(start.toUtc().add(const Duration(hours: 7)).toIso8601String().substring(0, 10))} · '
                      '${formatTime(start)}–${formatTime(end)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.secondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Pill(label: status, fill: scheme.surface, ink: scheme.secondary),
          ],
        ),
      ),
    );
  }
}

/// Thẻ việc còn lại (Figma "Component · Bàn giao ca"): tên việc, nhãn trạng thái, người · phòng, vạch ngăn, rồi lý do
/// đã nhập hoặc dòng đỏ "Bổ sung lý do".
class _LeftoverCard extends StatelessWidget {
  const _LeftoverCard({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.note,
    required this.section,
    required this.onWrite,
  });

  final String title;
  final String subtitle;
  final (String, bool)? tag;
  final (String, String) note;
  final String? section;
  final VoidCallback? onWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final (reason, next) = note;
    final label = text.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface);
    final value = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final hasReason = reason.trim().isNotEmpty;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TaskHead(title: title, subtitle: subtitle, tag: tag),
          if (section == 'AFTER_PREPARATION')
            Text('Phát sinh sau khi lập', style: text.labelSmall?.copyWith(color: scheme.secondary)),
          const SizedBox(height: 8),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 8),
          if (hasReason) ...[
            Text('Lý do chưa hoàn thành', style: label),
            Text(reason, style: value),
            if (next.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Việc ca sau cần làm', style: label),
              Text(next, style: value),
            ],
          ] else ...[
            Text('Lý do chưa hoàn thành', style: label?.copyWith(color: scheme.error)),
            const SizedBox(height: 6),
            if (onWrite == null)
              Text('Chưa có lý do.', style: value)
            else
              Material(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: onWrite,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Bổ sung lý do',
                              style: text.labelLarge?.copyWith(color: scheme.error, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(LucideIcons.chevronRight, size: 18, color: scheme.error),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: hasReason && onWrite != null
          ? InkWell(
              onTap: onWrite,
              child: Semantics(button: true, hint: 'Sửa lý do', child: body),
            )
          : body,
    );
  }
}

class _TaskHead extends StatelessWidget {
  const _TaskHead({required this.title, required this.subtitle, required this.tag});

  final String title;
  final String subtitle;
  final (String, bool)? tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tagValue = tag;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            if (tagValue != null) ...[
              const SizedBox(width: 8),
              _Pill(
                label: tagValue.$1,
                fill: tagValue.$2 ? scheme.errorContainer : scheme.secondaryContainer,
                ink: tagValue.$2 ? scheme.error : scheme.secondary,
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Nhãn nền nhạt bo tròn (Figma "Trạng thái": "Quá hạn", "Chờ bàn giao").
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.fill, required this.ink});

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    // Chữ phóng to thì nhãn xuống dòng, không đẩy tràn hàng.
    constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.4),
    child: DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink, fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );
}

/// Khối trắng viền mảnh: tiêu đề, nội dung, thao tác phụ.
class _Panel extends StatelessWidget {
  const _Panel({this.title, this.body, this.action});

  final String? title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) Text(title!, style: theme.textTheme.titleMedium),
            if (body != null)
              Text(body!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (action != null) Align(alignment: Alignment.centerLeft, child: action),
          ],
        ),
      ),
    );
  }
}

/// Thanh thao tác cuối màn: nền trắng, dòng nhắc, nút chính rộng hết, cao 52.
class _BottomBar extends StatelessWidget {
  const _BottomBar({this.hint, required this.button});

  final Widget? hint;
  final Widget button;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hint != null) ...[hint!, const SizedBox(height: 8)],
              SizedBox(
                height: 52,
                // Figma "Thao tác cuối màn": nút chữ nhật bo vừa, không bo tròn hẳn.
                child: FilledButtonTheme(
                  data: FilledButtonThemeData(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                  child: button,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Figma "Bàn giao ca · Bổ sung lý do": thẻ việc, "Lý do chưa hoàn thành *" bắt buộc, "Việc ca sau cần làm", nút "Lưu
/// lý do" chỉ bật khi đã có lý do. Trả về (lý do, việc ca sau cần làm).
class _ReasonScreen extends StatefulWidget {
  const _ReasonScreen({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.reason,
    required this.next,
  });

  final String title;
  final String subtitle;
  final (String, bool)? tag;
  final String reason;
  final String next;

  @override
  State<_ReasonScreen> createState() => _ReasonScreenState();
}

class _ReasonScreenState extends State<_ReasonScreen> {
  late final reason = TextEditingController(text: widget.reason);
  late final next = TextEditingController(text: widget.next);

  @override
  void dispose() {
    reason.dispose();
    next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final ready = reason.text.trim().isNotEmpty;
    return Scaffold(
      appBar: headerAppBar(context, title: 'Bổ sung lý do'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: _TaskHead(title: widget.title, subtitle: widget.subtitle, tag: widget.tag),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Lý do chưa hoàn thành *', style: label),
                const SizedBox(height: 7),
                TextField(
                  key: const ValueKey('handover.reason'),
                  controller: reason,
                  minLines: 3,
                  maxLines: 5,
                  autofocus: widget.reason.isEmpty,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Nhập lý do chưa hoàn thành'),
                ),
                if (!ready) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Cần nhập lý do để lưu.',
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Việc ca sau cần làm', style: label),
                const SizedBox(height: 7),
                TextField(
                  key: const ValueKey('handover.next'),
                  controller: next,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'Ghi bước tiếp theo cho ca sau'),
                ),
              ],
            ),
          ),
          _BottomBar(
            button: FilledButton(
              onPressed: ready ? () => Navigator.pop(context, (reason.text.trim(), next.text.trim())) : null,
              child: const Text('Lưu lý do'),
            ),
          ),
        ],
      ),
    );
  }
}
