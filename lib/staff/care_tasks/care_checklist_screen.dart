import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/format/date_time.dart';
import '../../common/theme/app_theme.dart';
import '../../common/widgets/header_app_bar.dart';
import '../../common/widgets/page_body.dart';
import '../alerts/alert_follow_up_screen.dart';
import '../alerts/alert_labels.dart';
import '../medication/dose_sheet.dart';
import '../medication/medication_labels.dart';
import '../medication/medication_round_repository.dart';
import '../medication/medication_round_screen.dart' show medicationCommandKey;
import 'care_checklist_links.dart';
import 'care_checklist_repository.dart';
import 'care_result_form.dart';
import 'care_task_context.dart';

String careCommandKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Nhận accountId/shiftId từ shell của A; không tự chọn một ca hoặc một tài khoản giả.
/// `links`: có thì khung chi tiết công việc có Báo sự cố và dòng bàn giao mở được màn Bàn giao ca.
class CareChecklistScreen extends StatefulWidget {
  const CareChecklistScreen({
    super.key,
    required this.repository,
    required this.accountId,
    required this.shiftId,
    this.links,
    this.medication,
    this.alertsApi,
    this.shiftLabel,
    this.taskId,
  });
  final CareChecklistRepository repository;

  /// Có thì nhãn "Đang theo dõi" bấm được, mở "Theo dõi cảnh báo" để ghi kết quả theo dõi (005 FR-057, Q-419).
  final ApiClient? alertsApi;
  final int accountId;
  final int shiftId;
  final CareChecklistLinks? links;

  /// Có quyền phát thuốc thì dòng liều bấm được, mở "Đối chiếu liều thuốc" (spec 2026-11-20 mục 5.2: liều thuốc là một
  /// dòng của Checklist ca, không còn mục Phát thuốc riêng); `null` thì dòng chỉ xem.
  final MedicationRoundRepository? medication;

  /// Dòng ca dưới tiêu đề (Figma "Ca sáng · Tầng 2 · 07:00–15:00"), lấy từ ca đã chọn; checklist không trả thông tin ca.
  final String? shiftLabel;

  /// Có thì màn là chi tiết của đúng công việc này trong ca (mở từ dòng của Checklist theo tuần), không phải cả checklist.
  final int? taskId;
  @override
  State<CareChecklistScreen> createState() => _CareChecklistScreenState();
}

