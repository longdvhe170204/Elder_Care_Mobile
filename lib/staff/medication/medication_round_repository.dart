import 'dart:convert';

import '../../common/api/api_client.dart';
import '../../common/offline/offline_queue.dart';
import 'medication_round_cache.dart';
import 'medication_round_gateway.dart';

/// Loáº¡i báº£n ghi ngoáº¡i tuyáº¿n cá»§a káº¿t quáº£ liá»u (backend `DoseResultOfflineHandler.RECORD_TYPE`).
const doseResultRecordType = 'M07.DOSE_RESULT';

/// Liá»u thuá»‘c kiá»ƒm soÃ¡t Ä‘áº·c biá»‡t khÃ´ng Ä‘Æ°á»£c lÆ°u táº¡m trÃªn mÃ¡y (FR-029, BR-M07-20, Q-01).
class RequiresOnline implements Exception {}

class MedicationRoundLoad {
  const MedicationRoundLoad(this.round, {required this.offline, this.queued = const {}});
  final CachedMedicationRound round;
  final bool offline;

  /// doseKey â†’ káº¿t quáº£ Ä‘Ã£ ghi trÃªn mÃ¡y, chÆ°a Ä‘á»“ng bá»™ (nhÃ£n "ChÆ°a Ä‘á»“ng bá»™", DESIGN.md 15.5).
  final Map<String, String> queued;
}

enum RecordSaved { online, queued }

