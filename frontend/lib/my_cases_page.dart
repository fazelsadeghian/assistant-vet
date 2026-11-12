import 'package:flutter/material.dart';

import 'analysis_result_page.dart';
import 'case_repository.dart';
import 'new_case_wizard.dart';

class MyCasesPage extends StatefulWidget {
  const MyCasesPage({super.key});

  @override
  State<MyCasesPage> createState() => _MyCasesPageState();
}

class _MyCasesPageState extends State<MyCasesPage> {
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<SavedCaseRecord> _allCases = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCases() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cases = await CaseRepository.fetchCases();

      if (!mounted) return;

      setState(() {
        _allCases = cases;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<SavedCaseRecord> get _filteredCases {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allCases;

    return _allCases.where((item) {
      final haystack = [
        item.patientName,
        item.species,
        item.breed,
        item.chiefComplaint,
        item.leadingDiagnosis,
        item.caseId,
      ].join(' ').toLowerCase();

      return haystack.contains(q);
    }).toList();
  }

  Future<void> _openCase(SavedCaseRecord item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisResultPage(
          result: item.analysisResult,
          casePayload: item.casePayload,
        ),
      ),
    );
  }

  Future<void> _startNewCase() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NewCaseWizard(),
      ),
    );

    if (mounted) {
      await _loadCases();
    }
  }

  Future<void> _deleteCase(SavedCaseRecord item) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('حذف کامل کیس؟'),
          content: Text(
            item.patientName.isEmpty
                ? 'این کیس برای همیشه از حساب حذف خواهد شد.'
                : 'کیس «${item.patientName}» برای همیشه از حساب حذف خواهد شد.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB43C3C),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('حذف قطعی'),
            ),
          ],
        );
      },
    );

    if (approved != true) return;

    try {
      await CaseRepository.deleteCase(item.id);

      if (!mounted) return;

      setState(() {
        _allCases = _allCases.where((row) => row.id != item.id).toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('کیس حذف شد.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB43C3C),
          content: Text('Could not delete the case: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredCases;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'My Cases',
          style: TextStyle(
            color: Color(0xFF102F46),
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadCases,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1180),
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 18),
              _search(),
              const SizedBox(height: 18),
              Expanded(
                child: _body(items),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startNewCase,
        backgroundColor: const Color(0xFF0AA7A0),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'New Case',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF075E70),
            Color(0xFF0AA7A0),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.folder_copy_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Clinical case history',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_allCases.length} saved case${_allCases.length == 1 ? '' : 's'} for this account',
                  style: const TextStyle(
                    color: Color(0xFFDDF6F4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _search() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        setState(() {
          _query = value;
        });
      },
      decoration: InputDecoration(
        hintText: 'Search by patient, breed, complaint or diagnosis...',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                  });
                },
                icon: const Icon(Icons.close_rounded),
              ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFFDDE8E8),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFFDDE8E8),
          ),
        ),
      ),
    );
  }

  Widget _body(List<SavedCaseRecord> items) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return _messageState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load saved cases',
        message: _error!,
        buttonLabel: 'Try again',
        onPressed: _loadCases,
      );
    }

    if (items.isEmpty) {
      return _messageState(
        icon: Icons.folder_open_outlined,
        title: _query.isEmpty ? 'No saved cases yet' : 'No matching cases',
        message: _query.isEmpty
            ? 'Completed analyses will be saved here automatically.'
            : 'Try a different patient name, complaint or diagnosis.',
        buttonLabel: _query.isEmpty ? 'Start New Case' : 'Clear search',
        onPressed: _query.isEmpty
            ? _startNewCase
            : () {
                _searchController.clear();
                setState(() {
                  _query = '';
                });
              },
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCases,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _caseCard(items[index]);
        },
      ),
    );
  }

  Widget _caseCard(SavedCaseRecord item) {
    final patient = item.patientName.isEmpty ? 'Unnamed patient' : item.patientName;
    final species = _capitalize(item.species);
    final subtitleParts = <String>[
      if (species.isNotEmpty) species,
      if (item.breed.isNotEmpty) item.breed,
      if (item.updatedAt != null) _formatDate(item.updatedAt!),
    ];

    final gatePass = item.clinicalGateStatus.toLowerCase() == 'pass';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: () => _openCase(item),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: const Color(0xFFDDE8E8),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F7F5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.pets,
                  color: Color(0xFF087B76),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            patient,
                            style: const TextStyle(
                              color: Color(0xFF102F46),
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (item.clinicalGateStatus.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: gatePass
                                  ? const Color(0xFFE7F6F1)
                                  : const Color(0xFFFFF1E5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Gate ${_capitalize(item.clinicalGateStatus)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: gatePass
                                    ? const Color(0xFF087B76)
                                    : const Color(0xFF9A5520),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' • '),
                        style: const TextStyle(
                          color: Color(0xFF74878F),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (item.chiefComplaint.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        item.chiefComplaint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF536B76),
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (item.leadingDiagnosis.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.fact_check_outlined,
                            color: Color(0xFF0AA7A0),
                            size: 17,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item.leadingDiagnosis,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF102F46),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'حذف کیس · Delete Case',
                onPressed: () => _deleteCase(item),
                icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFB43C3C)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: const Color(0xFFDDE8E8),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 44,
              color: const Color(0xFF0AA7A0),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF102F46),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF74878F),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: onPressed,
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$year-$month-$day  $hour:$minute';
  }
}
