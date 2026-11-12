import 'package:supabase_flutter/supabase_flutter.dart';

class SavedCaseRecord {
  final String id;
  final String caseId;
  final String patientName;
  final String species;
  final String breed;
  final String chiefComplaint;
  final String leadingDiagnosis;
  final String clinicalGateStatus;
  final double? analysisSeconds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic> casePayload;
  final Map<String, dynamic> analysisResult;

  const SavedCaseRecord({
    required this.id,
    required this.caseId,
    required this.patientName,
    required this.species,
    required this.breed,
    required this.chiefComplaint,
    required this.leadingDiagnosis,
    required this.clinicalGateStatus,
    required this.analysisSeconds,
    required this.createdAt,
    required this.updatedAt,
    required this.casePayload,
    required this.analysisResult,
  });

  factory SavedCaseRecord.fromMap(Map<String, dynamic> map) {
    return SavedCaseRecord(
      id: map['id']?.toString() ?? '',
      caseId: map['case_id']?.toString() ?? '',
      patientName: map['patient_name']?.toString() ?? '',
      species: map['species']?.toString() ?? '',
      breed: map['breed']?.toString() ?? '',
      chiefComplaint: map['chief_complaint']?.toString() ?? '',
      leadingDiagnosis: map['leading_diagnosis']?.toString() ?? '',
      clinicalGateStatus: map['clinical_gate_status']?.toString() ?? '',
      analysisSeconds: _asDouble(map['analysis_seconds']),
      createdAt: _asDateTime(map['created_at']),
      updatedAt: _asDateTime(map['updated_at']),
      casePayload: _asMap(map['case_payload']),
      analysisResult: _asMap(map['analysis_result']),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }

    return <String, dynamic>{};
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static DateTime? _asDateTime(dynamic value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }
}

class CaseRepository {
  CaseRepository._();

  static SupabaseClient get _client => Supabase.instance.client;

  static User _requireUser() {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in veterinarian was found.');
    }
    return user;
  }

  static Future<void> saveAnalysis({
    required Map<String, dynamic> casePayload,
    required Map<String, dynamic> analysisResult,
  }) async {
    final user = _requireUser();

    final patient = _map(casePayload['patient']);
    final clinical = _map(casePayload['clinical']);
    final analysis = _map(analysisResult['analysis']);
    final performance = _map(analysisResult['performance']);

    final leadingDiagnosis = _leadingDiagnosis(analysis);
    final caseId = casePayload['case_id']?.toString().trim() ?? '';

    if (caseId.isEmpty) {
      throw StateError('The analyzed case has no case_id.');
    }

    final data = <String, dynamic>{
      'user_id': user.id,
      'case_id': caseId,
      'patient_name': patient['name']?.toString(),
      'species': patient['species']?.toString(),
      'breed': patient['breed']?.toString(),
      'chief_complaint': clinical['chief_complaint']?.toString(),
      'leading_diagnosis': leadingDiagnosis,
      'clinical_gate_status': analysis['clinical_gate_status']?.toString(),
      'analysis_seconds': _asDouble(performance['total_seconds']),
      'case_payload': casePayload,
      'analysis_result': analysisResult,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await _client
        .from('cases')
        .upsert(
          data,
          onConflict: 'user_id,case_id',
        );
  }

  static Future<List<SavedCaseRecord>> fetchCases() async {
    final user = _requireUser();

    final rows = await _client
        .from('cases')
        .select()
        .eq('user_id', user.id)
        .order('updated_at', ascending: false)
        .limit(200);

    if (rows is! List) {
      return const <SavedCaseRecord>[];
    }

    return rows
        .whereType<Map>()
        .map(
          (row) => SavedCaseRecord.fromMap(
            row.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        )
        .toList();
  }

  static Future<void> deleteCase(String id) async {
    final user = _requireUser();

    final deleted = await _client
        .from('cases')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('Case not found or deletion was not permitted.');
    }
  }

  static String _leadingDiagnosis(Map<String, dynamic> analysis) {
    final mostLikely = analysis['most_probable_diagnoses'];
    if (mostLikely is List && mostLikely.isNotEmpty) {
      final first = mostLikely.first;
      if (first is Map) {
        final value = first['diagnosis']?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }

    final ranked = analysis['ranked_differentials'];
    if (ranked is List && ranked.isNotEmpty) {
      final first = ranked.first;
      if (first is Map) {
        final value = first['diagnosis']?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }

    return '';
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return value.map(
        (key, item) => MapEntry(key.toString(), item),
      );
    }

    return <String, dynamic>{};
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