class _CareChecklistScreenState extends State<CareChecklistScreen> {
  CareChecklistLoad? loaded;
  String? error;
  bool busy = false;
  bool recording = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(CareChecklistScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.shiftId != widget.shiftId ||
        oldWidget.repository != widget.repository) {
      loaded = null;
      error = null;
      load();
    }
  }

  Future<void> load() async {
    final token = ++generation;
    final accountId = widget.accountId, shiftId = widget.shiftId;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await widget.repository.load(accountId, shiftId);
      if (mounted && generation == token) setState(() => loaded = next);
    } catch (e) {
      if (mounted && generation == token) {
        setState(() {
          error = e is ApiProblem ? e.detail : 'Không tải được checklist. Kiểm tra kết nối rồi thử lại.';
          loaded = null;
        });
      }
    } finally {
      if (mounted && generation == token) setState(() => busy = false);
    }
  }

  /// Mở "Đối chiếu liều thuốc" (Figma 5:290) cho liều [doseKey] bằng khung ghi liều của vòng phát thuốc (006); liều
  /// không ghi được lúc này (chưa đến giờ, đã ghi, đang chờ đồng bộ) thì báo, không mở.
  Future<void> openDose(String doseKey) async {
    final medication = widget.medication!;
    final messenger = ScaffoldMessenger.of(context);
    List<Map<String, dynamic>> items;
    try {
      final round = await medication.load(widget.accountId);
      items = round.round.items
          .where((i) => (i['dose'] as Map)['doseKey'] == doseKey)
          .where((i) => doseRecordable((i['dose'] as Map)['status'] as String?))
          .where((i) => !round.queued.containsKey(doseKey))
          .toList();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Không tải được liều thuốc. Kiểm tra kết nối rồi thử lại.')));
      return;
    }
    if (!mounted) return;
    if (items.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Liều này chưa ghi nhận được lúc này.')));
      return;
    }
    final result = await Navigator.of(context).push<DoseSheetResult>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: headerAppBar(context, title: 'Đối chiếu liều thuốc'),
          body: DoseSheet(
            repository: medication,
            accountId: widget.accountId,
            items: items,
            newKey: medicationCommandKey,
            clock: DateTime.now,
          ),
        ),
      ),
    );
    if (result != null && mounted) await load();
  }

  Future<void> report(int? residentId) => widget.links!.reportIncident(context, residentId);

  Future<void> openHandover() => widget.links!.openHandover(context, widget.shiftId);

  /// Trả `true` khi đã nhận việc để khung chi tiết đóng lại, checklist tải mới.
  Future<bool> claim(Map<String, dynamic> task) async {
    setState(() => busy = true);
    try {
      await widget.repository.gateway.claim(task['id'] as int, careCommandKey());
      await load();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiProblem ? e.detail : 'Chưa nhận được công việc. Tải lại rồi thử lại.');
      }
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> notPerform(Map<String, dynamic> task) async {
    final reasons =
        (loaded!.snapshot.content['nonPerformanceReasonTypes'] as List? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .where((r) => r['status'] == 'ACTIVE')
            .toList()
          ..sort((a, b) => (b['fixed'] == true ? 1 : 0).compareTo(a['fixed'] == true ? 1 : 0));
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NotPerformedForm(repository: widget.repository, taskId: task['id'] as int, reasons: reasons),
    );
    if (saved == true && mounted) await load();
    return saved == true;
  }

  bool canRecord(Map<String, dynamic> task) =>
      (loaded?.offline == false || widget.repository.recorder != null) &&
      !widget.repository.pendingTaskIds.contains(task['id']) &&
      (task['allowedCommands'] as List? ?? const []).contains('record');

  // Q-446: Chỉ ghi nhận lại trực tuyến khi công việc cho phép đính chính.
  bool canReRecord(Map<String, dynamic> task) =>
      loaded?.offline == false && (task['allowedCommands'] as List? ?? const []).contains('reRecord');

  Future<bool> record(Map<String, dynamic> task, {bool quickCompletion = false, bool reRecord = false}) async {
    if (recording || !(reRecord ? canReRecord(task) : canRecord(task))) return false;
    recording = true;
    try {
      final values = loaded?.snapshot.content['resultValues'] as List? ?? [];
      final saved = await showCareResultDialog(
        context,
        task: task,
        repository: widget.repository,
        newKey: careCommandKey,
        resultValues: values.map((v) => Map<String, dynamic>.from(v as Map)).toList(),
        quickCompletion: quickCompletion,
        reRecord: reRecord,
      );
      if (saved == true && mounted) await load();
      return saved == true;
    } finally {
      recording = false;
    }
  }

  void openFollowUps(ApiClient api, List<dynamic>? openAlerts, Object? residentId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: headerAppBar(context, title: 'Theo dõi cảnh báo'),
        body: AlertFollowUpScreen(api: api, alertIds: followingAlertIds(openAlerts, residentId)),
      ),
    ),
  );

  /// Chi tiết công việc mở từ dòng checklist (Figma "Prototype · Mobile" 15:3317 "Ghi nhận công việc"): ngữ cảnh FR-030
  /// và các lệnh backend cho phép.
  Future<void> openTask(Map<String, dynamic> task) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => taskDetail(task)));

  Widget taskDetail(Map<String, dynamic> task) {
    final data = loaded!.snapshot.content;
    final openAlerts = data['openAlerts'] as List?;
    final commands = task['allowedCommands'] as List? ?? const [];
    final pending = widget.repository.pendingTaskIds.contains(task['id']);
    final canWrite = loaded?.offline == false || widget.repository.recorder != null;
    return _TaskDetail(
      task: task,
      pending: pending,
      followingLabel: followingLabel(openAlerts, task['residentId']),
      onFollowUps: widget.alertsApi == null
          ? null
          : () => openFollowUps(widget.alertsApi!, openAlerts, task['residentId']),
      agreements: [
        for (final entry in (data['riskAgreements'] as List? ?? []).map((a) => Map<String, dynamic>.from(a as Map)))
          if (entry['residentId'] == task['residentId'])
            for (final a in (entry['agreements'] as List? ?? []).map((a) => Map<String, dynamic>.from(a as Map)))
              a['choice'] as String? ?? '',
      ],
      onRecord: canRecord(task) ? () => record(task) : null,
      onClaim: loaded?.offline == false && commands.contains('claim') ? () => claim(task) : null,
      onReRecord: canReRecord(task) ? () => record(task, reRecord: true) : null,
      onNotPerform: canWrite && commands.contains('notPerform') && !pending ? () => notPerform(task) : null,
      onReport: widget.links != null && task['residentId'] != null ? () => report(task['residentId'] as int) : null,
    );
  }

  /// Màn mở từ dòng của Checklist theo tuần ([CareChecklistScreen.taskId]): tải checklist của ca rồi hiện chi tiết đúng
  /// công việc đó; ghi nhận, nhận việc, không thực hiện xong thì quay về lịch tuần.
  Widget taskScaffold(BuildContext context) {
    final task = (loaded?.snapshot.content['tasks'] as List? ?? [])
        .map((t) => Map<String, dynamic>.from(t as Map))
        .where((t) => t['id'] == widget.taskId)
        .firstOrNull;
    if (task != null) return taskDetail(task);
    return Scaffold(
      appBar: headerAppBar(context, title: 'Công việc'),
      body: PageBody(
        child: busy
            ? const Center(child: CircularProgressIndicator())
            : Text(error ?? 'Công việc này không còn trong checklist của ca.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.taskId != null) return taskScaffold(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    final data = loaded?.snapshot.content;
    final tasks = (data?['tasks'] as List? ?? []).map((t) => Map<String, dynamic>.from(t as Map)).toList()
      ..sort((a, b) => (a['plannedAt'] as String? ?? '').compareTo(b['plannedAt'] as String? ?? ''));
    final openAlerts = data?['openAlerts'] as List?;
    final names = <Object?, String>{
      for (final t in tasks)
        if ((t['residentCard'] as Map?)?['fullName'] case final String name) t['residentId']: name,
    };
    Widget taskRow(Map<String, dynamic> task) {
      final title = task['taskType'] as String? ?? '';
      final row = _ChecklistRow(
        icon: _taskIcon(task),
        title: title,
        subtitle: _taskLine(task),
        notes: [
          if (widget.repository.pendingTaskIds.contains(task['id'])) 'Chưa đồng bộ',
          if (task['awaitingRemeasurementConfirmation'] == true) 'Chờ xác nhận đo lại',
          ?followingLabel(openAlerts, task['residentId']),
        ],
        onTap: () => openTask(task),
      );
      if (task['resultType'] != 'PERFORMED' || !canRecord(task)) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row,
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: TextButton(
              onPressed: busy ? null : () => record(task, quickCompletion: true),
              child: Semantics(
                label: 'Đánh dấu hoàn thành: $title',
                excludeSemantics: true,
                child: const Text('Đánh dấu hoàn thành'),
              ),
            ),
          ),
        ],
      );
    }

    const open = {'OVERDUE', 'DUE', 'NOT_YET_DUE'};
    final groups = <(String, Color, List<Map<String, dynamic>>)>[
      ('Quá hạn', scheme.error, tasks.where((t) => t['status'] == 'OVERDUE').toList()),
      ('Bây giờ', scheme.onSurfaceVariant, tasks.where((t) => t['status'] == 'DUE').toList()),
      ('Sau đó', scheme.onSurfaceVariant, tasks.where((t) => t['status'] == 'NOT_YET_DUE').toList()),
      ('Đã xong', scheme.onSurfaceVariant, tasks.where((t) => !open.contains(t['status'])).toList()),
    ];
    final doses = (data?['medicationDoses'] as List? ?? []).map((d) => Map<String, dynamic>.from(d as Map)).toList();
    final alerts = (openAlerts ?? []).map((a) => Map<String, dynamic>.from(a as Map)).toList();
    final handoverTasks = data?['handoverTasks'] as Map?;
    final offlineNote = widget.repository.lastQueued
        ? 'Chưa đồng bộ. Bản ghi đã lưu trên máy, sẽ đồng bộ khi có mạng.'
        : loaded?.offline == true
        ? (widget.repository.recorder == null
              ? 'Đang xem bản đã tải. Kết nối lại và tải mới trước khi ghi nhận.'
              : 'Đang ngoại tuyến. Bản ghi sẽ đồng bộ khi có mạng.')
        : null;
    return Scaffold(
      appBar: headerAppBar(
        context,
        title: '',
        actions: [
          IconButton(
            tooltip: 'Tải lại checklist',
            onPressed: busy ? null : load,
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _ChecklistHeader(
              subtitle: widget.shiftLabel ?? 'Ca ${widget.shiftId}',
              updated: loaded == null
                  ? null
                  : '${loaded!.offline ? 'Chưa cập nhật · ' : 'Cập nhật '}${formatDateTime(loaded!.snapshot.loadedAt)}',
              tones: tones,
            ),
            if (busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (offlineNote != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: _Notice(icon: LucideIcons.wifiOff, text: offlineNote),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (error != null) ...[
                    _Notice(icon: LucideIcons.circleAlert, text: error!, danger: true),
                    const SizedBox(height: 8),
                  ],
                  if (loaded != null && tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Chưa có công việc trong phạm vi được giao.', style: theme.textTheme.bodyMedium),
                    ),
                  for (final (label, color, rows) in groups)
                    if (rows.isNotEmpty) _Section(label: label, color: color, rows: [for (final t in rows) taskRow(t)]),
                  if (doses.isNotEmpty)
                    _Section(
                      label: 'Liều thuốc',
                      color: scheme.onSurfaceVariant,
                      rows: [
                        for (final dose in doses)
                          _ChecklistRow(
                            icon: LucideIcons.pill,
                            title:
                                (dose['medication'] as Map?)?['description'] as String? ??
                                'Liều thuốc ${dose['doseKey']}',
                            subtitle: dose['plannedAt'] == null
                                ? null
                                : 'Dự kiến ${formatTime(DateTime.parse(dose['plannedAt'] as String))}',
                            onTap: widget.medication == null ? null : () => openDose(dose['doseKey'] as String),
                          ),
                      ],
                    ),
                  if (alerts.isNotEmpty)
                    _Section(
                      label: 'Cảnh báo đang mở',
                      color: scheme.onSurfaceVariant,
                      rows: [
                        for (final alert in alerts)
                          _ChecklistRow(
                            icon: LucideIcons.triangleAlert,
                            title: alert['type'] == null
                                ? 'Cảnh báo #${alert['id']}'
                                : alertTypeName(alert['type'] as String?),
                            subtitle: names[alert['residentId']],
                            onTap: widget.alertsApi == null || alert['residentId'] == null
                                ? null
                                : () => openFollowUps(widget.alertsApi!, openAlerts, alert['residentId']),
                          ),
                      ],
                    ),
                  if (handoverTasks?['receiveAtStart'] == true || handoverTasks?['prepareAtEnd'] == true)
                    _Section(
                      label: 'Bàn giao',
                      color: scheme.onSurfaceVariant,
                      rows: [
                        if (handoverTasks?['receiveAtStart'] == true)
                          _ChecklistRow(
                            icon: LucideIcons.arrowLeftRight,
                            title: 'Nhận bàn giao đầu ca',
                            onTap: widget.links == null ? null : openHandover,
                          ),
                        if (handoverTasks?['prepareAtEnd'] == true)
                          _ChecklistRow(
                            icon: LucideIcons.arrowLeftRight,
                            title: 'Lập bàn giao cuối ca',
                            onTap: widget.links == null ? null : openHandover,
                          ),
                      ],
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

/// Dòng phụ của dòng công việc (Figma "Nguyễn Thị Lan · P. 203 · 09:00"): người cao tuổi hoặc nơi làm, phòng giường,
/// giờ dự kiến.
String _taskLine(Map<String, dynamic> task) {
  final card = task['residentCard'] as Map?;
  return [
    card?['fullName'] as String? ?? task['location'] as String? ?? 'Công việc tầng/khu',
    if (card?['roomBed'] case final String roomBed) roomBed,
    if (task['plannedAt'] case final String at) formatTime(DateTime.parse(at)),
  ].join(' · ');
}

/// Biểu tượng theo trạng thái rồi nguồn sinh (Figma: đồng hồ cho việc quá hạn, nhịp cho đo, đĩa cho bữa ăn).
IconData _taskIcon(Map<String, dynamic> task) {
  if (task['status'] == 'OVERDUE') return LucideIcons.clock;
  if (!const {'DUE', 'NOT_YET_DUE'}.contains(task['status'])) return LucideIcons.circleCheck;
  return switch ((task['basis'] as Map?)?['type']) {
    'MEASUREMENT' => LucideIcons.activity,
    'MEAL' => LucideIcons.utensils,
    'ACTIVITY_SESSION' => LucideIcons.users,
    _ => LucideIcons.listChecks,
  };
}

/// Phần chữ của đầu màn xanh đêm (Figma "Đầu màn"): tiêu đề lớn, ca, giờ cập nhật.
class _ChecklistHeader extends StatelessWidget {
  const _ChecklistHeader({required this.subtitle, required this.updated, required this.tones});

  final String subtitle;
  final String? updated;
  final Tones tones;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ColoredBox(
      color: tones.header,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Checklist ca', style: text.headlineMedium?.copyWith(color: tones.headerInkStrong)),
            ),
            const SizedBox(height: 8),
            Text(subtitle, style: text.bodyMedium?.copyWith(color: tones.headerInk)),
            if (updated != null) Text(updated!, style: text.bodySmall?.copyWith(color: tones.headerInkMuted)),
          ],
        ),
      ),
    );
  }
}

/// Thẻ báo trắng có biểu tượng (Figma "Đang ngoại tuyến. Bản ghi sẽ đồng bộ khi có mạng.").
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.danger = false});

  final IconData icon;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Một nhóm của checklist (Figma "QUÁ HẠN", "BÂY GIỜ", "SAU ĐÓ"): nhãn chữ hoa rồi khối dòng trắng bo góc.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.color, required this.rows});

  final String label;
  final Color color;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
        ),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: ListTile.divideTiles(context: context, tiles: rows).toList(),
          ),
        ),
      ],
    ),
  );
}

