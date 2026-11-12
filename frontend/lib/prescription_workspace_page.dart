import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_vet_api.dart';

/// Clinician-facing three-plan review with automatic vendor SKU price attempts.
/// Does not invent medications, doses, price data, or substitution equivalence.
class PrescriptionWorkspacePage extends StatefulWidget {
  final Map<String, dynamic> casePayload;
  final Map<String, dynamic> analysisResult;

  const PrescriptionWorkspacePage({
    super.key,
    required this.casePayload,
    required this.analysisResult,
  });

  @override
  State<PrescriptionWorkspacePage> createState() => _PrescriptionWorkspacePageState();
}

class _PrescriptionWorkspacePageState extends State<PrescriptionWorkspacePage> {
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _research;
  Map<String, dynamic>? _connectorAudit;
  bool _checkingConnectors = false;
  bool _genericSaving = false;
  bool _genericPreviewing = false;
  String? _genericMessage;
  String _genericForm = 'injection';
  String _genericUnit = 'ml';
  final _genericIngredient = TextEditingController(text: 'maropitant');
  final _genericStrength = TextEditingController(text: '10');
  final _genericPack = TextEditingController(text: '10');
  final _genericName = TextEditingController();
  final _genericBrand = TextEditingController();
  final _genericUrl = TextEditingController();
  final _genericPrice = TextEditingController();
  final _genericRecordedBy = TextEditingController();
  bool _genericProductChecked = false;
  bool _genericPreferred = false;
  String? _error;
  bool _loading = false;
  bool _discovering = false;
  String? _discoveryError;
  Map<String, dynamic>? _discovery;

  bool _savingQuote = false;
  bool _fetchingPrice = false;
  bool _confirmedProduct = false;
  bool _preferredBrand = false;
  String _priceSource = 'salardam';
  String _priceCurrency = 'TOMAN';
  String? _priceMessage;
  final _quoteName = TextEditingController();
  final _quoteBrand = TextEditingController();
  final _quoteUrl = TextEditingController();
  final _quotePackMl = TextEditingController(text: '10');
  final _quoteAmount = TextEditingController();
  final _quoteClinician = TextEditingController();
  final Map<String, bool> _clinicianChecks = {};

  @override
  void dispose() {
    for (final c in [_quoteName, _quoteBrand, _quoteUrl, _quotePackMl,
      _quoteAmount, _quoteClinician, _genericIngredient,
      _genericStrength, _genericPack, _genericName, _genericBrand,
      _genericUrl, _genericPrice, _genericRecordedBy]) { c.dispose(); }
    super.dispose();
  }

  static const _ink = Color(0xFF102F46);
  static const _teal = Color(0xFF087B76);

  @override
  void initState() {
    super.initState();
    // Open in evidence-search mode. A clinical Rx must not appear before review.
  }

