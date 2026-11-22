import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/api/api_client.dart';
import '../../common/format/date_time.dart';
import '../../common/theme/app_theme.dart';
import '../../common/widgets/header_app_bar.dart';
import '../../common/widgets/page_body.dart';
import '../../common/widgets/status_pill.dart';
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
/// `links`: có thì khung chi tiết công việc có Xem kế hoạch chăm sóc, Báo sự cố và dòng bàn giao mở được màn Bàn giao ca.
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
    this.residentKey,
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

  /// Có thì màn là "Việc chăm sóc" của một người cao tuổi ([careGroupKey]) thay cho cả checklist (Figma 105:1324).
  final String? residentKey;
  @override
  State<CareChecklistScreen> createState() => _CareChecklistScreenState();
}

class _CareChecklistScreenState extends State<CareChecklistScreen> {
  CareChecklistLoad? loaded;
  String? error;
  bool busy = false;
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

  /// Kế hoạch chăm sóc của người cao tuổi của công việc (trước ở dải Tiến trình ca, nay ở khung chi tiết).
  Future<void> openPlan(Map<String, dynamic> task) => widget.links!.openPlans(context, [
    {
      'id': task['residentId'],
      'name': (task['residentCard'] as Map?)?['fullName'] ?? 'Người cao tuổi ${task['residentId']}',
    },
  ]);

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