/// Dòng của khối "Danh sách" (Figma): ô biểu tượng 36 nền phụ, tên việc, dòng phụ, ghi chú ngắn, mũi tên khi bấm được.
class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.icon, required this.title, this.subtitle, this.notes = const [], this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<String> notes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = theme.extension<Tones>()!;
    return ListTile(
      minTileHeight: 72,
      onTap: onTap,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.menu),
        ),
        child: SizedBox.square(dimension: 36, child: Icon(icon, size: 20, color: theme.colorScheme.secondary)),
      ),
      title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null && notes.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitle != null) Text(subtitle!),
                for (final note in notes)
                  Text(note, style: theme.textTheme.bodySmall?.copyWith(color: tones.attentionInk)),
              ],
            ),
      trailing: onTap == null ? null : const Icon(LucideIcons.chevronRight),
    );
  }
}

/// Chi tiết một công việc mở từ dòng checklist (Figma 192:1752 "Chi tiết công việc"): nhãn trạng thái, thẻ người cao
/// tuổi, hướng dẫn chăm sóc, lịch thực hiện, Đang theo dõi, lựa chọn đã thỏa thuận, khối Thao tác khác và nút Ghi nhận
/// kết quả cố định cuối màn. Chỉ hiện lệnh backend cho phép; ghi nhận, không thực hiện, nhận việc xong thì đóng về
/// checklist đã tải mới.
class _TaskDetail extends StatefulWidget {
  const _TaskDetail({
    required this.task,
    required this.pending,
    required this.followingLabel,
    required this.onFollowUps,
    required this.agreements,
    required this.onRecord,
    required this.onClaim,
    this.onReRecord,
    required this.onNotPerform,
    required this.onReport,
  });