  Map<String, dynamic> _map(dynamic data) =>
      data is Map ? data.map((key, value) => MapEntry(key.toString(), value)) : <String, dynamic>{};

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map((row) => _map(row)).toList();
  }

  String _text(dynamic value, [String fallback = '—']) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  String _frequency(dynamic perDay) {
    final n = perDay is num ? perDay.toDouble() : double.tryParse(_text(perDay, ''));
    if (n == null || n <= 0) return 'Frequency not set';
    final hours = 24.0 / n;
    return (hours - hours.roundToDouble()).abs() < 0.0001
        ? 'q${hours.round()}h'
        : '${_text(perDay)} administrations/day';
  }

  String _durationLabel(Map<String, dynamic> line) {
    final days = line['duration_days'];
    if (days != null) return '$days days';
    return 'NOT SET (source maximum ${_text(line['reference_max_duration_days'])} days)';
  }

  String _money(dynamic value) {
    if (value is! num) return 'Price not verified';
    final text = value.round().toString();
    final output = text.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '$output Toman';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(
        '${AssistantVetApi.baseUrl}/prescription/workflow',
      )).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({
        'case_payload': {...widget.casePayload, 'prescription_checks': _clinicianChecks},
        'analysis_result': widget.analysisResult,
      }));
      final response = await request.close().timeout(const Duration(seconds: 360));
      final data = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode != 200 || data is! Map) {
        throw const FormatException('Prescription service is not ready.');
      }
      if (!mounted) return;
      final responseMap = _map(data);
      if (_map(responseMap['plan']).isEmpty) {
        throw const FormatException('No full evidence-to-Rx workflow received.');
      }
      setState(() { _plan = _map(responseMap['plan']);
        _discovery = _map(responseMap['discovery']);
        _research = _map(responseMap['research']); });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error =
          'Cannot reach the prescription service. Ensure the updated Backend is running.\n$error');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _discoverEvidence() async {
    if (_discovering || _loading) return;
    setState(() {
      _discovering = true;
      _discoveryError = null;
      _error = null;
      // Clear the previous Rx: it must not be mistaken for the new analysis.
      _plan = null;
      _discovery = null;
      _research = null;
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('${AssistantVetApi.baseUrl}/prescription/workflow'),
      ).timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.write(jsonEncode({
        'case_payload': {...widget.casePayload, 'prescription_checks': _clinicianChecks},
        'analysis_result': widget.analysisResult,
      }));
      final response = await request.close().timeout(const Duration(seconds: 360));
      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 45));
      final data = jsonDecode(body);
      if (response.statusCode != 200 || data is! Map) {
        throw const FormatException('Integrated evidence review service is not ready.');
      }
      final workflow = _map(data);
      final discovery = _map(workflow['discovery']);
      final plan = _map(workflow['plan']);
      if (discovery.isEmpty || plan.isEmpty) {
        throw const FormatException('No complete workflow response received.');
      }
      if (!mounted) return;
      setState(() { _discovery = discovery; _plan = plan; _research = _map(workflow['research']); });
    } catch (error) {
      if (!mounted) return;
      setState(() => _discoveryError = error is TimeoutException
          ? 'The source review exceeded its time limit; no new prescription was generated.'
          : 'Could not complete the review. Check that the updated Backend is running. $error');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _discovering = false);
    }
  }


  // Clipboard helpers use the original response data, not the text currently
  // visible on screen. A collapsed section remains included in Copy all.
  Future<void> _copyEvidenceText(String label, String text) async {
    final value = text.trim();
    if (value.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No source text available to copy.')),
      );
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$label copied to clipboard.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not copy the source text.')),
      );
    }
  }

  String _excerptCopyText(Map<String, dynamic> part) => [
    '${_text(part['section_type'])} · p. ${_text(part['page_start'])}',
    'Reference ID: ${_text(part['source_id'])}',
    _text(part['exact_quote'], ''),
  ].join('\n');

  String _handbookCopyText(Map<String, dynamic> ref) {
    final review = _map(ref['monograph_review']);
    final parts = _rows(review['sections']);
    return [
      'PLUMB’S VETERINARY DRUG HANDBOOK — REFERENCE EXCERPTS',
      'Locator: ${_text(ref['locator'])}',
      'Passage context: ${_text(ref['passage_context'])}',
      'Reference ID: ${_text(ref['source_id'])}',
      'Review status: ${_text(review['status'])}',
      'Monograph boundary: ${_text(review['boundary'])}',
      'Clinical dosing section: ${_text(review['dose_section_status'], 'not_assessed')}',
      if (review['cross_drug_warning'] == true) ...[
        'WARNING: a possible OTHER DRUG dosage section was blocked from this monograph review.',
        for (final blocked in _rows(review['excluded_cross_drug_sections']))
          'Blocked ${_text(blocked['source_id'])}; foreign drug(s): ${_text(blocked['foreign_drug_names'])}',
      ],
      'Pharmacokinetic concentrations and mg/kg study exposures are NOT validated treatment doses.',
      'UNVERIFIED SOURCE EXCERPTS — NOT A PRESCRIPTION OR VERIFIED DOSING PROTOCOL',
      if (_rows(review['source_label_rows']).isNotEmpty) ...[
        '',
        'SOURCE TABLE ROWS (transcribed; unverified; NOT for prescribing):',
        for (final row in _rows(review['source_label_rows'])) ...[
          '---',
          'Drug: ${_text(row['ingredient'])} · Species: ${_text(row['species'])}',
          'Indication printed: ${_text(row['indication_as_printed'])}',
          'Minimum age printed: ${_text(row['minimum_age_as_printed'])}',
          'Form: ${_text(row['form_as_printed'])}',
          'Dose: ${_text(row['dose_as_printed'])} · Route: ${_text(row['route_as_printed'])}',
          'Frequency: ${_text(row['frequency_as_printed'])} · Duration: ${_text(row['duration_as_printed'])}',
          'Reference: ${_text(row['source_id'])} · p. ${_text(row['page_start'])}',
          'Exact source row: ${_text(row['exact_source_row'])}',
          'Patient suitability: NOT ASSESSED; prescription: NOT READY',
        ],
      ],
      '',
      'Located passage:',
      _text(ref['exact_quote'], ''),
      for (final part in parts) ...[
        '',
        '---',
        _excerptCopyText(part),
      ],
    ].join('\n');
  }

  String _candidateCopyText(Map<String, dynamic> item,
      Map<String, dynamic>? handbookRef) => [
    'DRUG NAME MENTION IN CLINICAL SOURCE — NOT AN APPROVED PRESCRIPTION',
    'Ingredient: ${_text(item['drug_name'])}',
    'Source: ${_text(item['source_title'])}',
    'Locator: ${_text(item['locator'])}',
    'Source ID: ${_text(item['source_id'])}',
    'Quoted source text:',
    _text(item['exact_quote'], ''),
    if (handbookRef != null) ...[
      '',
      _handbookCopyText(handbookRef),
    ],
  ].join('\n');

  String _allEvidenceCopyText(Map<String, dynamic> discovery) {
    final candidates = _rows(discovery['candidates']);
    final handbook = _rows(discovery['handbook_references']);
    final byName = <String, Map<String, dynamic>>{
      for (final item in handbook)
        _text(item['drug_name'], '').toLowerCase(): item,
    };
    final sources = _rows(discovery['sources_examined']);
    return [
      'ASSISTANT VET — TREATMENT SOURCE REVIEW (UNVERIFIED)',
      'Case ID: ${_text(widget.casePayload['case_id'])}',
      'Status: ${_text(discovery['status'])}',
      'NOT A PRESCRIPTION — ALL DRUG AND DOSE CLAIMS REQUIRE REVIEW',
      '',
      for (final item in candidates) ...[
        _candidateCopyText(
          item,
          byName[_text(item['drug_name'], '').toLowerCase()],
        ),
        '',
        '========================================',
        '',
      ],
      'SOURCES EXAMINED:',
      for (final source in sources)
        '- ${_text(source['title'])} · ${_text(source['locator'])}'
        ' · ${_text(source['case_applicability'])}',
    ].join('\n');
  }

  Widget _handbookReference(Map<String, dynamic> ref) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      initiallyExpanded: false,
      title: Text(_text(ref['passage_context']) == 'combination_entry_not_single_ingredient'
          ? 'Plumb’s: combination product — NOT a single-drug entry'
          : _text(ref['entry_match']) == 'possible_drug_entry_heading'
              ? 'Plumb’s: possible drug-entry heading'
              : 'Plumb’s: drug name mentioned (entry not verified)',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _teal)),
      subtitle: Text(_text(ref['locator']),
        style: const TextStyle(fontSize: 11, color: Color(0xFF58717D))),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: () => _copyEvidenceText(
              'All Plumb’s review excerpts', _handbookCopyText(ref)),
            icon: const Icon(Icons.copy_all_outlined, size: 16),
            label: const Text('Copy all review excerpts'),
          ),
        ),
        Text(_text(ref['review_note'], 'Name match only; not a prescription.'),
          style: const TextStyle(fontSize: 12, color: Color(0xFF945C23), height: 1.4)),
        const SizedBox(height: 4),
        Text('Passage context: ${_text(ref['passage_context'])} · Hits inspected: ${_text(ref['handbook_hits_inspected'])}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF58717D))),
        const SizedBox(height: 7),
        Text(_text(ref['exact_quote']),
          style: const TextStyle(color: _ink, fontSize: 12, height: 1.5)),
        if (_map(ref['monograph_review']).isNotEmpty) ...[
          const SizedBox(height: 10),
          Builder(builder: (context) {
            final review = _map(ref['monograph_review']);
            final parts = _rows(review['sections']);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Monograph review excerpts · ${parts.length} section cue(s) · ${_text(review['chunks_examined'], '0')} adjacent chunk(s)',
                style: const TextStyle(fontSize: 12, color: _ink, fontWeight: FontWeight.w800)),
              Text('Boundary: ${_text(review['boundary'])} · ${_text(review['status'])}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF58717D))),
              if (review['scan_scope_note'] != null)
                Text(_text(review['scan_scope_note']),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF58717D))),
              if (review['cross_drug_warning'] == true) ...[
                const SizedBox(height: 6),
                const Text('CROSS-DRUG SOURCE WARNING: a Dosages section mentioning another medication was excluded. It is NOT a dosing reference for the selected drug.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                    color: Color(0xFFB42318), height: 1.4)),
                for (final blocked in _rows(review['excluded_cross_drug_sections']))
                  Text('Blocked: ${_text(blocked['source_id'])} · Other drug: ${_text(blocked['foreign_drug_names'])}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF945C23))),
              ],
              const SizedBox(height: 5),
              Text(
                review['clinical_dosage_section_found'] == true
                    ? 'Possible Dosages / Administration heading located for MANUAL review. The case-specific regimen is still unverified.'
                    : 'No dedicated clinical dosage-section heading was found in the scanned text. Numbers in pharmacokinetics are NOT prescribing instructions.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: Color(0xFF945C23), height: 1.45),
              ),
              const SizedBox(height: 4),
              const Text('Unreviewed verbatim text only. No dose, indication, route, interval or patient regimen is approved. PDF OCR and entry boundaries require manual checking.',
                style: TextStyle(fontSize: 12, color: Color(0xFF945C23), height: 1.5)),
              if (_rows(review['source_label_rows']).isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('Structured source rows — for clinician review ONLY',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _ink)),
                const SizedBox(height: 4),
                const Text('Transcribed from the printed DOGS label table. Not a prescription. Patient suitability, contraindications, formulation, regulatory label and actual product strength are NOT checked.',
                  style: TextStyle(fontSize: 11, height: 1.5, color: Color(0xFF945C23))),
                for (final sourceRow in _rows(review['source_label_rows'])) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8F7),
                      border: Border.all(color: const Color(0xFFDDEAE8)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_text(sourceRow['ingredient'])} · ${_text(sourceRow['species'])} · ${_text(sourceRow['indication_as_printed'])}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: _ink)),
                      Text('Minimum age: ${_text(sourceRow['minimum_age_as_printed'])} · ${_text(sourceRow['form_as_printed'])}',
                        style: const TextStyle(fontSize: 12, color: _ink)),
                      Text('As printed: ${_text(sourceRow['dose_as_printed'])} · ${_text(sourceRow['route_as_printed'])} · ${_text(sourceRow['frequency_as_printed'])} · ${_text(sourceRow['duration_as_printed'])}',
                        style: const TextStyle(fontSize: 12, color: _ink)),
                      Text('${_text(sourceRow['source_id'])} · p. ${_text(sourceRow['page_start'])} · NOT APPROVED',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF945C23))),
                    ]),
                  ),
                ],
              ],
              if (parts.isEmpty)
                const Text('No section-specific text located. Check original monograph pages.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF58717D))),
              for (final part in parts) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: Text(
                    '${_text(part['section_type'])} · p. ${_text(part['page_start'])} · ${_text(part['source_id'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: _teal),
                  )),
                  IconButton(
                    tooltip: 'Copy this source excerpt',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.content_copy_outlined, size: 17, color: _teal),
                    onPressed: () => _copyEvidenceText('Source excerpt', _excerptCopyText(part)),
                  ),
                ]),
                if (_text(part['section_type']) == 'pharmacokinetics_context')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text('Drug exposure / pharmacokinetics only — NOT a verified treatment dose.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: Color(0xFF945C23))),
                  ),
                if (_text(part['section_type']) == 'clinical_dosage_section_candidate')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text('Potential dosage section — verify species, indication, original page, route, interval and patient restrictions.',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: Color(0xFF945C23))),
                  ),
                const SizedBox(height: 3),
                Text(_text(part['exact_quote']),
                  style: const TextStyle(fontSize: 12, height: 1.5, color: _ink)),
              ],
            ]);
          }),
        ],
        const SizedBox(height: 7),
        Text('Reference ID: ${_text(ref['source_id'])}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF58717D))),
      ],
    );
  }

  Widget _discoveryCard() {
    final discovery = _discovery ?? <String, dynamic>{};
    final candidates = _rows(discovery['candidates']);
    final handbook = _rows(discovery['handbook_references']);
    final handbookByName = <String, Map<String, dynamic>>{
      for (final row in handbook) _text(row['drug_name'], '').toLowerCase(): row,
    };
    final classOnly = _rows(discovery['excluded_class_mentions']);
    final sources = _rows(discovery['sources_examined']);
    final warnings = discovery['warnings'] is List
        ? (discovery['warnings'] as List).map((item) => item.toString()).toList()
        : <String>[];
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.menu_book_outlined, color: _teal),
          const SizedBox(width: 10),
          const Expanded(child: Text('1 · Search books and papers → assess case → build three plans',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink))),
          FilledButton.icon(
            onPressed: (_discovering || _loading) ? null : _discoverEvidence,
            icon: const Icon(Icons.search_outlined, size: 18),
            label: Text(_discovery == null ? 'Search & analyze' : 'Re-run review'),
          ),
        ]),
        const SizedBox(height: 9),
        const Text('One action: retrieve evidence, run local Qwen case review, enforce drug-safety checks and prepare First, Alternative and Economic drafts. Unverified drug mentions are never orders.',
          style: TextStyle(color: Color(0xFF58717D), height: 1.5)),
        if (_discovering) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
          const SizedBox(height: 7),
          const Text('Searching indexed textbooks and articles, checking case relevance and producing review drafts...',
            style: TextStyle(fontSize: 12, color: Color(0xFF617A83))),
        ],
        if (_discoveryError != null) ...[
          const SizedBox(height: 12),
          Text(_discoveryError!, style: const TextStyle(color: Colors.red)),
        ],
        if (_discovery != null) ...[
          const Divider(height: 27),
          Row(children: [
            Expanded(child: Text(
              'Evidence-name search ${_text(discovery['discovery_version'], 'source navigation')}',
              style: TextStyle(fontSize: 12, color: _teal, fontWeight: FontWeight.w700),
            )),
            OutlinedButton.icon(
              onPressed: () => _copyEvidenceText(
                'All treatment evidence', _allEvidenceCopyText(discovery)),
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Copy all evidence · v17'),
            ),
          ]),
          const SizedBox(height: 5),
          Text('Result: ${_text(discovery['status'])} · ${sources.length} source(s) examined · ${candidates.length} source-backed mention(s)',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
          if (_map(discovery['retrieval_diagnostics']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Book passages: ${_text(_map(discovery['retrieval_diagnostics'])['book_passages_examined'], '0')} · Retrieval mode: ${_text(_map(discovery['retrieval_diagnostics'])['book_text_mode'])}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF58717D))),
          ],
          if (discovery['status'] == 'partial_result_timeout') ...[
            const SizedBox(height: 9),
            const Text('Partial search: a time-limited stage could not finish. The source list may be reviewed, but no conclusion about available medications can be drawn from this attempt.',
              style: TextStyle(color: Color(0xFF945C23), height: 1.4)),
          ] else if (candidates.isEmpty) ...[
            const SizedBox(height: 9),
            const Text('No names from the current detector vocabulary were found in the examined passages. This does not prove that a treatment is absent from the books; do not infer a medicine or dose.',
              style: TextStyle(color: Color(0xFF627885), height: 1.4)),
          ],
          if (_map(_map(discovery['retrieval_diagnostics'])['stage_seconds']).isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text('Search timings (s): ${_map(_map(discovery['retrieval_diagnostics'])['stage_seconds'])}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF58717D)))),
          const SizedBox(height: 6),
          ExpansionTile(
            initiallyExpanded: false,
            tilePadding: EdgeInsets.zero,
            title: const Text('Open detailed drug mentions and source passages',
              style: TextStyle(fontWeight: FontWeight.w700, color: _teal)),
            subtitle: Text('${candidates.length} mentions · ${handbook.length} Plumb’s entries; not automatically selected',
              style: const TextStyle(fontSize: 11)),
            children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (handbook.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Plumb’s locations reviewed: ${handbook.length}. A name match can be a study, interaction or cross-reference; even a possible entry heading does not verify dosing.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF58717D), height: 1.4)),
          ],
          if (classOnly.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text('${classOnly.length} general drug-class mention(s) excluded — not specific medication names.',
              style: const TextStyle(color: Color(0xFF945C23), fontSize: 12, fontWeight: FontWeight.w700)),
            for (final row in classOnly)
              Padding(padding: const EdgeInsets.only(top: 3),
                child: Text('${_text(row['class_name'])} · ${_text(row['source_title'])}',
                  style: const TextStyle(color: Color(0xFF7D6A51), fontSize: 12))),
          ],
          for (final item in candidates) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Mentioned: ${_text(item['drug_name'])}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _ink))),
                  IconButton(
                    tooltip: 'Copy this drug and its evidence',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.content_copy_outlined, color: _teal),
                    onPressed: () => _copyEvidenceText(
                      'Drug source evidence',
                      _candidateCopyText(
                        item,
                        handbookByName[_text(item['drug_name'], '').toLowerCase()],
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('Source: ${_text(item['source_title'])} · ${_text(item['locator'])}',
                  style: const TextStyle(color: Color(0xFF496978), fontSize: 12)),
                const SizedBox(height: 8),
                Text('“${_text(item['exact_quote'])}”',
                  style: const TextStyle(height: 1.5, color: Color(0xFF2D4F5D))),
                const SizedBox(height: 8),
                const Text('Name in clinical literature only · Indication, suitability and dose NOT verified',
                  style: TextStyle(color: Color(0xFF945C23), fontSize: 12, fontWeight: FontWeight.w700)),
                if (item['population_notes'] is List)
                  for (final note in item['population_notes'] as List)
                    Text(note.toString(),
                      style: const TextStyle(color: Color(0xFF945C23), fontSize: 12)),
                if (item['negative_or_cautionary_context'] == true)
                  const Text('Caution: source phrase includes a negative/contraindication context.',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
                if (item['quality_warning'] == true)
                  const Text('Source text extraction may be unreliable; inspect the original page.',
                    style: TextStyle(color: Color(0xFF945C23), fontSize: 12)),
                if (handbookByName.containsKey(_text(item['drug_name'], '').toLowerCase())) ...[
                  const SizedBox(height: 7),
                  _handbookReference(handbookByName[_text(item['drug_name'], '').toLowerCase()]!),
                ],
                if (_text(item['url'], '').startsWith('https://'))
                  TextButton.icon(
                    onPressed: () => _openLink(_text(item['url'], '')),
                    icon: const Icon(Icons.open_in_new_outlined, size: 16),
                    label: const Text('Open source'),
                  ),
              ]),
            ),
          ],
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 15),
            ExpansionTile(
              initiallyExpanded: false,
              tilePadding: EdgeInsets.zero,
              title: Text('Review ${sources.length} source(s) searched',
                style: const TextStyle(fontWeight: FontWeight.w700, color: _teal)),
              children: [for (final row in sources)
                ListTile(
                  dense: true,
                  title: Text(_text(row['title']), style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${_text(row['type'])} · ${_text(row['case_applicability'])} · ${_text(row['locator'])}',
                    style: const TextStyle(fontSize: 11)),
                  trailing: _text(row['url'], '').startsWith('https://')
                      ? const Icon(Icons.open_in_new, size: 16) : null,
                  onTap: _text(row['url'], '').startsWith('https://')
                      ? () => _openLink(_text(row['url'], '')) : null,
                ),
              ],
            ),
          ],
          for (final warning in warnings)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(warning, style: const TextStyle(fontSize: 12, color: Color(0xFF945C23)))),
            ])],
          ),
        ],
      ],
    ));
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the link. Address copied.')),
      );
    }
  }

  Future<void> _copyPrescription(String label, Map<String, dynamic> option) async {
    final patient = _map(_plan?['patient']);
    final lines = _rows(option['lines']);
    if (lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No verified medication protocol to copy yet.')),
      );
      return;
    }
    final output = <String>[
      'ASSISTANT VET — $label',
      'DRAFT — Requires veterinarian approval',
      'Patient: ${_text(patient['name'])} · ${_text(patient['species'])} · ${_text(patient['weight_kg'])} kg',
      'Case ID: ${_text(widget.casePayload['case_id'])}',
      'Clinical status: ${_text(_map(_plan?['clinical_safety'])['status'])}',
      'Unverified clinical checks: ${_text(_map(_plan?['clinical_safety'])['missing_checks'])}',
      'Any red flags: ${_text(_map(_plan?['clinical_safety'])['red_flags'])}',
      '',
    ];
    for (final item in lines) {
      output.addAll([
        'Rx/: ${_text(item['rx_abbreviation'], _text(item['form']))} ${_text(item['ingredient'])} ${_text(item['product_name'], '')}',
        '(${_text(item['why'], 'Clinical rationale pending')})',
        'Dose: ${_text(item['dose_mg'])} mg (${_text(item['dose_mg_per_kg'])} mg/kg)',
        'Quantity per dose: ${_text(item['units_per_dose'])} ${_text(item['unit_kind'])}',
        'Route: ${_text(item['route'])}',
        'Frequency: ${_frequency(item['administrations_per_day'])}',
        'Duration: ${_durationLabel(item)}',
        'Packages needed: ${_text(item['packages_needed'])}',
        'Cost: ${_money(item['cost_toman'])}',
        'Reviewed by: ${_text(item['reviewer'], 'NOT REVIEWED')}, ${_text(item['reviewed_at'])}',
        ..._rows(item['evidence']).map((src) =>
          'Evidence: ${_text(src['title'])} — ${_text(src['locator'])}'),
        '',
      ]);
    }
    output.add('Indicative one-administration acquisition cost (NOT course): ${_money(option['total_toman'])}');
    output.add('CHECK: Contraindications, patient status, regulatory authorization, and actual product label.');
    await Clipboard.setData(ClipboardData(text: output.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prescription draft copied.')),
    );
  }


  Future<void> _previewPriceFromSite() async {
    if (_fetchingPrice) return;
    setState(() { _fetchingPrice = true; _priceMessage = null; });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('${AssistantVetApi.baseUrl}/prescription/prices/preview'),
      ).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'quote': {
        'source_id': _priceSource, 'url': _quoteUrl.text.trim(),
        'pack_ml': double.tryParse(_quotePackMl.text.trim()),
      }}));
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode != 200 || body is! Map) {
        throw FormatException(_text(_map(body)['detail'], 'Listing unavailable'));
      }
      final listing = _map(body);
      if (!mounted) return;
      if (_text(listing['status']) == 'source_page_price_preview_unverified') {
        _quoteAmount.text = _text(listing['price'], '');
        _quoteName.text = _text(listing['product_name'], '');
        setState(() {
          _priceCurrency = _text(listing['currency'], 'TOMAN');
          _confirmedProduct = false;
          _priceMessage = 'Price copied from site markup; check pack, stock and currency before recording.';
        });
      } else {
        setState(() => _priceMessage = _text(listing['warning'], 'No usable matching price.'));
      }
    } catch (error) {
      if (mounted) setState(() => _priceMessage = 'Source page could not be checked: $error');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _fetchingPrice = false);
    }
  }

  Future<void> _savePriceQuote() async {
    if (_savingQuote) return;
    setState(() { _savingQuote = true; _priceMessage = null; });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(
        Uri.parse('${AssistantVetApi.baseUrl}/prescription/prices/observe'),
      ).timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'quote': {
        'source_id': _priceSource,
        'url': _quoteUrl.text.trim(),
        'product_name': _quoteName.text.trim(),
        'brand': _quoteBrand.text.trim(),
        'pack_ml': double.tryParse(_quotePackMl.text.trim()),
        'strength_mg_per_ml': 10,
        'price': double.tryParse(_quoteAmount.text.trim().replaceAll(',', '')),
        'currency': _priceCurrency,
        'entered_by': _quoteClinician.text.trim(),
        'confirm_exact_product': _confirmedProduct,
        'preferred': _preferredBrand,
      }}));
      final response = await request.close().timeout(const Duration(seconds: 12));
      final body = await utf8.decoder.bind(response).join();
      final parsed = jsonDecode(body);
      if (response.statusCode != 200) {
        throw FormatException(_text(_map(parsed)['detail'], 'Price evidence rejected'));
      }
      if (!mounted) return;
      setState(() => _priceMessage =
          'Price recorded as a clinician-entered, UNVERIFIED listing. Confirm stock and page accuracy.');
      await _load();
    } catch (err) {
      if (mounted) setState(() => _priceMessage = 'Could not record price: $err');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _savingQuote = false);
    }
  }

  Widget _formularyReviewCard() {
    final review = _map(_plan?['formulary_review']);
    final options = _rows(review['entries']);
    final supportive = _rows(_plan?['supportive_care_review']);
    if (review.isEmpty || (options.isEmpty && supportive.isEmpty)) {
      return const SizedBox.shrink();
    }
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.fact_check_outlined, color: _teal), SizedBox(width: 8),
          Expanded(child: Text('Evidence-backed treatment options to REVIEW',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _ink))),
        ]),
        const SizedBox(height: 6),
        const Text('These are alternatives found in published references, not additional Rx lines. No drug here has an authorized patient-specific dose or automatic approval. A veterinarian must review the original source, patient and local product.',
          style: TextStyle(fontSize: 12, color: Color(0xFF586D79), height: 1.45)),
        for (final item in options) ...[
          const Divider(height: 20),
          Text('${_text(item['ingredient'])} · ${_text(item['status'])}',
            style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 3),
          Text(_text(item['why_consider']), style: const TextStyle(fontSize: 12, color: _ink)),
          const SizedBox(height: 3),
          Text('Safety: ${_text(item['important_caution'])}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF97501A))),
          Text('Not approved for this patient · No Rx dose generated',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF97501A))),
          if (_text(item['source_url'], '').startsWith('https://'))
            TextButton.icon(
              onPressed: () => _openLink(_text(item['source_url'])),
              icon: const Icon(Icons.open_in_new, size: 15),
              label: Text(_text(item['source_title'], 'Open original source')),
            ),
        ],
        for (final item in supportive) ...[
          const Divider(height: 20),
          Text(_text(item['title']),
            style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
          Text(_text(item['why']),
            style: const TextStyle(fontSize: 12, color: _ink)),
          Text('Status: ${_text(item['status'])} · Volume/rate NOT automatically prescribed',
            style: const TextStyle(fontSize: 11, color: Color(0xFF97501A))),
          if (_text(item['source_url'], '').startsWith('https://'))
            TextButton.icon(
              onPressed: () => _openLink(_text(item['source_url'])),
              icon: const Icon(Icons.open_in_new, size: 15),
              label: const Text('AAHA clinical guideline'),
            ),
        ],
      ],
    ));
  }

  Widget _clinicalSafetyCard() {
    final info = _map(_plan?['clinical_safety']);
    const names = <String, String>{
      'obstruction_ruled_out': 'GI obstruction or foreign body evaluated and excluded',
      'toxin_ruled_out': 'Toxin ingestion investigated and excluded',
      'hydration_assessed': 'Hydration, fluid needs and electrolytes assessed',
      'medications_reviewed': 'Existing medicines and interactions reviewed',
      'liver_status_reviewed': 'Hepatic conditions and precautions reviewed',
      'veterinarian_examined': 'Examination documented by treating veterinarian',
    };
    final done = names.keys.where((k) => _clinicianChecks[k] == true).length;
    final red = info['red_flags'] is List ? info['red_flags'] as List : [];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.health_and_safety_outlined, color: _teal), SizedBox(width: 8),
        Expanded(child: Text('Clinician safety review — before any real order',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink))),
      ]),
      const SizedBox(height: 7),
      const Text('These are clinical safety reminders — NOT login steps or requirements for viewing a draft. Check only what a veterinarian has actually verified. Checking boxes never signs or authorizes a prescription.',
        style: TextStyle(fontSize: 12, color: Color(0xFF586D79), height: 1.45)),
      if (red.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('POTENTIAL RED FLAGS: ${red.join('; ')}',
          style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
      ],
      const SizedBox(height: 5),
      Text('Status: ${_text(info['status'])} · Verified in this session: $done/${names.length}',
        style: const TextStyle(color: Color(0xFF945C23), fontSize: 12, fontWeight: FontWeight.w700)),
      ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        title: const Text('What are these checks? / Open clinician checklist',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _teal)),
        children: [
          for (final e in names.entries)
            CheckboxListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              title: Text(e.value, style: const TextStyle(fontSize: 13)),
              value: _clinicianChecks[e.key] ?? false,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (checked) => setState(() => _clinicianChecks[e.key] = checked == true),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _loading || _discovering ? null : _load,
            label: const Text('Update clinical review status'),
          ),
        ],
      ),
    ]));
  }


  Widget _researchCard() {
    final research = _research ?? <String, dynamic>{};
    final books = _map(research['books']);
    final papers = _map(research['papers']);
    final ai = _map(research['ai_reasoning']);
    final checkedBooks = _rows(books['books']);
    final screenedPapers = _rows(papers['papers']);
    final decisions = _rows(research['evidence_decisions']);
    final gaps = _rows(research['patient_gaps']);
    final aiItems = _map(ai['items']);
    if (_research == null) return const SizedBox.shrink();
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.science_outlined, color: _teal), SizedBox(width: 9),
        Expanded(child: Text('Evidence audit — source-by-source verification',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _ink))),
      ]),
      const SizedBox(height: 8),
      Text('Local books indexed: ${_text(books['books_checked'], '0')} · Books with sampled topic hits: ${_text(books['books_with_hits'], '0')} · Paper screening: ${_text(papers['status'])} · Retrieved paper records (unreviewed): ${screenedPapers.length}',
        style: const TextStyle(color: _teal, fontWeight: FontWeight.w700, height: 1.4)),
      const SizedBox(height: 5),
      const Text('An indexed match or article abstract is evidence to REVIEW, not automatically the correct treatment. The app does not claim that every page or article was fully appraised.',
        style: TextStyle(color: Color(0xFF916128), fontSize: 12, height: 1.4)),
      const SizedBox(height: 12),
      const Text('Why each found drug was / was not selected:',
        style: TextStyle(fontWeight: FontWeight.w800, color: _ink, fontSize: 13)),
      for (final d in decisions) Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Container(width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFF4F8F7),borderRadius: BorderRadius.circular(9)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
            Text('${_text(d['ingredient'])} · ${_text(d['status'])}',
              style: TextStyle(fontWeight: FontWeight.w800,
              color: _text(d['status']).contains('source_row') ? _teal : const Color(0xFF916128))),
            Text(_text(d['why']), style: const TextStyle(fontSize: 12, color: _ink, height: 1.35)),
            Text('Article keyword overlaps (not efficacy proof): ${_text(d['matched_paper_count'],'0')} · Source dose rows requiring review: ${_text(d['unverified_dose_row_count'],'0')}',
              style: const TextStyle(fontSize: 11,color: Color(0xFF58717D))),
          ]))),
      const SizedBox(height: 11),
      ExpansionTile(
        initiallyExpanded:false, tilePadding: EdgeInsets.zero,
        title: Text('Book-by-book checks · ${checkedBooks.length} indexed book(s)',
          style: const TextStyle(color:_teal,fontWeight:FontWeight.w700)),
        children:[for (final book in checkedBooks)
          ExpansionTile(
            initiallyExpanded:false, tilePadding:EdgeInsets.zero,
            title:Text(_text(book['title']),style:const TextStyle(fontSize:13,color:_ink,fontWeight:FontWeight.w700)),
            subtitle:Text('${_text(book['status'])} · ${_rows(book['sampled_hits']).length} sampled passages',
              style:const TextStyle(fontSize:11)),
            children:[for (final hit in _rows(book['sampled_hits'])) Padding(
              padding: const EdgeInsets.only(bottom:9),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('p. ${_text(hit['page_start'])} · ${_text(hit['source_id'])}',
                  style:const TextStyle(fontSize:11,color:_teal)),
                Text(_text(hit['passage']),style:const TextStyle(fontSize:12,height:1.4)),
                TextButton.icon(onPressed:()=>_copyEvidenceText('Book excerpt',
                  '${_text(book['title'])} · ${_text(hit['source_id'])}\n${_text(hit['passage'])}'),
                  icon:const Icon(Icons.copy,size:14),label:const Text('Copy evidence')),
              ])),
            ],
          ),
        ],
      ),
      ExpansionTile(
        initiallyExpanded:false, tilePadding:EdgeInsets.zero,
        title:Text('Independent paper screening · ${screenedPapers.length} result(s)',
          style:const TextStyle(color:_teal,fontWeight:FontWeight.w700)),
        subtitle:Text('Europe PMC: ${_text(papers['status'])} · abstracts/metadata only',
          style:const TextStyle(fontSize:11)),
        children:[for (final paper in screenedPapers)
          ListTile(
            contentPadding:EdgeInsets.zero, dense:true,
            title:Text(_text(paper['title']),style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
            subtitle:Text('${_text(paper['year'])} · ${_text(paper['reported_design'])} · ${_text(paper['v27_clinical_relevance'], _text(paper['relevance_status']))}\n${_text(paper['abstract_excerpt'])}',
              maxLines:5,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,height:1.3)),
            trailing: _text(paper['url'],'').startsWith('https://')
              ? const Icon(Icons.open_in_new,color:_teal,size:17) : null,
            onTap:_text(paper['url'],'').startsWith('https://')
              ? ()=>_openLink(_text(paper['url'],'')) : null,
          ),
        ],
      ),
      ExpansionTile(
        initiallyExpanded:false,tilePadding:EdgeInsets.zero,
        title:const Text('Local AI differential questions (not medication orders)',
          style:TextStyle(color:_teal,fontWeight:FontWeight.w700)),
        subtitle:Text('Status: ${_text(ai['status'])}',style:const TextStyle(fontSize:11)),
        children:[
          for (final key in const ['differential_questions','safety_concerns',
                                 'additional_clinical_data','research_conflicts'])
            if (aiItems[key] is List && (aiItems[key] as List).isNotEmpty) ...[
              Text(key.replaceAll('_',' ').toUpperCase(),
                style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800,color:_ink)),
              for (final answer in aiItems[key] as List)
                Padding(padding:const EdgeInsets.only(bottom:5),
                  child:Text('• $answer',style:const TextStyle(fontSize:12,height:1.4))),
            ],
          if (ai['status']!='ai_hypotheses_for_clinician_only')
            Text(_text(ai['note'],'Local model unavailable or disabled.'),
              style:const TextStyle(fontSize:12)),
          const Text('Never use an AI response as a drug dose or authorization.',
            style:TextStyle(color:Color(0xFF955E27),fontSize:12)),
        ],
      ),
      if (gaps.isNotEmpty) ExpansionTile(
        initiallyExpanded:false,tilePadding:EdgeInsets.zero,
        title:Text('Case information still needed (${gaps.length})',
          style:const TextStyle(color:_teal,fontWeight:FontWeight.w700)),
        children:[for (final gap in gaps)
          Padding(padding:const EdgeInsets.only(bottom:6),
            child:Text('• ${_text(gap['question'])}',
              style:const TextStyle(fontSize:12,color:_ink))),
        ],
      ),
    ]));
  }

  // Structured case-level reasoning without converting literature mentions to Rx.
  Widget _aiReasoningCard() {
    final ai = _map(_plan?['ai_clinical_review']);
    if (ai.isEmpty) return const SizedBox.shrink();
    final status = _text(ai['status'], 'not_run');
    final ok = status == 'ai_hypotheses_for_clinician_only';
    final items = _map(ai['items']);
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.psychology_alt_outlined : Icons.warning_amber_rounded,
              size: 24, color: ok ? _teal : const Color(0xFFB36B28)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Local AI · actual case analysis',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 4),
            Text('Model: ${_text(ai['model'], 'Unknown')} · $status',
                style: const TextStyle(fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
            if (ai['duration_s'] != null)
              Text('Generation: ${_text(ai['duration_s'])} s · ${_text(ai['tokens_per_second'], '—')} tokens/s',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF667D85))),
          ])),
        ]),
        const SizedBox(height: 9),
        if (!ok) ...[
          Text('Reasoning did not complete. Error: ${_text(ai['error_type'], status)} '
              '(HTTP ${_text(ai['http_status'], '—')}; limit ${_text(ai['timeout_setting_s'], '—')} s)',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9B5327))),
          const Text('The drug draft below is source-based, NOT an output approved by the model.',
              style: TextStyle(fontSize: 12, height: 1.45)),
        ],
        for (final key in const ['differential_questions','safety_concerns',
                                 'additional_clinical_data','research_conflicts'])
          if (items[key] is List && (items[key] as List).isNotEmpty) ...[
            Padding(padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(key.replaceAll('_',' ').toUpperCase(),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _ink))),
            for (final value in (items[key] as List))
              Padding(padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $value', style: const TextStyle(fontSize: 12, height: 1.45))),
          ],
        const SizedBox(height: 9),
        const Text('AI questions support clinical review. Dose, alternative choice and price must come from independently checked sources; veterinarian authorization is required.',
          style: TextStyle(fontSize: 11, color: Color(0xFF667D85), height: 1.4)),
      ],
    ));
  }

  Widget _clinicalPathwaysCard() {
    final info = _map(_plan?['clinical_pathways']);
    if (info.isEmpty) return const SizedBox.shrink();
    final actions = _rows(info['review_actions']);
    final alerts = _rows(info['case_alerts']);
    final unselected = _rows(info['discovered_drugs_not_prescribed']);
    final diagnoses = info['potential_differentials_to_examine'] is List
        ? info['potential_differentials_to_examine'] as List : [];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.account_tree_outlined, color: _teal),
        SizedBox(width: 9),
        Expanded(child: Text('Case-specific clinical decision paths',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink))),
      ]),
      const SizedBox(height: 7),
      Text('Detected case topic: ${_text(info['topic'])} · ${_text(info['review_summary'])}',
        style: const TextStyle(fontSize: 12, color: _teal, fontWeight: FontWeight.w700)),
      const SizedBox(height: 7),
      const Text('Clinical questions and actions below are NOT additional drug orders. A medicine enters a draft only with an indication-matched source/protocol.',
        style: TextStyle(fontSize: 12, color: Color(0xFF657A85), height: 1.4)),
      for (final a in alerts) Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Text('URGENT REVIEW: ${_text(a['message'])}',
          style: const TextStyle(color: Color(0xFFB42318), fontWeight: FontWeight.w700, fontSize: 12))),
      const SizedBox(height: 9),
      for (final action in actions) Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.radio_button_unchecked, size: 16, color: _teal),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_text(action['title']),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: _ink)),
            Text(_text(action['why']),
              style: const TextStyle(fontSize: 12, color: Color(0xFF526B78), height: 1.4)),
          ])),
        ])),
      if (diagnoses.isNotEmpty) ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Differentials to investigate (not diagnoses)',
          style: TextStyle(fontSize: 13, color: _teal, fontWeight: FontWeight.w700)),
        children: [for (final d in diagnoses)
          ListTile(dense: true, title: Text('• $d', style: const TextStyle(fontSize: 12)))],
      ),
      if (unselected.isNotEmpty) ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('${unselected.length} literature drug mention(s) withheld from Rx',
          style: const TextStyle(fontSize: 13, color: _teal, fontWeight: FontWeight.w700)),
        children: [for (final drug in unselected)
          ListTile(dense: true,
            title: Text(_text(drug['ingredient']),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(_text(drug['reason']),
              style: const TextStyle(fontSize: 11, height: 1.4)))],
      ),
      if (_rows(_map(_plan?['alternative'])['lines']).isEmpty)
        Text(_text(info['reason_for_missing_alternative']),
          style: const TextStyle(fontSize: 12, color: Color(0xFF945C23), height: 1.4)),
    ]));
  }

  Widget _caseAssessmentCard() {
    final info = _map(_plan?['case_review']);
    final reasons = info['reasons'] is List ? info['reasons'] as List : [];
    final selected = info['selected_ingredients'] is List ? info['selected_ingredients'] as List : [];
    final notSelected = info['not_selected_ingredients'] is List
        ? info['not_selected_ingredients'] as List : [];
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.fact_check_outlined, color: _teal), SizedBox(width: 8),
        Expanded(child: Text('Case assessment and missing information',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink))),
      ]),
      const SizedBox(height: 8),
      Text('Clinician-recorded complaint: ${_text(info['chief_complaint'])}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
      const SizedBox(height: 5),
      Text('Reviewed ${_text(info['sources_examined'], '0')} sources and ${_text(info['handbook_entries_examined'], '0')} drug-handbook matches.',
        style: const TextStyle(fontSize: 12, color: Color(0xFF58717D))),
      const SizedBox(height: 9),
      Text(selected.isNotEmpty
          ? 'Source-backed reference candidate: ${selected.join(', ')}'
          : 'No case-matched, source-backed dose could be proposed.',
        style: const TextStyle(color: _teal, fontWeight: FontWeight.w700)),
      if (notSelected.isNotEmpty) ...[
        const SizedBox(height: 5),
        Text('Other retrieved names (NOT prescribed): ${notSelected.join(', ')}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF945C23))),
      ],
      for (final note in reasons) ...[
        const SizedBox(height: 6),
        Text('• $note', style: const TextStyle(color: _ink, fontSize: 12, height: 1.45)),
      ],
      const SizedBox(height: 9),
      const Text('Clinical tasks to consider (NOT drug orders):',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: _ink)),
      for (final step in (info['clinician_next_steps'] is List
          ? info['clinician_next_steps'] as List : []))
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('• $step',
          style: const TextStyle(color: _ink, fontSize: 12, height: 1.4))),
      const SizedBox(height: 8),
      const Text('No AI-generated differential or study dose is accepted as a signed prescription. Check the original publications and the specific formulation.',
        style: TextStyle(color: Color(0xFF945C23), fontSize: 12, height: 1.45)),
    ]));
  }

  Widget _exchangeRateCard() {
    final rate = _map(_plan?['exchange_rate']);
    final articles = _rows(_plan?['literature_evidence']);
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Iranian exchange rate & research trace',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 8),
      Text(rate['status'] == 'current'
        ? 'USD (Tehran market) ≈ ${_money(rate['toman_per_usd'])} / USD'
        : 'Dollar conversion unavailable: ${_text(rate['status'])} — no invented rate.',
        style: const TextStyle(fontWeight: FontWeight.w700)),
      Text('NerkhAra (public API) · Updated: ${_text(rate['updated_at'])}',
        style: const TextStyle(fontSize: 11, color: Color(0xFF58717D))),
      TextButton(onPressed: () => _openLink('https://nerkhara.com/en/api/'),
        child: const Text('Open FX data source')),
      const Divider(),
      const Text('Scientific articles (context, not independently verified dosing)',
        style: TextStyle(fontWeight: FontWeight.w700, color: _ink)),
      if (articles.isEmpty) const Text('No article with a verified link in this retrieval.',
        style: TextStyle(fontSize: 12)),
      for (final a in articles)
        ListTile(dense: true, contentPadding: EdgeInsets.zero,
          title: Text(_text(a['title']), style: const TextStyle(fontSize: 12)),
          subtitle: const Text('Review methods, population and full text before using study doses.',
            style: TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.open_in_new, size: 17),
          onTap: () => _openLink(_text(a['url'], '')),
        ),
    ]));
  }

  Widget _enterIranPriceCard() => _card(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Iranian product-price evidence (optional)',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 5),
      const Text('Connect your VERIFIED product page: exact maropitant INJECTION 10 mg/mL only. '
        'The listed price is manually transcribed, not automatically verified. '
        'No alternative medicine is substituted by price alone.',
        style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF5B6E7C))),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _priceSource,
        decoration: const InputDecoration(labelText: 'Iranian supplier', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value:'salardam', child: Text('Salardam')),
          DropdownMenuItem(value:'pharmacy4pet', child: Text('Pharmacy4Pet')),
          DropdownMenuItem(value:'cheetavet', child: Text('Cheetavet')),
          DropdownMenuItem(value:'vetkala', child: Text('Vetkala')),
          DropdownMenuItem(value:'pillix', child: Text('Pillix')),
          DropdownMenuItem(value:'ttac', child: Text('TTAC')),
        ],
        onChanged: (value) => setState(() => _priceSource = value ?? 'salardam'),
      ),
      const SizedBox(height: 9),
      TextField(controller: _quoteUrl, decoration: const InputDecoration(
        labelText: 'Exact product HTTPS URL (not homepage)', border: OutlineInputBorder())),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: _fetchingPrice ? null : _previewPriceFromSite,
        icon: const Icon(Icons.public, size: 18),
        label: Text(_fetchingPrice ? 'Reading site…' : 'Try live price from product page (JSON-LD)')),
      const SizedBox(height: 9),
      TextField(controller: _quoteName, decoration: const InputDecoration(
        labelText: 'Product name (must identify Maropitant/Cerenia)', border: OutlineInputBorder())),
      const SizedBox(height: 9),
      TextField(controller: _quoteBrand, decoration: const InputDecoration(
        labelText: 'Brand / manufacturer', border: OutlineInputBorder())),
      const SizedBox(height: 9),
      Row(children: [
        Expanded(child: TextField(controller: _quotePackMl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Vial size (mL)', border: OutlineInputBorder()))),
        const SizedBox(width: 10),
        Expanded(child: TextField(controller: _quoteAmount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Price of pack', border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 9),
      DropdownButtonFormField<String>(value: _priceCurrency,
        decoration: const InputDecoration(labelText: 'Currency', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value:'TOMAN', child: Text('Toman')),
          DropdownMenuItem(value:'IRR', child: Text('Rial (÷10)')),
        ],
        onChanged: (v) => setState(() => _priceCurrency = v ?? 'TOMAN')),
      const SizedBox(height: 9),
      TextField(controller: _quoteClinician, decoration: const InputDecoration(
        labelText: 'Recorded by (veterinarian)', border: OutlineInputBorder())),
      CheckboxListTile(value: _preferredBrand,
        title: const Text('Preferred source product/brand (not a clinical approval)',
          style: TextStyle(fontSize: 12)),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => setState(() => _preferredBrand = v == true)),
      CheckboxListTile(value: _confirmedProduct,
        title: const Text('I checked the link, ingredient, injection 10 mg/mL, vial size and price.',
          style: TextStyle(fontSize: 12)),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => setState(() => _confirmedProduct = v == true)),
      FilledButton.icon(
        onPressed: _savingQuote ? null : _savePriceQuote,
        icon: const Icon(Icons.save_outlined),
        label: Text(_savingQuote ? 'Recording…' : 'Record source-linked price & refresh')),
      if (_priceMessage != null) Text(_priceMessage!,
        style: const TextStyle(fontSize: 12, color: Color(0xFF85591C))),
    ]));

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(20)}) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDEAE8)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }

  Widget _prescriptionCard(String label, Map<String, dynamic> option, IconData icon) {
    final lines = _rows(option['lines']);
    final status = _text(option['status']);
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: _teal),
          const SizedBox(width: 9),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: _ink))),
          IconButton(
            tooltip: 'Copy draft',
            onPressed: lines.isEmpty ? null : () => _copyPrescription(label, option),
            icon: const Icon(Icons.content_copy_outlined),
          ),
        ]),
        const Divider(height: 24),
        const Text('REFERENCE DRAFT — Not a signed/authorized prescription',
          style: TextStyle(color: Color(0xFF9C5D1E), fontWeight: FontWeight.w700, fontSize: 11)),
        const SizedBox(height: 8),
        if (lines.isEmpty) ...[
          if (label.contains('Economic Choice') &&
              _rows(_map(_plan?['first_choice'])['lines']).isNotEmpty) ...[
            const Text('Clinical reference used as the price-comparison baseline — NOT an established cheaper prescription.',
              style: TextStyle(color: Color(0xFF945C23), fontSize: 12, fontWeight: FontWeight.w700, height: 1.45)),
            const SizedBox(height: 8),
            Text('Reference treatment: ${_text(_rows(_map(_plan?['first_choice'])['lines']).first['ingredient'])} · ${_text(_rows(_map(_plan?['first_choice'])['lines']).first['dose_mg'])} mg / administration',
              style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
          ],
          const Icon(Icons.fact_check_outlined, size: 29, color: Color(0xFF8FA1A5)),
          const SizedBox(height: 12),
          Text(_text(option['detail'], 'No suitable alternative or independently price-supported regimen yet.'),
            style: TextStyle(height: 1.5, color: Color(0xFF435E6C))),
          const SizedBox(height: 10),
          const Text('The system will not invent a drug, dose, route or duration from a loosely related article.',
            style: TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF71818A))),
        ] else ...[
          ...lines.asMap().entries.map((entry) {
            final number = entry.key + 1;
            final line = entry.value;
            final evidence = _rows(line['evidence']);
            final price = _map(line['price_evidence']);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8F7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Rx/ $number. ${_text(line['rx_abbreviation'], _text(line['form']))} ${_text(line['ingredient'])} ${_text(line['brand'], '')}',
                    style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)),
                if (_text(line['why'], '').isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('(${_text(line['why'])})', style: const TextStyle(
                    color: Color(0xFF16803B), fontWeight: FontWeight.w700, height: 1.45)),
                ],
                const SizedBox(height: 6),
                Text('Reference calculation: ${_text(line['dose_mg'])} mg (${_text(line['dose_mg_per_kg'])} mg/kg) · ${_text(line['units_per_dose'])} ${_text(line['unit_kind'])} / dose',
                    style: const TextStyle(height: 1.4)),
                Text('${_text(line['route'])} · ${_frequency(line['administrations_per_day'])} · Duration: ${_durationLabel(line)}',
                    style: const TextStyle(height: 1.4)),
                Text('Estimated pack acquisition (${_text(line['cost_scope'], 'one administration')}) : ${_text(line['packages_needed'])} pack(s) · ${_money(line['cost_toman'])}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Price status: ${_text(price['status'])}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF657A85))),
                if (price['official_toman'] is num)
                  Text('Official TTAC reference: ${_money(price['official_toman'])} per pack',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF657A85))),
                if (line['cost_usd_approx'] is num)
                  Text('Approx. USD: \$${_text(line['cost_usd_approx'])}',
                    style: const TextStyle(fontSize: 12, color: _teal)),
                if (_text(price['source_id'], '').isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _openLink(_text(price['url'], '')),
                    icon: const Icon(Icons.local_pharmacy_outlined, size: 15),
                    label: Text('Iranian seller: ${_text(price['source_id'])} · '
                      '${_money(price['price_per_pack_toman'])}/pack · '
                      '${_text(price['observed_at'])}',
                      style: const TextStyle(fontSize: 11)),
                  ),
                const SizedBox(height: 7),
                Text('Protocol review: ${_text(line['reviewer'], 'PENDING')} · ${_text(line['dose_context'], 'Clinician review required')}',
                  style: const TextStyle(fontSize: 12)),
                for (final source in evidence)
                  _text(source['url'], '').startsWith('https://')
                      ? Align(alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _openLink(_text(source['url'], '')),
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: Text('Evidence: ${_text(source['title'])} · ${_text(source['locator'])}',
                              style: const TextStyle(fontSize: 12)),
                          ))
                      : Text('Evidence: ${_text(source['title'])} · ${_text(source['locator'])}',
                          style: const TextStyle(fontSize: 12, color: _teal)),
              ]),
            );
          }),
          const SizedBox(height: 6),
          Text('Indicative acquisition (${_text(option['cost_scope'], 'scope unknown')}): ${_money(option['total_toman'])}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _ink)),
          Text('Pricing status: $status', style: const TextStyle(color: Color(0xFF6B818B), fontSize: 12)),
        ],
      ],
    ));
  }

  Widget _clinicalContext() {
    final analysis = _map(widget.analysisResult['analysis']);
    final items = _rows(analysis['treatment_lines']);
    if (items.isEmpty) return const SizedBox.shrink();
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Previous AI treatment considerations (not prescriptions)',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _ink)),
      const SizedBox(height: 7),
      for (final item in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('• ${_text(item['line'])} — ${_text(item['details'])}',
            style: const TextStyle(color: Color(0xFF58717D), height: 1.4)),
        ),
    ]));
  }


  Future<void> _auditIranSuppliers() async {
    if (_checkingConnectors) return;
    setState(() => _checkingConnectors = true);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(
        '${AssistantVetApi.baseUrl}/prescription/source-connectors/audit'));
      final response = await req.close().timeout(const Duration(seconds: 18));
      final parsed = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode != 200 || parsed is! Map) {
        throw const FormatException('Vendor connectivity audit unavailable');
      }
      if (mounted) setState(() => _connectorAudit = _map(parsed));
    } catch (error) {
      if (mounted) setState(() => _connectorAudit = {'status':'unavailable',
        'note':'Supplier connectivity could not be checked: $error'});
    } finally {
      client.close(force:true);
      if (mounted) setState(() => _checkingConnectors=false);
    }
  }

  Future<void> _previewGeneralPrice() async {
    if (_genericPreviewing) return;
    setState(() { _genericPreviewing=true; _genericMessage=null; });
    final client = HttpClient()..connectionTimeout=const Duration(seconds:8);
    try {
      final req = await client.postUrl(Uri.parse(
        '${AssistantVetApi.baseUrl}/prescription/prices/preview-v26'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'quote':{
        'source_id':_priceSource,'url':_genericUrl.text.trim(),
        'ingredient':_genericIngredient.text.trim(),
        'strength_mg_per_unit':double.tryParse(_genericStrength.text.trim()),
        'pack_units':double.tryParse(_genericPack.text.trim()),
        'unit_kind':_genericUnit,
      }}));
      final resp = await req.close().timeout(const Duration(seconds:15));
      final data = _map(jsonDecode(await utf8.decoder.bind(resp).join()));
      if (resp.statusCode!=200) throw FormatException(_text(data['detail']));
      if (!mounted) return;
      if (data['status']=='source_page_price_preview_not_verified') {
        _genericPrice.text = _text(data['price_toman'],'');
        _genericName.text = _text(data['product_name'],'');
        setState(() { _priceCurrency='TOMAN'; _genericProductChecked=false;
          _genericMessage='Price read from structured product markup. Verify current stock, license, label and final price before saving.'; });
      } else {
        setState(() => _genericMessage=_text(data['warning'], 'No reliable exact-SKU price available.'));
      }
    } catch (error) {
      if (mounted) setState(() => _genericMessage='Cannot preview product: $error');
    } finally {
      client.close(force:true);
      if (mounted) setState(() => _genericPreviewing=false);
    }
  }

  Future<void> _saveGeneralPrice() async {
    if (_genericSaving) return;
    setState(() { _genericSaving=true; _genericMessage=null; });
    final client = HttpClient()..connectionTimeout=const Duration(seconds:8);
    try {
      final req = await client.postUrl(Uri.parse(
        '${AssistantVetApi.baseUrl}/prescription/prices/products-v26'));
      req.headers.contentType=ContentType.json;
      req.write(jsonEncode({'quote':{
        'source_id':_priceSource,'url':_genericUrl.text.trim(),
        'ingredient':_genericIngredient.text.trim(),
        'active_ingredient_on_label':_genericIngredient.text.trim(),
        'product_name':_genericName.text.trim(),
        'brand':_genericBrand.text.trim(),
        'form':_genericForm,'unit_kind':_genericUnit,
        'strength_mg_per_unit':double.tryParse(_genericStrength.text.trim()),
        'pack_units':double.tryParse(_genericPack.text.trim()),
        'price':double.tryParse(_genericPrice.text.trim().replaceAll(',','')),
        'currency':_priceCurrency,'entered_by':_genericRecordedBy.text.trim(),
        'in_stock':_genericProductChecked,
        'confirm_exact_product':_genericProductChecked,
        'preferred':_genericPreferred,
      }}));
      final resp = await req.close().timeout(const Duration(seconds:15));
      final result = _map(jsonDecode(await utf8.decoder.bind(resp).join()));
      if (resp.statusCode!=200) throw FormatException(_text(result['detail'],'Quote rejected'));
      if (!mounted) return;
      setState(()=>_genericMessage='Source-linked manual price saved with timestamp as NOT independently verified.');
      await _load();
    } catch (error) {
      if (mounted) setState(()=>_genericMessage='Could not save source-linked price: $error');
    } finally {
      client.close(force:true);
      if (mounted) setState(()=>_genericSaving=false);
    }
  }

  Widget _generalPriceCard() {
    final priceRows = _rows(_plan?['price_comparison_audit']);
    return _card(child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Iranian medicine price: exact product, any ingredient',
        style:TextStyle(fontWeight:FontWeight.w800,fontSize:15,color:_ink)),
      const SizedBox(height:7),
      const Text('Enter a REAL supplier product URL and an observed pack price. For non-public APIs, automatic pricing may be unavailable; never invent a price. Currency uses Iranian toman (IRR ÷ 10).',
        style:TextStyle(fontSize:12,color:Color(0xFF6B818B),height:1.45)),
      const SizedBox(height:10),
      DropdownButtonFormField<String>(value:_priceSource,
        decoration:const InputDecoration(labelText:'Iranian price source',border:OutlineInputBorder()),
        items:const [
          DropdownMenuItem(value:'salardam',child:Text('Salardam')),
          DropdownMenuItem(value:'cheetavet',child:Text('Cheetavet')),
          DropdownMenuItem(value:'pharmacy4pet',child:Text('Pharmacy4Pet')),
          DropdownMenuItem(value:'vetkala',child:Text('Vetkala')),
          DropdownMenuItem(value:'pillix',child:Text('Pillix')),
          DropdownMenuItem(value:'ttac',child:Text('TTAC official manual lookup')),
        ], onChanged:(v)=>setState(()=>_priceSource=v??'salardam')),
      const SizedBox(height:10),
      TextField(controller:_genericUrl, decoration:const InputDecoration(
        labelText:'Exact HTTPS product page (not homepage)',border:OutlineInputBorder())),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:TextField(controller:_genericIngredient,decoration:const InputDecoration(
          labelText:'Generic ingredient (INN)',border:OutlineInputBorder()))),
        const SizedBox(width:8),
        Expanded(child:TextField(controller:_genericName,decoration:const InputDecoration(
          labelText:'Product name on label',border:OutlineInputBorder()))),
      ]),
      const SizedBox(height:10),
      TextField(controller:_genericBrand,decoration:const InputDecoration(
        labelText:'Brand / manufacturer',border:OutlineInputBorder())),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:DropdownButtonFormField<String>(value:_genericForm,
          decoration:const InputDecoration(labelText:'Dosage form',border:OutlineInputBorder()),
          items:const [
            DropdownMenuItem(value:'injection',child:Text('Inj. / Amp.')),
            DropdownMenuItem(value:'tablet',child:Text('Tab.')),
            DropdownMenuItem(value:'capsule',child:Text('Cap.')),
            DropdownMenuItem(value:'syrup',child:Text('Syrp.')),
            DropdownMenuItem(value:'suspension',child:Text('Susp.')),
            DropdownMenuItem(value:'drop',child:Text('Drop.')),
            DropdownMenuItem(value:'serum',child:Text('Serum / IV fluid')),
          ],onChanged:(v)=>setState(()=>_genericForm=v??'injection'))),
        const SizedBox(width:8),
        Expanded(child:DropdownButtonFormField<String>(value:_genericUnit,
          decoration:const InputDecoration(labelText:'Unit',border:OutlineInputBorder()),
          items:const [
            DropdownMenuItem(value:'ml',child:Text('mL')),
            DropdownMenuItem(value:'tablet',child:Text('tablet')),
            DropdownMenuItem(value:'capsule',child:Text('capsule')),
            DropdownMenuItem(value:'ampoule',child:Text('ampoule')),
            DropdownMenuItem(value:'vial',child:Text('vial')),
            DropdownMenuItem(value:'drop',child:Text('drop')),
            DropdownMenuItem(value:'sachet',child:Text('sachet')),
          ],onChanged:(v)=>setState(()=>_genericUnit=v??'ml'))),
      ]),
      const SizedBox(height:10),
      Row(children:[
        Expanded(child:TextField(controller:_genericStrength,
          keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Strength (mg/unit)',border:OutlineInputBorder()))),
        const SizedBox(width:8),
        Expanded(child:TextField(controller:_genericPack,
          keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Units in purchasable pack',border:OutlineInputBorder()))),
      ]),
      const SizedBox(height:10),
      OutlinedButton.icon(onPressed:_genericPreviewing?null:_previewGeneralPrice,
        icon:const Icon(Icons.cloud_download_outlined,size:18),
        label:Text(_genericPreviewing?'Inspecting JSON-LD…':'Try reading exact SKU price from page')),
      const SizedBox(height:8),
      Row(children:[
        Expanded(child:TextField(controller:_genericPrice,
          keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Whole pack price',border:OutlineInputBorder()))),
        const SizedBox(width:8),
        Expanded(child:DropdownButtonFormField<String>(value:_priceCurrency,
          decoration:const InputDecoration(labelText:'Currency',border:OutlineInputBorder()),
          items:const [DropdownMenuItem(value:'TOMAN',child:Text('Toman')),
                       DropdownMenuItem(value:'IRR',child:Text('Rial ÷ 10'))],
          onChanged:(v)=>setState(()=>_priceCurrency=v??'TOMAN'))),
      ]),
      const SizedBox(height:10),
      TextField(controller:_genericRecordedBy,decoration:const InputDecoration(
        labelText:'Recorded by (veterinarian)',border:OutlineInputBorder())),
      CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,
        value:_genericPreferred,
        title:const Text('Reference/preferred supplier for price comparison (not a treatment endorsement)',
          style:TextStyle(fontSize:12)),
        onChanged:(v)=>setState(()=>_genericPreferred=v==true)),
      CheckboxListTile(dense:true,contentPadding:EdgeInsets.zero,
        value:_genericProductChecked,
        title:const Text('I checked this exact product, strength, package, label, availability and price.',
          style:TextStyle(fontSize:12)),
        onChanged:(v)=>setState(()=>_genericProductChecked=v==true)),
      FilledButton.icon(onPressed:_genericSaving?null:_saveGeneralPrice,
        icon:const Icon(Icons.save_outlined),
        label:Text(_genericSaving?'Saving…':'Save observed price (NOT independently verified)')),
      if (_genericMessage!=null)
        Padding(padding:const EdgeInsets.only(top:10),
          child:Text(_genericMessage!,style:const TextStyle(fontSize:12,color:Color(0xFF945C23)))),
      for (final item in priceRows)
        Text('${_text(item['ingredient'])} · ${_text(item['status'])}',
          style:const TextStyle(fontSize:11,color:_teal)),
    ]));
  }

  Widget _supplierAuditCard() {
    final result = _connectorAudit ?? <String,dynamic>{};
    return _card(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Iranian supplier connectivity (NOT a verified price API)',
        style:TextStyle(fontWeight:FontWeight.w800,fontSize:14,color:_ink)),
      const SizedBox(height:7),
      OutlinedButton.icon(onPressed:_checkingConnectors?null:_auditIranSuppliers,
        icon:const Icon(Icons.health_and_safety_outlined,size:18),
        label:Text(_checkingConnectors?'Checking 6 source sites…':'Check each Iranian site now')),
      if (_connectorAudit!=null) ...[
        Text('Checked: ${_text(result['checked_at'])} · ${_text(result['status'])}',
          style:const TextStyle(fontSize:11,color:_teal)),
        for (final entry in _rows(result['sources']))
          ListTile(dense:true,contentPadding:EdgeInsets.zero,
            title:Text('${_text(entry['name'])} · ${_text(entry['status'])}',
              style:const TextStyle(fontSize:12,fontWeight:FontWeight.w700)),
            subtitle:Text('HTTP ${_text(entry['http_status'])} · Product-price API not verified',
              style:const TextStyle(fontSize:11)),
          ),
        Text(_text(result['note']),style:const TextStyle(fontSize:11)),
      ],
    ]));
  }

  Widget _autoPriceOverviewCard() {
    final data = _map(_plan?['automatic_prices']);
    final rows = _rows(data['by_drug']);
    final amount = _text(data['offers_count'], '0');
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.travel_explore_outlined, color: _teal),
          SizedBox(width: 9),
          Expanded(child: Text('Automatic Iranian pharmacy price-check audit',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink))),
        ]),
        const SizedBox(height: 6),
        Text('Automatic check complete · $amount exact SKU offer(s) · ${_text(data['checked_at'])}',
          style: const TextStyle(fontSize: 12, color: _teal)),
        const SizedBox(height: 6),
        const Text('No product names or links to enter. Supplier-listed prices only; '
          'price may differ at checkout. No matching listing means price unknown, never estimated.',
          style: TextStyle(fontSize: 12, height: 1.45, color: Color(0xFF657A85))),
        const SizedBox(height: 9),
        if (rows.isEmpty)
          const Text('No exact dosage-form/strength product could be price-checked for this case.',
            style: TextStyle(fontSize: 12)),
        for (final d in rows)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('${_text(d['ingredient'])} — ${_text(d['status'])}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text('${_text(d['offer_count'], '0')} matching offer(s)',
              style: const TextStyle(fontSize: 11)),
            children: [
              for (final offer in _rows(d['matching_offers']))
                ListTile(dense: true,
                  title: Text('${_text(offer['product_name'])} · ${_money(offer['price_toman'])} / pack',
                    style: const TextStyle(fontSize: 12)),
                  subtitle: Text('${_text(offer['source_id'])} · ${_text(offer['pack_units'])} '
                    '${_text(offer['unit_kind'])} · ${_text(offer['observed_at'])}',
                    style: const TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.open_in_new, size: 17),
                  onTap: () => _openLink(_text(offer['url'], '')),
                ),
              for (final supplier in _rows(d['sources']))
                ListTile(dense: true,
                  title: Text('${_text(supplier['source_id'])}: ${_text(supplier['status'])}',
                    style: const TextStyle(fontSize: 12)),
                  subtitle: Text('${_text(supplier['offer_count'], '0')} offers · '
                    '${_text(supplier['product_pages_scanned'], '0')} product pages read',
                    style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        const SizedBox(height: 6),
        const Text('TTAC and Pillix are not treated as verified public price APIs. '
          'Missing supplier access is recorded as missing data, not a zero-cost medicine.',
          style: TextStyle(fontSize: 11, color: Color(0xFF657A85))),
      ],
    ));
  }

  Widget _priceSources() {
    final plan = _plan ?? <String, dynamic>{};
    final links = _rows(plan['price_sources']);
    return _card(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.price_check_outlined, color: _teal),
          SizedBox(width: 8),
          Expanded(child: Text('Iranian medicine-price sources',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink))),
        ]),
        const SizedBox(height: 9),
        const Text('Where a product page exposes exact structured price data, Try live price can prefill an unverified quote. Otherwise record the product price manually. Never infer SKU strength or market stock.',
          style: TextStyle(color: Color(0xFF526B78), height: 1.5)),
        const SizedBox(height: 12),
        for (final item in links)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_text(item['name']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            subtitle: Text(_text(item['type']), style: const TextStyle(fontSize: 11)),
            trailing: const Icon(Icons.open_in_new, size: 18, color: _teal),
            onTap: () => _openLink(_text(item['url'], '')),
          ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final patient = _map(widget.casePayload['patient']);
    final plan = _plan ?? <String, dynamic>{};
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F7),
      appBar: AppBar(
        title: const Text('Prescription Workspace · AI Connected', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: (_loading || _discovering) ? null : (_plan == null ? _discoverEvidence : _load),
            icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && _plan == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 36),
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  ])))
              : SelectionArea(child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1300),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Patient: ${_text(patient['name'])} · ${_text(patient['species'])} · ${_text(patient['weight_kg'])} kg',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _ink)),
                      const SizedBox(height: 12),
                      _discoveryCard(),
                      if (_plan == null) ...[
                        const SizedBox(height: 14),
                        _card(child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.info_outline, color: _teal), SizedBox(width: 12),
                          Expanded(child: Text('Start with “Search & analyze” above. The program will retrieve evidence, assess patient details and then show three plan drafts below. No default drug is prescribed when this page opens.',
                            style: TextStyle(color: _ink, height: 1.5))),
                        ])),
                      ] else ...[
                        const SizedBox(height: 16),
                        _caseAssessmentCard(),
                        const SizedBox(height: 16),
                        _aiReasoningCard(),
                        const SizedBox(height: 16),
                        _clinicalPathwaysCard(),
                        const SizedBox(height: 16),
                        _formularyReviewCard(),
                        const SizedBox(height: 16),
                        _clinicalContext(),
                        const SizedBox(height: 16),
                        const SizedBox(height: 2),
                        const Text('Three treatment plan options — clinician review',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _ink)),
                        const SizedBox(height: 10),
                      LayoutBuilder(builder: (context, constraints) {
                        final first = _prescriptionCard('1 · First Choice — clinical reference',
                          _map(plan['first_choice']), Icons.workspace_premium_outlined);
                        final alternative = _prescriptionCard('2 · Alternative Choice — if source-verified',
                          _map(plan['alternative']), Icons.alt_route_outlined);
                        final economic = _prescriptionCard('3 · Economic Choice — auto supplier comparison',
                          _map(plan['economic']), Icons.savings_outlined);
                        return constraints.maxWidth >= 1190
                            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Expanded(child: first), const SizedBox(width: 12),
                                Expanded(child: alternative), const SizedBox(width: 12),
                                Expanded(child: economic),
                              ])
                            : Column(children: [first, const SizedBox(height: 12),
                                alternative, const SizedBox(height: 12), economic]);
                      }),
                      const SizedBox(height: 16),
                      _clinicalSafetyCard(),
                      const SizedBox(height: 16),
                      _researchCard(),
                      const SizedBox(height: 16),
                      _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Prescription and price verification status',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: _ink)),
                        const SizedBox(height: 6),
                        Text(_text(plan['status']), style: const TextStyle(color: _teal)),
                        const SizedBox(height: 5),
                        Text('Indicative savings (one administration, if two source-linked prices): ${_money(_map(plan['economic'])['indicative_savings_toman'])}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        const Text('Savings are NOT verified until exact product/stock/prices are checked. A cheaper listing is not proof of clinical or regulatory equivalence.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF667D85))),
                      ])),
                      ],
                      if (_plan != null) ...[
                        const SizedBox(height: 16),
                        _exchangeRateCard(),
                        const SizedBox(height: 16),
                        _autoPriceOverviewCard(),
                      ],
                      const SizedBox(height: 18),
                    ]),
                  )),
                )),
    );
  }
}