  Future<bool> record(Map<String, dynamic> task) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CareResultForm(
        task: task,
        repository: widget.repository,
        newKey: careCommandKey,
        resultValues: (loaded!.snapshot.content['resultValues'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList(),
      ),
    );
    if (saved == true && mounted) await load();
    return saved == true;
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
  Future<void> openTask(Map<String, dynamic> task) {
    final data = loaded!.snapshot.content;
    final openAlerts = data['openAlerts'] as List?;
    final commands = task['allowedCommands'] as List? ?? const [];
    final pending = widget.repository.pendingTaskIds.contains(task['id']);
    final canWrite = loaded?.offline == false || widget.repository.recorder != null;
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _TaskDetail(
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
          onRecord: canWrite && commands.contains('record') && !pending ? () => record(task) : null,
          onClaim: loaded?.offline == false && commands.contains('claim') ? () => claim(task) : null,
          onNotPerform: canWrite && commands.contains('notPerform') && !pending ? () => notPerform(task) : null,
          onReport: widget.links != null && task['residentId'] != null ? () => report(task['residentId'] as int) : null,
          onPlan: widget.links != null && task['residentId'] != null ? () => openPlan(task) : null,
        ),
      ),
    );
  }

  /// Màn "Việc chăm sóc" của một người cao tuổi: đầu màn có dòng ca, thân là [_ResidentCare].
  Widget residentScaffold(BuildContext context) {
    final theme = Theme.of(context);
    final tones = theme.extension<Tones>()!;
    final data = loaded?.snapshot.content;
    final tasks =
        (data?['tasks'] as List? ?? [])
            .map((t) => Map<String, dynamic>.from(t as Map))
            .where((t) => careGroupKey(t) == widget.residentKey)
            .toList()
          ..sort((a, b) => (a['plannedAt'] as String? ?? '').compareTo(b['plannedAt'] as String? ?? ''));
    final residentId = tasks.firstOrNull?['residentId'];
    final doses = (data?['medicationDoses'] as List? ?? [])
        .map((d) => Map<String, dynamic>.from(d as Map))
        .where((d) => residentId != null && d['residentId'] == residentId)
        .toList();
    final canWrite = loaded?.offline == false || widget.repository.recorder != null;
    final note = widget.repository.lastQueued
        ? 'Chưa đồng bộ. Bản ghi đã lưu trên máy, sẽ đồng bộ khi có mạng.'
        : loaded?.offline == true
        ? 'Đang xem bản đã tải, chưa cập nhật.'
        : null;
    return Scaffold(
      appBar: headerAppBar(context, title: 'Việc chăm sóc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: tones.header,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
              child: Text(
                widget.shiftLabel ?? 'Ca ${widget.shiftId}',
                style: theme.textTheme.labelLarge?.copyWith(color: tones.headerInk),
              ),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (note != null || error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Semantics(
                liveRegion: true,
                child: _Notice(
                  icon: error != null ? LucideIcons.circleAlert : LucideIcons.wifiOff,
                  text: error ?? note!,
                  danger: error != null,
                ),
              ),
            ),
          Expanded(
            child: loaded == null
                ? const SizedBox.shrink()
                : RefreshIndicator(
                    onRefresh: load,
                    child: _ResidentCare(
                      tasks: tasks,
                      doses: doses,
                      pending: widget.repository.pendingTaskIds,
                      openAlerts: data?['openAlerts'] as List?,
                      onRecord: (task) =>
                          canWrite &&
                              (task['allowedCommands'] as List? ?? const []).contains('record') &&
                              !widget.repository.pendingTaskIds.contains(task['id'])
                          ? () => record(task)
                          : null,
                      onOpen: openTask,
                      onDose: (dose) => widget.medication == null ? null : () => openDose(dose['doseKey'] as String),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.residentKey != null) return residentScaffold(context);
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
    Widget taskRow(Map<String, dynamic> task) => _ChecklistRow(
      icon: _taskIcon(task),
      title: task['taskType'] as String? ?? '',
      subtitle: _taskLine(task),
      notes: [
        if (widget.repository.pendingTaskIds.contains(task['id'])) 'Chưa đồng bộ',
        if (task['awaitingRemeasurementConfirmation'] == true) 'Chờ xác nhận đo lại',
        ?followingLabel(openAlerts, task['residentId']),
      ],
      onTap: () => openTask(task),
    );
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

/// Chi tiết một công việc mở từ dòng checklist: ngữ cảnh (FR-030), nhãn Đang theo dõi, thỏa thuận lựa chọn có rủi ro và
/// các lệnh backend cho phép. Ghi nhận, Không thực hiện, Nhận việc xong thì đóng về checklist đã tải mới.
class _TaskDetail extends StatefulWidget {
  const _TaskDetail({
    required this.task,
    required this.pending,
    required this.followingLabel,
    required this.onFollowUps,
    required this.agreements,
    required this.onRecord,
    required this.onClaim,
    required this.onNotPerform,
    required this.onReport,
    required this.onPlan,
  });

  final Map<String, dynamic> task;
  final bool pending;
  final String? followingLabel;
  final VoidCallback? onFollowUps;
  final List<String> agreements;
  final Future<bool> Function()? onRecord;
  final Future<bool> Function()? onClaim;
  final Future<bool> Function()? onNotPerform;
  final Future<void> Function()? onReport;
  final Future<void> Function()? onPlan;

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
    final task = widget.task;
    return Scaffold(
      appBar: headerAppBar(context, title: task['taskType'] as String? ?? 'Công việc'),
      body: PageBody(
        child: ListView(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label: _status(task['status'] as String?),
                tone: task['status'] == 'OVERDUE' ? StatusTone.urgent : StatusTone.neutral,
              ),
            ),
            if (widget.pending) Text('Chưa đồng bộ', style: theme.textTheme.bodyMedium),
            if (task['awaitingRemeasurementConfirmation'] == true) const Text('Chờ xác nhận đo lại'),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CareTaskContext(task: task),
              ),
            ),
            if (widget.followingLabel case final label?) ...[
              const SizedBox(height: 8),
              if (widget.onFollowUps case final open?)
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                  onPressed: open,
                  child: Text('$label ›'),
                )
              else
                Text(label, style: theme.textTheme.bodyMedium),
            ],
            if (widget.agreements.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Lựa chọn đã thỏa thuận', style: theme.textTheme.titleSmall),
              for (final choice in widget.agreements) Text(choice),
            ],
            const SizedBox(height: 24),
            if (widget.onRecord case final record?)
              FilledButton(onPressed: busy ? null : () => run(record), child: const Text('Ghi nhận kết quả')),
            if (widget.onClaim case final claim?) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: busy ? null : () => run(claim), child: const Text('Nhận công việc')),
            ],
            if (widget.onNotPerform case final notPerform?) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: busy ? null : () => run(notPerform),
                child: const Text('Không thực hiện được…'),
              ),
            ],
            if (widget.onPlan case final plan?) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: plan, child: const Text('Xem kế hoạch chăm sóc')),
            ],
            if (widget.onReport case final report?) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: report, child: const Text('Báo sự cố')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Khóa nhóm công việc theo người cao tuổi (Figma 105:1024 "Checklist ca · Theo người cao tuổi"); việc không gắn người