  final Map<String, dynamic> task;
  final bool pending;
  final String? followingLabel;
  final VoidCallback? onFollowUps;
  final List<String> agreements;
  final Future<bool> Function()? onRecord;
  final Future<bool> Function()? onClaim;
  final Future<bool> Function()? onReRecord;
  final Future<bool> Function()? onNotPerform;
  final Future<void> Function()? onReport;

  @override
  State<_TaskDetail> createState() => _TaskDetailState();
}

class _TaskDetailState extends State<_TaskDetail> {
  bool busy = false;

  Future<void> run(Future<bool> Function() action) async {
    setState(() => busy = true);
    final done = await action();
    if (!mounted) return;
    setState(() => busy = false);
    if (done) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    final text = theme.textTheme;
    final task = widget.task;
    final card = task['residentCard'] as Map?;
    final status = task['status'] as String?;
    final importance = const {'IMPORTANT': 'Quan trọng', 'MANDATORY': 'Bắt buộc'}[task['importance']];
    final carryover = const {
      'FROM_PREVIOUS_SHIFT': 'Tồn từ ca trước',
      'AWAITING_CONFIRMATION': 'Tồn, chờ xác nhận bàn giao',
    }[task['carryover']];
    final source = CareTaskContext.sources[(task['basis'] as Map?)?['type']];
    final planned = task['plannedAt'] as String?;
    final from = task['windowFrom'] as String?, to = task['windowTo'] as String?;
    final muted = text.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500);
    final heading = text.titleSmall?.copyWith(fontWeight: FontWeight.w700);

