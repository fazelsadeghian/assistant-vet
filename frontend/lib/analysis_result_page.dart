// Assistant Vet analysis UI v3 — source links, citation transparency and readable excerpts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prescription_workspace_page.dart';

class AnalysisResultPage extends StatelessWidget {
  final Map<String, dynamic> result;
  final Map<String, dynamic> casePayload;

  const AnalysisResultPage({
    super.key,
    required this.result,
    required this.casePayload,
  });

  Map<String, dynamic> get _analysis => _map(result['analysis']);
  Map<String, dynamic> get _performance => _map(result['performance']);
  Map<String, dynamic> get _systemAudit => _map(result['system_audit']);
  Map<String, dynamic> get _auditTrail => _map(result['audit_trail']);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'Case Analysis',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MediaQuery.sizeOf(context).width < 670
                ? IconButton(
                    tooltip: 'Copy full report',
                    icon: const Icon(Icons.copy_all_outlined),
                    onPressed: () => _copyReport(context),
                  )
                : TextButton.icon(
                    onPressed: () => _copyReport(context),
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Copy full report'),
                  ),
          ),
          if (MediaQuery.sizeOf(context).width >= 760)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Center(child: _engineBadge()),
            ),
        ],
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 720 ? 14 : 28),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 1360),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summary(),
                  const SizedBox(height: 18),
                  _statusStrip(),
                  const SizedBox(height: 12),
                  _copyGuide(context),
                  const SizedBox(height: 10),
                  _citationGuide(),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 900;
                      final left = _clinicalAnalysis();
                      final right = _management();

                      if (narrow) {
                        return Column(
                          children: [
                            left,
                            const SizedBox(height: 18),
                            right,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 7, child: left),
                          const SizedBox(width: 18),
                          Expanded(flex: 5, child: right),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _literature(context),
                  const SizedBox(height: 18),
                  _textbook(context),
                  const SizedBox(height: 18),
                  _prescriptionWorkspaceCard(context),
                  const SizedBox(height: 18),
                  _technicalFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _prescriptionWorkspaceCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF075E70), Color(0xFF0B9289)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        return Wrap(
          spacing: 16,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: constraints.maxWidth < 780 ? constraints.maxWidth : constraints.maxWidth - 270,
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Prescription Workspace · v6',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19)),
                SizedBox(height: 6),
                Text('Two drafts: clinically preferred and evidence-verified economic alternative. Includes Iranian price-source links and transparent cost calculation.',
                  style: TextStyle(color: Color(0xFFE1F6F2), height: 1.45, fontSize: 13)),
              ]),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF075E70),
                padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => PrescriptionWorkspacePage(
                  casePayload: casePayload, analysisResult: result),
              )),
              icon: const Icon(Icons.medication_outlined),
              label: const Text('Open prescriptions'),
            ),
          ],
        );
      }),
    );
  }

  Widget _copyGuide(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCAE7E2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.content_copy_outlined,
              color: Color(0xFF087B76), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Text is selectable. Use Ctrl+C, a section copy icon, or Copy full report.',
              style: TextStyle(
                color: Color(0xFF1B575A),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            const Text(
              'EVIDENCE + COPY · v3',
              style: TextStyle(
                color: Color(0xFF087B76),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _citationGuide() {
    final strict = _systemAudit['strict_diagnosis_source_topic_filter_enabled'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: strict ? const Color(0xFFF0F8F6) : const Color(0xFFFFF6E8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: strict ? const Color(0xFFCCE5DD) : const Color(0xFFF3DEC0),
        ),
      ),
      child: Row(
        children: [
          Icon(strict ? Icons.fact_check_outlined : Icons.info_outline,
              size: 17,
              color: strict ? const Color(0xFF137F6B) : const Color(0xFF946019)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              strict
                  ? 'Citation topic matching is active. A relevant source is not proof of a patient-specific diagnosis.'
                  : 'Legacy saved analysis: citation relevance was not checked with the new filter. Generate a fresh analysis for updated references.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF435E6C)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _engineBadge() {
    final model = (_systemAudit['ai_model'] ?? _auditTrail['ai_model'])?.toString() ?? 'local AI';
    final mode = (_systemAudit['analysis_mode'] ?? _auditTrail['analysis_mode'])?.toString() ?? 'fast';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        '$model • $mode',
        style: const TextStyle(
          color: Color(0xFF087B76),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _summary() {
    final patient = _map(casePayload['patient']);
    final clinical = _map(casePayload['clinical']);
    final name = _text(patient['name'], fallback: 'Unnamed patient');
    final species = _text(patient['species'], fallback: 'patient');
    final breed = _text(patient['breed']);
    final chief = _text(clinical['chief_complaint']);

    final mostLikely = _mapList(_analysis['most_probable_diagnoses']);
    final leading = mostLikely.isNotEmpty
        ? _text(mostLikely.first['diagnosis'])
        : _leadingDifferential();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF075E70), Color(0xFF0AA7A0)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 31,
            backgroundColor: Colors.white,
            child: Icon(Icons.pets, color: Color(0xFF087B76), size: 30),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name • ${_capitalize(species)}${breed.isEmpty ? '' : ' • $breed'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (chief.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    chief,
                    style: const TextStyle(color: Color(0xFFE0F5F3)),
                  ),
                ],
                const SizedBox(height: 15),
                Text(
                  leading.isEmpty
                      ? 'Integrated clinical analysis complete'
                      : 'Leading working diagnosis: $leading',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusStrip() {
    final gate = _text(_analysis['clinical_gate_status'], fallback: 'unknown');
    final totalSeconds = _number(_performance['total_seconds']);
    final conflicts = _mapList(result['conflicts']).length;
    final sourceCount = _map(_analysis['grounding'])['source_count'];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _statusPill(
          icon: gate == 'pass' ? Icons.verified_outlined : Icons.warning_amber_rounded,
          label: 'Clinical gate: ${_capitalize(gate)}',
          positive: gate == 'pass',
        ),
        _statusPill(
          icon: Icons.balance_outlined,
          label: '$conflicts conflict${conflicts == 1 ? '' : 's'} detected',
          positive: conflicts == 0,
        ),
        if (sourceCount != null)
          _statusPill(
            icon: Icons.library_books_outlined,
            label: '$sourceCount retrieved references',
            positive: true,
          ),
        if (totalSeconds != null)
          _statusPill(
            icon: Icons.timer_outlined,
            label: '${totalSeconds.toStringAsFixed(1)} s',
            positive: true,
          ),
      ],
    );
  }

  Widget _statusPill({
    required IconData icon,
    required String label,
    required bool positive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: positive ? const Color(0xFFE7F6F1) : const Color(0xFFFFF1E5),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 17,
            color: positive ? const Color(0xFF087B76) : const Color(0xFFB86524),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: positive ? const Color(0xFF087B76) : const Color(0xFF9A5520),
            ),
          ),
        ],
      ),
    );
  }

  Widget _clinicalAnalysis() {
    return Column(
      children: [
        _mostLikelyCard(),
        const SizedBox(height: 16),
        _differentialsCard(),
        const SizedBox(height: 16),
        _nextTestsCard(),
      ],
    );
  }

  Widget _management() {
    return Column(
      children: [
        _treatmentCard(),
        const SizedBox(height: 16),
        _problemListCard(),
        const SizedBox(height: 16),
        _missingDataCard(),
        const SizedBox(height: 16),
        _safetyCard(),
        const SizedBox(height: 16),
        _modalityCard(),
        const SizedBox(height: 16),
        _conflictsCard(),
      ],
    );
  }

  Widget _mostLikelyCard() {
    final items = _mapList(_analysis['most_probable_diagnoses']);

    if (items.isEmpty) {
      return _emptyCard(
        'Most likely diagnosis',
        Icons.fact_check_outlined,
        'No single diagnosis was promoted as most probable.',
      );
    }

    return _panel(
      title: 'Most likely diagnosis',
      icon: Icons.fact_check_outlined,
      child: Column(
        children: items.map((item) {
          final diagnosis = _text(item['diagnosis'], fallback: 'Unspecified');
          final confidence = _text(item['confidence']);
          final rationale = _text(item['rationale']);
          final facts = _stringList(item['verified_case_facts']);
          final sources = _stringList(item['source_ids']);

          return _diagnosisBlock(
            diagnosis: diagnosis,
            confidence: confidence,
            rationale: rationale,
            facts: facts,
            sources: sources,
            citationStatus: _text(item['citation_status']),
          );
        }).toList(),
      ),
    );
  }

  Widget _differentialsCard() {
    final items = _mapList(_analysis['ranked_differentials']);

    if (items.isEmpty) {
      return _emptyCard(
        'Ranked differentials',
        Icons.account_tree_outlined,
        'No usable etiologic differential list was returned.',
      );
    }

    return _panel(
      title: 'Ranked differentials',
      icon: Icons.account_tree_outlined,
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final diagnosis = _text(item['diagnosis'], fallback: 'Unspecified');
          final confidence = _text(item['confidence']);
          final uncertain = _stringList(item['against_or_uncertain']);
          final facts = _stringList(item['verified_supporting_case_facts']);
          final sources = _stringList(item['source_ids']);

          return Container(
            margin: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 11),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFB),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: const Color(0xFFE2F4F2),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Color(0xFF087B76),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        diagnosis,
                        style: const TextStyle(
                          color: Color(0xFF102F46),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (confidence.isNotEmpty) _confidenceChip(confidence),
                  ],
                ),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 11),
                  _smallLabel('Case support'),
                  ...facts.take(2).map(_factLine),
                  if (facts.length > 2)
                    _ExpandableFactLines(
                      lines: facts.skip(2).map(_humanizeFact).toList(),
                    ),
                ],
                if (uncertain.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _smallLabel('Against / uncertain'),
                  ...uncertain.take(4).map(_mutedBullet),
                ],
                if (sources.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  _sourceLine(sources),
                ],
                _citationStatusLabel(_text(item['citation_status']), sources),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _modalityCard() {
    final modalities = _map(_analysis['modality_interpretations']);

    if (modalities.isEmpty) {
      return _emptyCard(
        'Modality interpretations',
        Icons.grid_view_rounded,
        'No modality-specific interpretation was returned.',
      );
    }

    return _panel(
      title: 'Modality interpretations',
      icon: Icons.grid_view_rounded,
      child: Column(
        children: modalities.entries.map((entry) {
          final lines = _stringList(entry.value);
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _prettyKey(entry.key),
                  style: const TextStyle(
                    color: Color(0xFF102F46),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                ...lines.map(_bulletLine),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _conflictsCard() {
    final conflicts = _mapList(result['conflicts']);
    final warnings = _mapList(_map(result['data_quality'])['warnings']);

    if (conflicts.isEmpty && warnings.isEmpty) {
      return _emptyCard(
        'Conflicts & data quality',
        Icons.balance_outlined,
        'No explicit contradiction or data-quality warning was returned.',
      );
    }

    return _panel(
      title: 'Conflicts & data quality',
      icon: Icons.balance_outlined,
      child: Column(
        children: [
          ...conflicts.map((item) {
            final title = _text(item['title'], fallback: 'Conflict');
            final interpretation = _text(item['interpretation']);
            final next = _text(item['next_check']);
            final severity = _text(item['severity']);
            return _alertBlock(
              title: title,
              body: [interpretation, next].where((e) => e.isNotEmpty).join('\n'),
              severity: severity,
            );
          }),
          ...warnings.map((item) {
            return _alertBlock(
              title: _text(item['source'], fallback: 'Data quality'),
              body: [
                _text(item['message']),
                _text(item['recommended_action']),
              ].where((e) => e.isNotEmpty).join('\n'),
              severity: _text(item['severity']),
            );
          }),
        ],
      ),
    );
  }

  Widget _nextTestsCard() {
    final items = _mapList(_analysis['next_best_tests']);

    if (items.isEmpty) {
      return _emptyCard(
        'Next diagnostic steps',
        Icons.alt_route,
        'No next test was returned.',
      );
    }

    return _panel(
      title: 'Next diagnostic steps',
      icon: Icons.alt_route,
      child: Column(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final sources = _stringList(item['source_ids']);
          return Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${index + 1}. ${_text(item['test'], fallback: 'Diagnostic test')}',
                  style: const TextStyle(
                    color: Color(0xFF102F46),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                finalText(_text(item['rationale'])),
                if (sources.isNotEmpty) _sourceLine(sources),
                _citationStatusLabel(_text(item['citation_status']), sources,
                    subject: 'diagnostic test'),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _treatmentCard() {
    final items = _mapList(_analysis['treatment_lines']);
    final verification = _map(_analysis['treatment_verification']);

    return _panel(
      title: 'Treatment considerations',
      icon: Icons.medical_services_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _text(
                verification['message'],
                fallback:
                    'Decision support only. Final drug choice, dose and contraindication checks remain the veterinarian’s responsibility.',
              ),
              style: const TextStyle(
                color: Color(0xFF7E5A22),
                height: 1.45,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Text(
              'No treatment line was released by the safety gate.',
              style: TextStyle(color: Color(0xFF71818A)),
            )
          else
            ...items.map((item) {
              final status = _text(item['status']);
              final sources = _stringList(item['source_ids']);
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFB),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _text(item['line'], fallback: 'Treatment consideration'),
                      style: const TextStyle(
                        color: Color(0xFF102F46),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    finalText(_text(item['details'])),
                    if (status.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        _prettyKey(status),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: status.contains('withheld')
                              ? const Color(0xFFB43C3C)
                              : const Color(0xFF8A6A27),
                        ),
                      ),
                    ],
                    if (sources.isNotEmpty) _sourceLine(sources),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _problemListCard() {
    final items = _stringList(_analysis['problem_list']);
    return _simpleListCard(
      'Problem list',
      Icons.format_list_bulleted,
      items,
      emptyMessage: 'No problem list returned.',
    );
  }

  Widget _missingDataCard() {
    final items = _stringList(_analysis['missing_data']);
    final uncertainty = _text(_analysis['uncertainty']);

    return _panel(
      title: 'Missing data & uncertainty',
      icon: Icons.query_stats_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isEmpty)
            const Text(
              'No major missing-data item was listed.',
              style: TextStyle(color: Color(0xFF71818A)),
            )
          else
            ...items.map(_bulletLine),
          if (uncertainty.isNotEmpty) ...[
            const Divider(height: 24),
            _smallLabel('Current uncertainty'),
            finalText(uncertainty),
          ],
        ],
      ),
    );
  }

  Widget _safetyCard() {
    final redFlags = _stringList(_analysis['red_flags']);
    final platelet = _map(_analysis['platelet_status']);
    final ua = _map(_analysis['urinalysis_status']);

    return _panel(
      title: 'Safety checks',
      icon: Icons.health_and_safety_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniStatus(
            'Red flags',
            redFlags.isEmpty ? 'None generated by the deterministic rule layer.' : redFlags.join(' • '),
            redFlags.isEmpty,
          ),
          if (platelet.isNotEmpty) ...[
            const SizedBox(height: 10),
            _miniStatus(
              'Platelet reliability',
              _text(platelet['reason'], fallback: _text(platelet['status'])),
              platelet['true_thrombocytopenia_confirmed'] != false,
            ),
          ],
          if (ua.isNotEmpty) ...[
            const SizedBox(height: 10),
            _miniStatus(
              'Urinalysis',
              _text(ua['status'], fallback: 'Unknown'),
              ua['status'] != 'not_provided',
            ),
          ],
        ],
      ),
    );
  }

  Widget _literature(BuildContext context) {
    final articles = _mapList(result['evidence']);

    return _panel(
      title: 'Current literature retrieved for this case',
      icon: Icons.article_outlined,
      child: articles.isEmpty
          ? const Text(
              'No articles were returned. External search requires access to PubMed/Europe PMC; saved reports are not refreshed automatically.',
              style: TextStyle(color: Color(0xFF71818A)),
            )
          : Column(
              children: articles.map((article) {
                final title = _text(article['title'], fallback: 'Untitled article');
                final authors = article['authors'] is List
                    ? (article['authors'] as List).join(', ')
                    : _text(article['authors']);
                final year = _text(article['year']);
                final doi = _text(article['doi']);
                final pmid = _text(article['pmid']);
                final abstract = _stripHtml(_text(article['abstract']));
                final articleUrl = _articleUrl(article);
                final applicability = _text(article['case_applicability']);
                final applicabilityNotes = _stringList(article['applicability_notes']);
                final studyDesign = _text(article['study_design_hint']);

                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 11),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFB),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFE2F4F2),
                            child: Icon(Icons.menu_book, color: Color(0xFF087B76)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          color: Color(0xFF102F46),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Copy this article',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.content_copy_outlined,
                                        size: 17,
                                      ),
                                      onPressed: () => _copyText(
                                        context,
                                        _clipboardFormat(article),
                                        'Article copied',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  [authors, year.isEmpty ? '' : year]
                                      .where((e) => e.isNotEmpty)
                                      .join(' • '),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF71818A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (applicability.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: applicability == 'context_only'
                                ? const Color(0xFFFFF4E5)
                                : const Color(0xFFEAF7F6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                applicability == 'context_only'
                                    ? 'Context only — not used to support this case'
                                    : 'Potentially applicable — claims not independently verified',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: applicability == 'context_only'
                                      ? const Color(0xFF925D14)
                                      : const Color(0xFF087B76),
                                ),
                              ),
                              if (studyDesign.isNotEmpty)
                                Text('Study type (automated hint): $studyDesign',
                                    style: const TextStyle(fontSize: 11)),
                              ...applicabilityNotes.map((note) => Text(
                                '• $note',
                                style: const TextStyle(fontSize: 11, height: 1.35),
                              )),
                            ],
                          ),
                        ),
                      ],
                      if (abstract.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _ExpandableExcerpt(
                          text: abstract,
                          previewLines: 5,
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (articleUrl != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _openSourceUrl(context, articleUrl),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open article in browser'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF087B76),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        )
                      else
                        const Text(
                          'No verified article URL or identifier was provided.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF71818A)),
                        ),
                      if (doi.isNotEmpty || pmid.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          [
                            if (pmid.isNotEmpty) 'PMID $pmid',
                            if (doi.isNotEmpty) 'DOI $doi',
                          ].join('   •   '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF087B76),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _textbook(BuildContext context) {
    final hits = _mapList(result['knowledge_hits']);
    final review = _map(result['book_evidence_audit']);
    final screened = review.isNotEmpty;
    final excluded = _mapList(review['excluded_examples']);
    final directCount = review['direct_candidate_count'] ?? 0;
    final contextCount = review['context_only_count'] ?? 0;
    final excludedCount = review['excluded_count'] ?? 0;

    return _panel(
      title: 'Textbook sources — clinical relevance review',
      icon: Icons.library_books_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (screened) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$directCount topic-aligned  •  $contextCount context-only  •  $excludedCount excluded',
                    style: const TextStyle(fontWeight: FontWeight.w800,
                        color: Color(0xFF105E65), fontSize: 12),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Automated relevance screening, not independent clinical or dosing verification. Only topic-aligned excerpts enter the citation pool.',
                    style: TextStyle(fontSize: 11, height: 1.4,
                        color: Color(0xFF53717A)),
                  ),
                  if (excluded.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: const Text('Show excluded examples',
                          style: TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      children: excluded.map((row) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• ${_text(row['title'], fallback: 'Textbook')} — ${_text(row['chapter'])} (${_text(row['reason'])})',
                          style: const TextStyle(fontSize: 11,
                              color: Color(0xFF607782)),
                        ),
                      )).toList(),
                    ),
                ],
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Saved legacy analysis: textbook relevance was not screened with v0.4.4.',
                style: TextStyle(color: Color(0xFF99631F), fontSize: 12),
              ),
            ),
          if (hits.isEmpty)
            const Text(
              'No sufficiently relevant textbook excerpts were retained. This is preferable to showing unrelated chapters as clinical evidence.',
              style: TextStyle(color: Color(0xFF71818A)),
            )
          else Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Excerpts are shown as extracted from the books; some passages may contain text-recognition artifacts.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5F7580),
                      height: 1.45,
                    ),
                  ),
                ),
                ...hits.map((hit) {
                  final title = _text(hit['title'], fallback: 'Textbook');
                  final chapter = _text(hit['chapter']);
                  final section = _text(hit['section']);
                  final page = hit['printed_page_start'] ?? hit['page_start'];
                  final snippet = _text(hit['snippet']);
                  final readableSnippet = _readableExcerpt(snippet);
                  final noisy = _possiblyNoisyExcerpt(snippet) ||
                      hit['book_excerpt_quality_warning'] == true;
                  final applicability = _text(hit['book_applicability']);
                  final notes = _stringList(hit['book_applicability_notes']);
                  final direct = applicability == 'direct_candidate';

                  return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 11),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFB),
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFF102F46),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy this textbook excerpt',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.content_copy_outlined,
                                size: 17),
                            onPressed: () => _copyText(
                              context,
                              _clipboardFormat(hit),
                              'Textbook excerpt copied',
                            ),
                          ),
                        ],
                      ),
                      if (applicability.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 7),
                          decoration: BoxDecoration(
                            color: direct
                                ? const Color(0xFFEAF7F6)
                                : const Color(0xFFFFF4E5),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                direct
                                    ? 'Topic-aligned candidate — clinical claim not verified'
                                    : 'Context only — not used to substantiate this case',
                                style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w800,
                                  color: direct
                                      ? const Color(0xFF087B76)
                                      : const Color(0xFF99631F),
                                ),
                              ),
                              ...notes.map((note) => Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text('• $note', style: const TextStyle(
                                    fontSize: 11, height: 1.3)),
                              )),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 5),
                      Text(
                        [
                          chapter,
                          section,
                          if (page != null) 'page $page',
                        ].where((e) => e.toString().trim().isNotEmpty).join(' • '),
                        style: const TextStyle(
                          color: Color(0xFF71818A),
                          fontSize: 11,
                        ),
                      ),
                      if (noisy) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Extracted table / OCR text: verify the original book page before citing.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF99631F),
                          ),
                        ),
                      ],
                      if (readableSnippet.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        _ExpandableExcerpt(text: readableSnippet),
                      ],
                    ],
                  ),
                );
                }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _technicalFooter() {
    final version = _text(_systemAudit['engine_version']);
    final model = _text(_systemAudit['ai_model'] ?? _auditTrail['ai_model']);
    final retry = _map(_performance['ollama'])['automatic_recovery_retry'];
    final valid = _map(_performance['ollama'])['model_output_valid'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4F4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 8,
        children: [
          if (version.isNotEmpty) Text('Engine: $version'),
          if (model.isNotEmpty) Text('Model: $model'),
          if (valid != null) Text('Structured output valid: $valid'),
          if (retry != null) Text('Automatic retry: $retry'),
          Text('Case ID: ${_text(result['case_id'], fallback: 'unknown')}'),
        ].map((widget) {
          return DefaultTextStyle(
            style: const TextStyle(
              color: Color(0xFF667983),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            child: widget,
          );
        }).toList(),
      ),
    );
  }

  Widget _diagnosisBlock({
    required String diagnosis,
    required String confidence,
    required String rationale,
    required List<String> facts,
    required List<String> sources,
    required String citationStatus,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  diagnosis,
                  style: const TextStyle(
                    color: Color(0xFF102F46),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
              if (confidence.isNotEmpty) _confidenceChip(confidence),
            ],
          ),
          if (rationale.isNotEmpty) finalText(rationale),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 10),
            _smallLabel('Verified patient facts'),
            ...facts.take(3).map(_factLine),
            if (facts.length > 3)
              _ExpandableFactLines(
                lines: facts.skip(3).map(_humanizeFact).toList(),
              ),
          ],
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 9),
            _sourceLine(sources),
          ],
          _citationStatusLabel(citationStatus, sources),
        ],
      ),
    );
  }

  Widget _confidenceChip(String confidence) {
    final lower = confidence.toLowerCase();
    final high = lower.contains('high');
    final moderate = lower.contains('moderate');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: high
            ? const Color(0xFFD9F1E9)
            : moderate
                ? const Color(0xFFFFF0D8)
                : const Color(0xFFEFF2F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _capitalize(confidence),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: high
              ? const Color(0xFF087B76)
              : moderate
                  ? const Color(0xFF9A6217)
                  : const Color(0xFF71818A),
        ),
      ),
    );
  }

  Widget _alertBlock({
    required String title,
    required String body,
    required String severity,
  }) {
    final high = severity.toLowerCase() == 'high';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: high ? const Color(0xFFFFECEC) : const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: high ? const Color(0xFFA33A3A) : const Color(0xFF8A641F),
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFF435E6C),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStatus(String title, String body, bool positive) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: positive ? const Color(0xFFEAF7F6) : const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF102F46),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF435E6C),
              height: 1.4,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _simpleListCard(
    String title,
    IconData icon,
    List<String> items, {
    required String emptyMessage,
  }) {
    return _panel(
      title: title,
      icon: icon,
      child: items.isEmpty
          ? Text(
              emptyMessage,
              style: const TextStyle(color: Color(0xFF71818A)),
            )
          : Column(children: items.map(_bulletLine).toList()),
    );
  }

  Widget _emptyCard(String title, IconData icon, String message) {
    return _panel(
      title: title,
      icon: icon,
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFF71818A), height: 1.45),
      ),
    );
  }

  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4ECEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0AA7A0)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF102F46),
                  ),
                ),
              ),
              Builder(
                builder: (buttonContext) => Tooltip(
                  message: 'Copy $title',
                  child: IconButton(
                    icon: const Icon(Icons.content_copy_rounded, size: 18),
                    color: const Color(0xFF087B76),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _copyText(
                      buttonContext,
                      _sectionText(title),
                      '$title copied',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _bulletLine(String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: CircleAvatar(
              radius: 3,
              backgroundColor: Color(0xFF0AA7A0),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _humanizeFact(value),
              style: const TextStyle(
                color: Color(0xFF435E6C),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _factLine(String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '• ${_humanizeFact(value)}',
        style: const TextStyle(
          color: Color(0xFF435E6C),
          height: 1.4,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _mutedBullet(String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '• $value',
        style: const TextStyle(
          color: Color(0xFF71818A),
          height: 1.4,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget finalText(String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        _humanizeFact(value),
        style: const TextStyle(
          color: Color(0xFF435E6C),
          height: 1.45,
        ),
      ),
    );
  }

  Widget _smallLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF71818A),
        fontWeight: FontWeight.w800,
        fontSize: 10,
        letterSpacing: .4,
      ),
    );
  }

  Widget _citationStatusLabel(String status, List<String> sources,
      {String subject = 'diagnosis'}) {
    final strict = _systemAudit['strict_diagnosis_source_topic_filter_enabled'] == true;
    if (!strict) {
      return const Padding(
        padding: EdgeInsets.only(top: 7),
        child: Text('Legacy citation status — not rechecked',
          style: TextStyle(color: Color(0xFF99631F), fontSize: 11)),
      );
    }
    final matched = status == 'topic_matched_not_claim_verified';
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Text(
        matched && sources.isNotEmpty
            ? 'Topical source match only — patient-specific claim not verified'
            : 'No topic-matched supporting reference for this $subject',
        style: TextStyle(
          fontSize: 11,
          color: matched && sources.isNotEmpty
              ? const Color(0xFF53717A)
              : const Color(0xFF99631F),
        ),
      ),
    );
  }

  Map<String, dynamic> _sourceRecord(String id) {
    for (final source in _mapList(result['source_context'])) {
      if (_text(source['source_id']) == id) return source;
    }
    return <String, dynamic>{};
  }

  String _sourceLabel(String id, Map<String, dynamic> record) {
    final title = _text(record['title']);
    if (title.isEmpty) return id;
    final page = record['printed_page_start'] ?? record['pdf_page_start'];
    final suffix = page == null ? '' : ' · p.$page';
    final summary = title.length > 44 ? '${title.substring(0, 44)}…' : title;
    return '$summary$suffix';
  }

  Widget _sourceLine(List<String> sources) {
    return Builder(builder: (context) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 7,
          runSpacing: 5,
          children: [
            const Text('References:', style: TextStyle(
              fontSize: 11, color: Color(0xFF607A84),
              fontWeight: FontWeight.w700,
            )),
            for (final id in sources) Builder(builder: (context) {
              final record = _sourceRecord(id);
              final articleUrl = _articleUrl(record);
              return Tooltip(
                message: articleUrl != null
                    ? 'Open article in browser'
                    : record.isNotEmpty
                        ? 'View source details and extracted excerpt'
                        : 'Source ID only — details unavailable',
                child: ActionChip(
                  avatar: Icon(articleUrl != null ? Icons.open_in_new
                      : Icons.menu_book_outlined, size: 14,
                      color: const Color(0xFF087B76)),
                  label: Text(_sourceLabel(id, record),
                    style: const TextStyle(fontSize: 10)),
                  backgroundColor: const Color(0xFFEAF7F6),
                  side: const BorderSide(color: Color(0xFFCEE7E5)),
                  onPressed: () {
                    if (articleUrl != null) {
                      _openSourceUrl(context, articleUrl);
                    } else if (record.isNotEmpty) {
                      _showBookSource(context, id, record);
                    } else {
                      _copyText(context, id, 'Source ID copied');
                    }
                  },
                ),
              );
            }),
          ],
        ),
      );
    });
  }

  String? _articleUrl(Map<String, dynamic> article) {
    final url = _text(article['url']);
    if (url.isNotEmpty) {
      final parsed = Uri.tryParse(url);
      const trustedHosts = {
        'pubmed.ncbi.nlm.nih.gov', 'pmc.ncbi.nlm.nih.gov',
        'www.ncbi.nlm.nih.gov', 'europepmc.org', 'www.europepmc.org',
        'doi.org', 'dx.doi.org',
      };
      if (parsed != null && parsed.scheme == 'https'
          && trustedHosts.contains(parsed.host.toLowerCase())) return url;
    }
    final pmid = _text(article['pmid']);
    if (RegExp(r'^\d{1,12}$').hasMatch(pmid)) {
      return 'https://pubmed.ncbi.nlm.nih.gov/$pmid/';
    }
    final pmcid = _text(article['pmcid']);
    if (RegExp(r'^PMC\d+$', caseSensitive: false).hasMatch(pmcid)) {
      return 'https://pmc.ncbi.nlm.nih.gov/articles/${pmcid.toUpperCase()}/';
    }
    final doi = _text(article['doi']);
    if (RegExp(r'^10\.\d{4,9}/\S+$').hasMatch(doi)) {
      return 'https://doi.org/${Uri.encodeComponent(doi)}';
    }
    return null;
  }

  Future<void> _openSourceUrl(BuildContext context, String url) async {
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [url],
            mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url],
            mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [url],
            mode: ProcessStartMode.detached);
      } else {
        throw const FileSystemException('Unsupported platform');
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open the browser: $error'),
      ));
      await _copyText(context, url, 'Article URL copied instead');
    }
  }

  void _showBookSource(
      BuildContext context, String id, Map<String, dynamic> record) {
    final title = _text(record['title'], fallback: 'Textbook reference');
    final chapter = _text(record['chapter']);
    final section = _text(record['section']);
    final page = record['printed_page_start'] ?? record['pdf_page_start'];
    final excerpt = _readableExcerpt(_text(record['snippet']));
    showDialog<void>(context: context, builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text([chapter, section, if (page != null) 'page $page']
                  .where((e) => e.trim().isNotEmpty).join(' • ')),
              const SizedBox(height: 10),
              const Text('Local textbook excerpt — no verified web link. '
                  'Confirm wording and page in the original book.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF99631F))),
              const SizedBox(height: 12),
              SelectableText(excerpt.isEmpty ? 'No excerpt supplied.' : excerpt),
            ],
          )),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy source'),
            onPressed: () => _copyText(context,
                _clipboardFormat(record).isEmpty ? id : _clipboardFormat(record),
                'Source copied'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close')),
        ],
      );
    });
  }

  // Presentation-only whitespace cleanup.  The raw extracted text is kept
  // untouched in the source record and full clipboard export.
  String _readableExcerpt(String raw) => raw
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _possiblyNoisyExcerpt(String raw) {
    final markers = RegExp(r'\[[A-Za-z]{2,5}\]').allMatches(raw).length;
    final digitGroups = RegExp(r'\b\d+(?:[.,]\d+)?\b').allMatches(raw).length;
    return markers >= 3 || (digitGroups >= 12 && raw.length < 700);
  }

  // Clipboard export deliberately uses the structured API response rather
  // than scraping visible widgets. Collapsed excerpts and facts are not lost.
  Future<void> _copyText(
    BuildContext context,
    String content,
    String confirmation,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: content));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(confirmation),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copy failed. Select the text and press Ctrl+C.'),
        ),
      );
    }
  }

  Future<void> _copyReport(BuildContext context) => _copyText(
        context,
        _fullReportText(),
        'Full analysis copied to clipboard',
      );

  String _fullReportText() {
    final patient = _map(casePayload['patient']);
    final name = _text(patient['name'], fallback: 'Unnamed patient');
    final output = <String>[
      'ASSISTANT VET — CASE ANALYSIS',
      'Patient: $name',
      'Case ID: ${_text(result['case_id'], fallback: 'unknown')}',
      'Engine: ${_text(_systemAudit['engine_version'])}',
      'Model: ${_text(_systemAudit['ai_model'] ?? _auditTrail['ai_model'])}',
      '',
      'ANALYSIS STATUS',
      _clipboardFormat({
        'clinical_gate': _analysis['clinical_gate_status'],
        'conflict_count': _mapList(result['conflicts']).length,
        'grounded_sources': _map(_analysis['grounding'])['source_count'],
        'elapsed_seconds': _performance['total_seconds'],
        'structured_output_valid': _map(_performance['ollama'])['model_output_valid'],
        'automatic_retry': _map(_performance['ollama'])['automatic_recovery_retry'],
      }),
      '',
      'SUBMITTED CASE DATA',
      _clipboardFormat(casePayload),
      '',
      for (final title in _exportTitles) ...[
        _sectionText(title),
        '',
      ],
    ];
    return output.join('\n').trim();
  }

  static const List<String> _exportTitles = [
    'Most likely diagnosis',
    'Ranked differentials',
    'Treatment considerations',
    'Problem list',
    'Missing data & uncertainty',
    'Safety checks',
    'Modality interpretations',
    'Conflicts & data quality',
    'Next diagnostic steps',
    'Current literature retrieved for this case',
    'Textbook evidence',
  ];

  String _sectionText(String title) {
    dynamic source;
    switch (title) {
      case 'Most likely diagnosis':
        source = _analysis['most_probable_diagnoses'];
        break;
      case 'Ranked differentials':
        source = _analysis['ranked_differentials'];
        break;
      case 'Modality interpretations':
        source = _analysis['modality_interpretations'];
        break;
      case 'Conflicts & data quality':
        source = {
          'conflicts': result['conflicts'],
          'warnings': _map(result['data_quality'])['warnings'],
        };
        break;
      case 'Next diagnostic steps':
        source = _analysis['next_best_tests'];
        break;
      case 'Treatment considerations':
        source = {
          'verification': _analysis['treatment_verification'],
          'treatment_lines': _analysis['treatment_lines'],
        };
        break;
      case 'Problem list':
        source = _analysis['problem_list'];
        break;
      case 'Missing data & uncertainty':
        source = {
          'missing_data': _analysis['missing_data'],
          'uncertainty': _analysis['uncertainty'],
        };
        break;
      case 'Safety checks':
        source = {
          'red_flags': _analysis['red_flags'],
          'platelet_status': _analysis['platelet_status'],
          'urinalysis_status': _analysis['urinalysis_status'],
        };
        break;
      case 'Current literature retrieved for this case':
        source = result['evidence'];
        break;
      case 'Textbook evidence':
        source = result['knowledge_hits'];
        break;
      default:
        source = {};
    }
    final formatted = _clipboardFormat(source).trim();
    return '$title\n${formatted.isEmpty ? 'No data returned.' : formatted}';
  }

  String _clipboardFormat(dynamic value, [int indent = 0]) {
    final padding = ' ' * indent;
    if (value == null) return '';
    if (value is Map) {
      final lines = <String>[];
      for (final entry in value.entries) {
        final data = entry.value;
        if (data == null || (data is String && data.trim().isEmpty)) continue;
        if (data is List && data.isEmpty) continue;
        if (data is Map && data.isEmpty) continue;
        final key = _prettyKey(entry.key.toString());
        if (data is Map || data is List) {
          final detail = _clipboardFormat(data, indent + 2);
          if (detail.isNotEmpty) lines.add('$padding$key:\n$detail');
        } else {
          final valueText = entry.key.toString().toLowerCase() == 'abstract'
              ? _stripHtml(data.toString())
              : data.toString().trim();
          lines.add('$padding$key: $valueText');
        }
      }
      return lines.join('\n');
    }
    if (value is List) {
      final lines = <String>[];
      for (final entry in value) {
        if (entry == null) continue;
        if (entry is Map || entry is List) {
          final detail = _clipboardFormat(entry, indent + 2);
          if (detail.isNotEmpty) lines.add('$padding-\n$detail');
        } else {
          final text = entry.toString().trim();
          if (text.isNotEmpty) lines.add('$padding• $text');
        }
      }
      return lines.join('\n');
    }
    return '$padding${value.toString().trim()}';
  }

  String _leadingDifferential() {
    final items = _mapList(_analysis['ranked_differentials']);
    if (items.isEmpty) return '';
    return _text(items.first['diagnosis']);
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .where((item) => item != null && item.toString().trim().isNotEmpty)
        .map((item) => item.toString().trim())
        .toList();
  }

  String _text(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _prettyKey(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(_capitalize)
        .join(' ');
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _humanizeFact(String value) {
    return value
        .replaceAll('case.patient.', 'Patient ')
        .replaceAll('case.clinical.', '')
        .replaceAll('case.cbc.', 'CBC ')
        .replaceAll('case.biochemistry.', 'Biochemistry ')
        .replaceAll('case.blood_smear.', 'Blood smear ')
        .replaceAll('_', ' ');
  }

  String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}


/// The full source excerpt is always available; the preview keeps long and
/// OCR-noisy book passages from overwhelming the analysis page.
class _ExpandableExcerpt extends StatefulWidget {
  final String text;
  final int previewLines;

  const _ExpandableExcerpt({required this.text, this.previewLines = 3});

  @override
  State<_ExpandableExcerpt> createState() => _ExpandableExcerptState();
}

class _ExpandableExcerptState extends State<_ExpandableExcerpt> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > 240;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded || !isLong ? null : widget.previewLines,
          overflow: _expanded || !isLong ? null : TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF435E6C),
            height: 1.55,
            fontSize: 13,
          ),
        ),
        if (isLong)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
              ),
              label: Text(_expanded ? 'Show less' : 'Read full excerpt'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF087B76),
                padding: const EdgeInsets.symmetric(horizontal: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }
}


/// Keeps repeated case facts compact without removing them from the report.
class _ExpandableFactLines extends StatefulWidget {
  final List<String> lines;

  const _ExpandableFactLines({required this.lines});

  @override
  State<_ExpandableFactLines> createState() => _ExpandableFactLinesState();
}

class _ExpandableFactLinesState extends State<_ExpandableFactLines> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_expanded)
          ...widget.lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• $line',
                style: const TextStyle(
                  color: Color(0xFF435E6C),
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 15,
          ),
          label: Text(
            _expanded
                ? 'Hide additional facts'
                : 'Show ${widget.lines.length} more case facts',
          ),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF087B76),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