/// cao tuổi nhóm theo nơi làm.
String careGroupKey(Map<String, dynamic> task) =>
    task['residentId'] != null ? 'r:${task['residentId']}' : 'l:${task['location'] ?? ''}';

/// Chữ viết tắt trên ảnh đại diện: chữ đầu của họ và của tên (Figma "NL" cho Nguyễn Thị Lan).
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  return words.length == 1 ? first.toUpperCase() : '$first${words.last.characters.first}'.toUpperCase();
}

const openTaskStatuses = {'OVERDUE', 'DUE', 'NOT_YET_DUE'};

/// "Việc chăm sóc" của một người cao tuổi trong ca (Figma 105:1324): thẻ người cao tuổi, "Cần thực hiện" có nút Ghi nhận,
/// liều thuốc của người đó, "Đã hoàn thành" thu gọn được. Bấm thẻ việc mở khung chi tiết (các lệnh khác, kế hoạch, sự cố).
class _ResidentCare extends StatefulWidget {
  const _ResidentCare({
    required this.tasks,
    required this.doses,
    required this.pending,
    required this.openAlerts,
    required this.onRecord,
    required this.onOpen,
    required this.onDose,
  });

  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> doses;
  final Set<int> pending;
  final List<dynamic>? openAlerts;

  /// null khi việc không ghi nhận được lúc này (backend không trả lệnh `record`, đang chờ đồng bộ, ngoại tuyến không ghi).
  final VoidCallback? Function(Map<String, dynamic> task) onRecord;
  final void Function(Map<String, dynamic> task) onOpen;
  final VoidCallback? Function(Map<String, dynamic> dose) onDose;

  @override
  State<_ResidentCare> createState() => _ResidentCareState();
}