    // Nút cuối màn là lệnh chính còn được phép: Ghi nhận kết quả, rồi Ghi nhận lại (Q-446), rồi Nhận công việc.
    final primary = widget.onRecord != null
        ? ('Ghi nhận kết quả', widget.onRecord!)
        : widget.onReRecord != null
        ? ('Ghi nhận lại', widget.onReRecord!)
        : widget.onClaim != null
        ? ('Nhận công việc', widget.onClaim!)
        : null;
    final actions = <(String, VoidCallback?)>[
      if (widget.onRecord != null)
        if (widget.onClaim case final claim?) ('Nhận công việc', busy ? null : () => run(claim)),
      if (widget.onNotPerform case final notPerform?) ('Không thực hiện được…', busy ? null : () => run(notPerform)),
      if (widget.onReport case final report?) ('Báo sự cố', report),
    ];

    return Scaffold(
      appBar: headerAppBar(context, title: 'Chi tiết công việc'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(
                      label: _status(status),
                      fill: switch (status) {
                        'OVERDUE' => scheme.errorContainer,
                        'DUE' => tones.attentionWash,
                        _ => scheme.surfaceContainerHighest,
                      },
                      ink: switch (status) {
                        'OVERDUE' => scheme.error,
                        'DUE' => tones.attentionInk,
                        _ => scheme.onSurfaceVariant,
                      },
                    ),
                    if (importance != null) _Tag(label: importance, fill: tones.attentionWash, ink: tones.attentionInk),
                    if (carryover != null) _Tag(label: carryover, fill: tones.occupiedWash, ink: tones.occupiedInk),
                    if (widget.pending) _Tag(label: 'Chưa đồng bộ', fill: tones.attentionWash, ink: tones.attentionInk),
                    if (task['awaitingRemeasurementConfirmation'] == true)
                      _Tag(label: 'Chờ xác nhận đo lại', fill: tones.attentionWash, ink: tones.attentionInk),
                  ],
                ),
                const SizedBox(height: 10),
                _DetailCard(
                  child: Row(
                    children: [
                      _Initials(name: card?['fullName'] as String?),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card == null ? 'Vị trí' : 'Người cao tuổi', style: muted),
                            Text(
                              card?['fullName'] as String? ?? task['location'] as String? ?? 'Công việc tầng/khu',
                              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (card?['roomBed'] case final String roomBed)
                              Text(roomBed, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _DetailCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text('Hướng dẫn chăm sóc', style: heading)),
                      const SizedBox(height: 6),
                      Text(
                        task['taskType'] as String? ?? 'Công việc',
                        style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (task['content'] case final String content) Text(content, style: text.bodyLarge),
                      if (card?['careNotes'] case final String notes) ...[
                        const SizedBox(height: 6),
                        Text('Lưu ý: $notes', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _DetailCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(header: true, child: Text('Lịch thực hiện', style: heading)),
                      const SizedBox(height: 4),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _Field(
                                label: 'Dự kiến',
                                value: planned == null ? '—' : formatDateTime(DateTime.parse(planned)),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
                            ),
                            Expanded(
                              child: _Field(
                                label: 'Khung giờ',
                                value: from == null || to == null
                                    ? '—'
                                    : '${formatTime(DateTime.parse(from))}–${formatTime(DateTime.parse(to))}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        [
                          if (source != null) 'Nguồn: $source',
                          task['performer'] == null ? 'Chưa ai nhận' : 'Phụ trách: ${task['performer']}',
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (widget.followingLabel case final label?) ...[
                  const SizedBox(height: 10),
                  _DetailCard(
                    padding: EdgeInsets.zero,
                    child: InkWell(
                      onTap: widget.onFollowUps,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.errorContainer,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: SizedBox.square(
                                dimension: 36,
                                child: Icon(LucideIcons.bell, size: 18, color: scheme.error),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Đang theo dõi', style: muted),
                                  Text(
                                    label.startsWith('Đang theo dõi: ') ? label.substring(15) : label,
                                    style: text.bodyMedium?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.onFollowUps != null)
                              Icon(LucideIcons.chevronRight, size: 20, color: scheme.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.agreements.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _DetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text('Lựa chọn đã thỏa thuận', style: heading)),
                        const SizedBox(height: 4),
                        for (final choice in widget.agreements) Text(choice, style: text.bodyLarge),
                      ],
                    ),
                  ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Semantics(header: true, child: Text('Thao tác khác', style: heading)),
                  const SizedBox(height: 6),
                  _DetailCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, (label, onTap)) in actions.indexed) ...[
                          if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: scheme.outlineVariant),
                          InkWell(
                            onTap: onTap,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: text.bodyLarge?.copyWith(
                                          color: onTap == null ? scheme.onSurfaceVariant : scheme.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    Icon(LucideIcons.chevronRight, size: 20, color: scheme.primary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (primary case (final label, final action))
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    // Figma "Ghi nhận kết quả · Cố định": nút chữ nhật bo vừa, không bo tròn hẳn.
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      onPressed: busy ? null : () => run(action),
                      child: Text(label),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Khối trắng viền mảnh bo 14 của màn chi tiết (Figma "Người cao tuổi", "Hướng dẫn chăm sóc", "Lịch thực hiện").
class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Nhãn trạng thái nền nhạt bo tròn (Figma "Quá hạn", "Quan trọng", "Tồn từ ca trước").
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.fill, required this.ink});

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: ink, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Ô chữ viết tắt bo góc của người cao tuổi (Figma "Chữ viết tắt"): chữ đầu của họ và của tên gọi.
class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = (name ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? null
        : (words.length == 1 ? words.first[0] : '${words.first[0]}${words.last[0]}').toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(13)),
        child: initials == null
            ? Icon(LucideIcons.mapPin, size: 20, color: theme.colorScheme.secondary)
            : Text(
                initials,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

/// Một cột của "Lịch thực hiện": nhãn nhỏ rồi giá trị đậm.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

String _status(String? status) =>
    const {
      'NOT_YET_DUE': 'Chưa đến hạn',
      'DUE': 'Đến hạn',
      'OVERDUE': 'Quá hạn',
      'COMPLETED': 'Hoàn thành',
      'COMPLETED_LATE': 'Hoàn thành trễ',
      'NOT_PERFORMED': 'Không thực hiện',
      'CANCELLED': 'Hủy',
    }[status] ??
    status ??
    '';

class _NotPerformedForm extends StatefulWidget {
  const _NotPerformedForm({required this.repository, required this.taskId, required this.reasons});
  final CareChecklistRepository repository;
  final int taskId;
  final List<Map<String, dynamic>> reasons;
  @override
  State<_NotPerformedForm> createState() => _NotPerformedFormState();
}

class _NotPerformedFormState extends State<_NotPerformedForm> {
  final note = TextEditingController();
  int? reason;
  String? error;
  String? retrySignature;
  String? retryKey;
  bool busy = false;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (reason == null) {
      setState(() => error = 'Chọn loại lý do Không thực hiện.');
      return;
    }
    final signature = '$reason:${note.text}';
    if (signature != retrySignature) {
      retrySignature = signature;
      retryKey = careCommandKey();
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.notPerform(widget.taskId, reason!, note.text, retryKey!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiProblem ? e.detail : 'Chưa gửi được. Giữ nguyên nội dung để thử lại.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Không thực hiện', style: Theme.of(context).textTheme.titleLarge),
            const Text('Loại lý do (bắt buộc)'),
            RadioGroup<int>(
              groupValue: reason,
              onChanged: (value) {
                if (!busy) setState(() => reason = value);
              },
              child: Column(
                children: [
                  for (final r in widget.reasons)
                    RadioListTile<int>(value: r['id'] as int, title: Text(r['name'] as String), enabled: !busy),
                ],
              ),
            ),
            TextField(
              controller: note,
              enabled: !busy,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
            ),
            const Text('Có thể ghi điều người cao tuổi đã nói.'),
            if (error != null) Text(error!),
            FilledButton(onPressed: busy ? null : save, child: Text(busy ? 'Đang lưu…' : 'Lưu Không thực hiện')),
          ],
        ),
      ),
    ),
  );
}