/// Táº£i vÃ²ng phÃ¡t thuá»‘c vÃ  ghÃ©p trÆ°á»ng hiá»ƒn thá»‹ cá»§a FR-020 tá»« cÃ¡c operation cÃ³ sáºµn (khÃ´ng Ä‘á»•i há»£p Ä‘á»“ng `Dose`):
/// `Prescription` (liá»u, Ä‘Æ°á»ng dÃ¹ng, hÆ°á»›ng dáº«n), `Medication` (tÃªn, hÃ m lÆ°á»£ng, Ä‘Æ¡n vá»‹), há»“ sÆ¡ 001 (há» tÃªn, dá»‹ á»©ng
/// Hiá»‡u lá»±c). Máº¥t máº¡ng thÃ¬ tráº£ báº£n Ä‘Ã£ táº£i gáº§n nháº¥t; 403, 404 thÃ¬ xÃ³a báº£n Ä‘Ã³, khÃ´ng phá»¥c há»“i ná»™i dung Ä‘Ã£ máº¥t quyá»n.
class MedicationRoundRepository {
  MedicationRoundRepository(this.gateway, this.cache, this.queue, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final MedicationRoundGateway gateway;
  final MedicationRoundCache cache;
  final OfflineQueue queue;
  final DateTime Function() clock;

  Future<MedicationRoundLoad> load(int accountId) async {
    try {
      final round = CachedMedicationRound(await _compose(await gateway.rounds()), clock());
      await cache.save(accountId, round);
      return MedicationRoundLoad(round, offline: false, queued: await _queued(accountId));
    } on ApiUnreachable {
      final cached = await cache.read(accountId);
      if (cached == null) rethrow;
      return MedicationRoundLoad(cached, offline: true, queued: await _queued(accountId));
    } on ApiProblem catch (problem) {
      if (problem.status == 403 || problem.status == 404) await cache.remove(accountId);
      rethrow;
    }
  }

  Future<Map<String, String>> _queued(int accountId) async => {
    for (final record in await queue.unsynced(accountId))
      if (record.recordType == doseResultRecordType)
        (jsonDecode(record.content) as Map)['doseKey'] as String:
            (jsonDecode(record.content) as Map)['resultType'] as String,
  };

  Future<List<Map<String, dynamic>>> _compose(List<Map<String, dynamic>> doses) async {
    final prescriptions = await _byId(doses.map((d) => d['prescriptionId'] as int), gateway.prescription);
    final medications = await _byId(prescriptions.values.map((p) => p['medicationId'] as int), gateway.medication);
    final residents = await _byId(doses.map((d) => d['residentId'] as int), _residentOrNull);
    return [
      for (final dose in doses)
        _item(
          dose,
          prescriptions[dose['prescriptionId']]!,
          medications[prescriptions[dose['prescriptionId']]!['medicationId']]!,
          residents[dose['residentId']],
        ),
    ];
  }

  /// Há»“ sÆ¡ ngoÃ i pháº¡m vi xem cá»§a ngÆ°á»i dÃ¹ng váº«n Ä‘á»ƒ liá»u hiá»‡n (backend Ä‘Ã£ cho liá»u vÃ o vÃ²ng), chá»‰ thiáº¿u há» tÃªn.
  Future<Map<String, dynamic>> _residentOrNull(int id) async {
    try {
      return await gateway.resident(id);
    } on ApiProblem catch (problem) {
      if (problem.status == 403 || problem.status == 404) return const {};
      rethrow;
    }
  }

  static Future<Map<int, Map<String, dynamic>>> _byId(
    Iterable<int> ids,
    Future<Map<String, dynamic>> Function(int) fetch,
  ) async {
    final unique = ids.toSet().toList();
    final values = await Future.wait(unique.map(fetch));
    return {for (var i = 0; i < unique.length; i++) unique[i]: values[i]};
  }

  static Map<String, dynamic> _item(
    Map<String, dynamic> dose,
    Map<String, dynamic> prescription,
    Map<String, dynamic> medication,
    Map<String, dynamic>? resident,
  ) {
    final hidden = (resident?['hiddenFields'] as List? ?? const []).contains('activeHealthItems');
    final healthItems = (resident?['activeHealthItems'] as List? ?? const []).map(
      (e) => Map<String, dynamic>.from(e as Map),
    );
    return {
      'dose': dose,
      'medication': {
        'name': medication['name'],
        'concentration': medication['concentration'],
        'usageUnit': medication['usageUnit'],
      },
      'prescription': {
        'dosage': prescription['dosage'],
        'route': prescription['route'],
        'instructionNote': prescription['instructionNote'],
        'timeCriticality': prescription['timeCriticality'],
        'requiredMeasurements': prescription['requiredMeasurements'],
      },
      'resident': {
        'fullName': (resident?['personalInfo'] as Map?)?['fullName'],
        // null: khÃ´ng Ä‘Æ°á»£c xem pháº§n sá»©c khá»e, mÃ n khÃ´ng hiá»‡n dÃ²ng dá»‹ á»©ng.
        'allergies': hidden || resident == null || resident.isEmpty
            ? null
            : [
                for (final item in healthItems)
                  if (item['type'] == 'ALLERGY' && item['status'] != 'EXCLUDED')
                    (item['allergen'] as Map?)?['name'] ?? item['freeText'],
              ].whereType<String>().toList(),
      },
    };
  }

  /// Liá»u Bá» lá»¡ ghi Ä‘Æ°á»£c "Ä‘Ã£ dÃ¹ng muá»™n": káº¿t quáº£ Ä‘Ã£ cÃ³ mÃ£ (api-006 `Dose.result.id`).
  static int? lateResultId(Map<String, dynamic> item) {
    final dose = item['dose'] as Map;
    if (dose['status'] != 'MISSED') return null;
    return (dose['result'] as Map?)?['id'] as int?;
  }

  Future<void> correctLate(Map<String, dynamic> item, DateTime at, String reason, String key) =>
      gateway.correctLate(lateResultId(item)!, at, reason, key);


  /// Ghi káº¿t quáº£ liá»u: cÃ³ máº¡ng thÃ¬ gá»i lá»‡nh trá»±c tuyáº¿n; máº¥t máº¡ng thÃ¬ Ä‘Æ°a vÃ o hÃ ng Ä‘á»£i `M07.DOSE_RESULT` (káº¿t quáº£
  /// Ä‘á»“ng bá»™ tá»«ng báº£n ghi á»Ÿ mÃ n Äá»“ng bá»™ cá»§a common, BR-M15-20); liá»u kiá»ƒm soÃ¡t Ä‘áº·c biá»‡t máº¥t máº¡ng thÃ¬ [RequiresOnline].
  Future<RecordSaved> record({
    required int accountId,
    required Map<String, dynamic> item,
    required DoseOutcome outcome,
    required Map<String, dynamic> body,
    required String key,
  }) async {
    final dose = Map<String, dynamic>.from(item['dose'] as Map);
    try {
      await gateway.record(dose['doseKey'] as String, outcome, body, key);
      return RecordSaved.online;
    } on ApiUnreachable {
      // HoÃ£n cÃ³ chá»§ Ä‘Ã­ch chá»‰ ghi khi cÃ³ máº¡ng (BR-M07-26): khÃ´ng Ä‘Æ°a vÃ o hÃ ng Ä‘á»£i
      if (outcome == DoseOutcome.postponed) rethrow;
      if (dose['requiresOnline'] == true) throw RequiresOnline();
      await queue.enqueue(
        accountId: accountId,
        recordType: doseResultRecordType,
        content: {
          'doseKey': dose['doseKey'],
          'residentId': dose['residentId'],
          'resultType': outcome.resultType,
          'administeredAt': ?body['administeredAt'],
          'reason': ?body['reason'],
          'adverseReaction': ?body['adverseReaction'],
          'note': ?body['note'],
          'measurements': ?body['measurements'],
        },
      );
      return RecordSaved.queued;
    }
  }
}