class _ResidentCareState extends State<_ResidentCare> {
  bool showDone = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tones = theme.extension<Tones>()!;
    final text = theme.textTheme;
    final first = widget.tasks.firstOrNull;
    final card = first?['residentCard'] as Map?;
    final name = card?['fullName'] as String? ?? first?['location'] as String? ?? 'Công việc tầng/khu';
    final open = widget.tasks.where((t) => openTaskStatuses.contains(t['status'])).toList();
    final done = widget.tasks.where((t) => !openTaskStatuses.contains(t['status'])).toList();
    final heading = text.titleLarge?.copyWith(fontSize: 19, fontWeight: FontWeight.w700);
    final following = followingLabel(widget.openAlerts, first?['residentId']);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _Box(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Row(
              children: [
                Initials(name: name, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: text.headlineSmall?.copyWith(fontSize: 21, fontWeight: FontWeight.w700)),
                      if (card?['roomBed'] case final String room)
                        Text(room, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 3),
                      Text(
                        '${done.length}/${widget.tasks.length} việc đã hoàn thành',
                        style: text.labelLarge?.copyWith(color: scheme.secondary, fontWeight: FontWeight.w600),
                      ),
                      if (following != null)
                        Text(following, style: text.bodySmall?.copyWith(color: tones.attentionInk)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Semantics(header: true, child: Text('Cần thực hiện', style: heading)),
            ),
            Text(
              '${open.length} việc',
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (open.isEmpty)
          _Box(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Không còn việc cần thực hiện.', style: text.bodyMedium),
            ),
          ),
        for (final task in open) ...[
          _TaskCard(
            task: task,
            pending: widget.pending.contains(task['id']),
            onRecord: widget.onRecord(task),
            onOpen: () => widget.onOpen(task),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.doses.isNotEmpty) ...[
          const SizedBox(height: 10),
          Semantics(header: true, child: Text('Liều thuốc', style: heading)),
          const SizedBox(height: 10),
          for (final dose in widget.doses) ...[
            _DoseCard(dose: dose, onRecord: widget.onDose(dose)),
            const SizedBox(height: 10),
          ],
        ],
        if (done.isNotEmpty) ...[
          const SizedBox(height: 10),
          _Box(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => showDone = !showDone),
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Đã hoàn thành · ${done.length} việc',
                              style: text.bodyLarge?.copyWith(color: tones.settledInk, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(
                            showDone ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                            semanticLabel: showDone ? 'Thu gọn' : 'Mở',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (showDone)
                  for (final task in done)
                    Material(
                      color: scheme.surfaceContainerHighest,
                      child: InkWell(
                        onTap: () => widget.onOpen(task),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task['taskType'] as String? ?? '',
                                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                [
                                  if (task['plannedAt'] case final String at) formatTime(DateTime.parse(at)),
                                  if (task['status'] != 'COMPLETED') _status(task['status'] as String?),
                                ].join(' · '),
                                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Thẻ một việc cần thực hiện: tên, giờ dự kiến và nhãn trạng thái, nút "Ghi nhận" bên phải.
class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.pending, required this.onRecord, required this.onOpen});

  final Map<String, dynamic> task;
  final bool pending;
  final VoidCallback? onRecord;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final overdue = task['status'] == 'OVERDUE';
    final ink = overdue ? scheme.error : scheme.secondary;
    final label = switch (task['status']) {
      'OVERDUE' => 'Quá hạn',
      'DUE' => 'Đến giờ',
      _ => 'Sắp tới',
    };
    return _Box(
      child: InkWell(
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task['taskType'] as String? ?? '',
                        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (task['plannedAt'] case final String at)
                            Text(
                              formatTime(DateTime.parse(at)),
                              style: text.labelLarge?.copyWith(color: ink, fontWeight: FontWeight.w600),
                            ),
                          _Chip(
                            label: label,
                            fill: overdue ? scheme.errorContainer : scheme.surfaceContainerHighest,
                            ink: ink,
                          ),
                          if (pending)
                            _Chip(
                              label: 'Chưa đồng bộ',
                              fill: scheme.surfaceContainerHighest,
                              ink: scheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (onRecord != null) _RecordButton(onPressed: onRecord!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DoseCard extends StatelessWidget {
  const _DoseCard({required this.dose, required this.onRecord});

  final Map<String, dynamic> dose;
  final VoidCallback? onRecord;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return _Box(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (dose['medication'] as Map?)?['description'] as String? ?? 'Liều thuốc ${dose['doseKey']}',
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (dose['plannedAt'] case final String at)
                      Text(
                        'Dự kiến ${formatTime(DateTime.parse(at))}',
                        style: text.labelLarge?.copyWith(color: scheme.secondary, fontWeight: FontWeight.w600),
                      ),
                  ],
                ),
              ),
              if (onRecord != null) ...[const SizedBox(width: 10), _RecordButton(onPressed: onRecord!)],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.secondary,
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: const Text('Ghi nhận'),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.fill, required this.ink});

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(AppRadius.menu)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: ink, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Ảnh đại diện chữ viết tắt, nền xanh trời nhạt bo 13 (Figma "Ảnh đại diện").
class Initials extends StatelessWidget {
  const Initials({super.key, required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(13)),
        child: Text(
          initialsOf(name),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.secondary, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Khối trắng bo 12 viền mảnh.
class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: child,
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
