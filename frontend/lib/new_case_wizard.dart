import 'package:flutter/material.dart';

import 'analysis_result_page.dart';
import 'assistant_vet_api.dart';
import 'case_repository.dart';

class NewCaseWizard extends StatefulWidget {
  const NewCaseWizard({super.key});

  @override
  State<NewCaseWizard> createState() => _NewCaseWizardState();
}

class _NewCaseWizardState extends State<NewCaseWizard> {
  int step = 0;
  bool _analyzing = false;
  bool _searchArticles = true;
  String _activeModelName = 'local model';

  @override
  void initState() {
    super.initState();
    _refreshModelName();
  }

  Future<void> _refreshModelName() async {
    try {
      final response = await AssistantVetApi.health();
      final model = (response['local_ai_model'] ?? '').toString().trim();
      if (mounted && model.isNotEmpty) setState(() => _activeModelName = model);
    } catch (_) {
      // Network status is already checked before analysis starts.
    }
  }


  String? _species;
  String? _sex;
  String? _mucousMembrane;
  String? _crt;
  String? _anemiaPattern;
  String? _plateletFlag;
  String? _spherocytes;
  String? _plateletClumping;
  String? _bilirubin;

  final _patientName = TextEditingController();
  final _breed = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  final _chiefComplaint = TextEditingController();

  final _temperature = TextEditingController();
  final _heartRate = TextEditingController();
  final _respiratoryRate = TextEditingController();
  final _dehydrationPercentController = TextEditingController();
  final _history = TextEditingController();
  final _examNotes = TextEditingController();
  final _currentMedications = TextEditingController();

  final _hct = TextEditingController();
  final _hgb = TextEditingController();
  final _rbc = TextEditingController();
  final _mcv = TextEditingController();
  final _mchc = TextEditingController();
  final _rdw = TextEditingController();
  final _wbc = TextEditingController();
  final _neutrophils = TextEditingController();
  final _lymphocytes = TextEditingController();
  final _platelets = TextEditingController();
  final _reticulocyteNotes = TextEditingController();
  final _chemistryNotes = TextEditingController();

  final _bloodSmearNotes = TextEditingController();
  final _skinCytologyNotes = TextEditingController();
  final _fecalNotes = TextEditingController();

  final _radiographyNotes = TextEditingController();
  final _ultrasoundNotes = TextEditingController();

  final _urinalysisNotes = TextEditingController();
  final _otherTests = TextEditingController();
  final _veterinarianNotes = TextEditingController(
    text:
        'Integrate only the supplied patient data. Identify contradictions, rank etiologic differentials, suggest discriminating next tests and provide source-grounded treatment considerations.',
  );

  final steps = const [
    'Patient',
    'Clinical',
    'Laboratory',
    'Microscopy',
    'Imaging',
    'Other tests',
    'Review',
  ];

  List<TextEditingController> get _controllers => [
        _patientName,
        _breed,
        _age,
        _weight,
        _chiefComplaint,
        _temperature,
        _heartRate,
        _respiratoryRate,
        _dehydrationPercentController,
        _history,
        _examNotes,
        _currentMedications,
        _hct,
        _hgb,
        _rbc,
        _mcv,
        _mchc,
        _rdw,
        _wbc,
        _neutrophils,
        _lymphocytes,
        _platelets,
        _reticulocyteNotes,
        _chemistryNotes,
        _bloodSmearNotes,
        _skinCytologyNotes,
        _fecalNotes,
        _radiographyNotes,
        _ultrasoundNotes,
        _urinalysisNotes,
        _otherTests,
        _veterinarianNotes,
      ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> next() async {
    if (_analyzing) return;

    if (step < steps.length - 1) {
      setState(() => step++);
      return;
    }

    await _analyzeCase();
  }

  void back() {
    if (_analyzing) return;

    if (step > 0) {
      setState(() => step--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _analyzeCase() async {
    FocusScope.of(context).unfocus();

    if (_species == null) {
      _showMessage(
        'Select Dog or Cat before analysis.',
        error: true,
      );
      setState(() => step = 0);
      return;
    }

    final payload = _buildPayload();

    setState(() => _analyzing = true);

    try {
      await AssistantVetApi.health();
      final result = await AssistantVetApi.analyzeCase(payload);

      String? saveWarning;
      try {
        await CaseRepository.saveAnalysis(
          casePayload: payload,
          analysisResult: result,
        );
      } catch (error) {
        saveWarning = error.toString();
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnalysisResultPage(
            result: result,
            casePayload: payload,
          ),
        ),
      );

      if (!mounted || saveWarning == null) return;

      _showMessage(
        'Analysis completed, but the case could not be saved to My Cases: $saveWarning',
        error: true,
      );
    } on AssistantVetApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message, error: true);
    } catch (error) {
      if (!mounted) return;
      _showMessage(
        'Unexpected error while analyzing the case: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _analyzing = false);
      }
    }
  }

  Map<String, dynamic> _buildPayload() {
    final cbc = _compactMap({
      'HCT': _number(_hct.text),
      'HGB': _number(_hgb.text),
      'RBC': _number(_rbc.text),
      'MCV': _number(_mcv.text),
      'MCHC': _number(_mchc.text),
      'RDW': _number(_rdw.text),
      'WBC': _number(_wbc.text),
      'neutrophils': _number(_neutrophils.text),
      'lymphocytes': _number(_lymphocytes.text),
      'platelets': _number(_platelets.text),
      'anemia_pattern': _clean(_anemiaPattern),
      'platelet_flag': _clean(_plateletFlag),
      'reticulocyte_or_analyzer_notes': _clean(_reticulocyteNotes.text),
    });

    final biochemistry = _compactMap({
      'bilirubin': _clean(_bilirubin),
      'summary': _clean(_chemistryNotes.text),
    });

    final bloodSmear = _compactMap({
      'spherocytes': _clean(_spherocytes),
      'platelet_clumping': _clean(_plateletClumping),
      'notes': _clean(_bloodSmearNotes.text),
    });

    final urinalysis = _compactMap({
      'summary': _clean(_urinalysisNotes.text),
    });

    final skinCytology = _compactMap({
      'summary': _clean(_skinCytologyNotes.text),
    });

    final fecal = _compactMap({
      'summary': _clean(_fecalNotes.text),
    });

    final radiography = _compactMap({
      'summary': _clean(_radiographyNotes.text),
    });

    final ultrasound = _compactMap({
      'summary': _clean(_ultrasoundNotes.text),
    });

    final otherTests = _compactMap({
      'summary': _clean(_otherTests.text),
    });

    return {
      'case_id': _makeCaseId(),
      'patient': {
        'name': _clean(_patientName.text),
        'species': _species,
        'breed': _clean(_breed.text),
        'sex': _clean(_sex),
        'age_years': _number(_age.text),
        'weight_kg': _number(_weight.text),
      },
      'clinical': {
        'chief_complaint': _clean(_chiefComplaint.text),
        'history': _clean(_history.text),
        'temperature_c': _number(_temperature.text),
        'heart_rate_bpm': _number(_heartRate.text),
        'respiratory_rate_bpm': _number(_respiratoryRate.text),
        'dehydration_percent': _number(_dehydrationPercentController.text),
        'mucous_membrane': _clean(_mucousMembrane),
        'crt_seconds': _crtSeconds,
        'exam_notes': _clean(_examNotes.text),
      },
      'cbc': cbc.isEmpty ? null : cbc,
      'biochemistry': biochemistry.isEmpty ? null : biochemistry,
      'urinalysis': urinalysis.isEmpty ? null : urinalysis,
      'blood_smear': bloodSmear.isEmpty ? null : bloodSmear,
      'skin_cytology': skinCytology.isEmpty ? null : skinCytology,
      'fecal': fecal.isEmpty ? null : fecal,
      'radiography': radiography.isEmpty ? null : radiography,
      'ultrasound': ultrasound.isEmpty ? null : ultrasound,
      'other_tests': otherTests.isEmpty ? null : otherTests,
      'current_medications': _clean(_currentMedications.text),
      'veterinarian_notes': _clean(_veterinarianNotes.text),
      'requested_article_search': _searchArticles,
      'max_evidence_results': 3,
    };
  }

  String _makeCaseId() {
    final name = _patientName.text.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]+'),
          '-',
        );
    final suffix = DateTime.now().millisecondsSinceEpoch;
    return name.isEmpty ? 'case-$suffix' : '$name-$suffix';
  }

  Map<String, dynamic> _compactMap(Map<String, dynamic> values) {
    final result = <String, dynamic>{};
    values.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      result[key] = value;
    });
    return result;
  }

  String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  num? _number(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return num.tryParse(normalized);
  }


  num? get _crtSeconds {
    switch (_crt) {
      case 'lt2':
        return 1.5;
      case '2to3':
        return 2.5;
      case 'gt3':
        return 3.5;
      default:
        return null;
    }
  }

  void _showMessage(String message, {required bool error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            error ? const Color(0xFFB43C3C) : const Color(0xFF087B76),
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'New Case',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF7F6),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 16,
                      color: Color(0xFF087B76),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Local clinical engine',
                      style: TextStyle(
                        color: Color(0xFF087B76),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              Container(
                width: 250,
                color: Colors.white,
                padding: const EdgeInsets.all(18),
                child: ListView.separated(
                  itemCount: steps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final active = i == step;
                    final done = i < step;
                    return InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: _analyzing ? null : () => setState(() => step = i),
                      child: Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFFE4F6F4)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: done
                                  ? const Color(0xFF0AA7A0)
                                  : active
                                      ? const Color(0xFFD5EFEC)
                                      : const Color(0xFFEEF3F3),
                              child: done
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        color: active
                                            ? const Color(0xFF087B76)
                                            : const Color(0xFF7B8B92),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                steps[i],
                                style: TextStyle(
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: active
                                      ? const Color(0xFF102F46)
                                      : const Color(0xFF667983),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(26),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: const Color(0xFFE4ECEC),
                            ),
                          ),
                          child: SingleChildScrollView(
                            child: _content(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _bottomBar(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_analyzing) _analysisOverlay(),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Row(
      children: [
        TextButton.icon(
          onPressed: _analyzing ? null : back,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
        ),
        const Spacer(),
        const Text(
          'Unavailable fields may stay empty.',
          style: TextStyle(
            color: Color(0xFF7A8990),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 16),
        if (step < steps.length - 1) ...[
          OutlinedButton(
            onPressed: _analyzing ? null : next,
            child: const Text('Skip / Next'),
          ),
          const SizedBox(width: 10),
        ],
        FilledButton.icon(
          onPressed: _analyzing ? null : next,
          icon: _analyzing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  step == steps.length - 1
                      ? Icons.auto_awesome
                      : Icons.arrow_forward,
                ),
          label: Text(
            _analyzing
                ? 'Analyzing...'
                : step == steps.length - 1
                    ? 'Analyze Case'
                    : 'Save & Next',
          ),
        ),
      ],
    );
  }

  Widget _analysisOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xAA102F46),
        child: Center(
          child: Container(
            width: 430,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 35,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 46,
                  height: 46,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Color(0xFF0AA7A0),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Assistant Vet is analyzing this case',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF102F46),
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'The local $_activeModelName engine is integrating clinical data, textbook evidence and literature. Performance depends on available GPU/RAM.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    height: 1.55,
                    color: Color(0xFF6B7F88),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (step) {
      case 0:
        return _patient();
      case 1:
        return _clinical();
      case 2:
        return _laboratory();
      case 3:
        return _microscopy();
      case 4:
        return _imaging();
      case 5:
        return _otherTestsPage();
      default:
        return _review();
    }
  }

  Widget _header(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            color: Color(0xFF102F46),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: Color(0xFF71818A),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _two(Widget a, Widget b) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              a,
              const SizedBox(height: 14),
              b,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: a),
            const SizedBox(width: 14),
            Expanded(child: b),
          ],
        );
      },
    );
  }

  Widget _patient() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Patient information',
          'Enter only what you know. Unknown or unavailable information may be left blank.',
        ),
        _two(
          DropdownButtonFormField<String>(
            value: _species,
            decoration: const InputDecoration(
              labelText: 'Species *',
              prefixIcon: Icon(Icons.pets_outlined),
            ),
            items: const [
              DropdownMenuItem(value: 'dog', child: Text('Dog')),
              DropdownMenuItem(value: 'cat', child: Text('Cat')),
            ],
            onChanged: (value) => setState(() => _species = value),
          ),
          TextField(
            controller: _patientName,
            decoration: const InputDecoration(
              labelText: 'Patient name',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _two(
          TextField(
            controller: _breed,
            decoration: const InputDecoration(
              labelText: 'Breed',
              prefixIcon: Icon(Icons.category_outlined),
            ),
          ),
          TextField(
            controller: _age,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Age (years)',
              prefixIcon: Icon(Icons.cake_outlined),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _two(
          DropdownButtonFormField<String>(
            value: _sex,
            decoration: const InputDecoration(
              labelText: 'Sex / reproductive status',
              prefixIcon: Icon(Icons.transgender),
            ),
            items: const [
              DropdownMenuItem(value: 'male', child: Text('Male')),
              DropdownMenuItem(value: 'female', child: Text('Female')),
              DropdownMenuItem(value: 'neutered male', child: Text('Neutered male')),
              DropdownMenuItem(value: 'spayed female', child: Text('Spayed female')),
            ],
            onChanged: (value) => setState(() => _sex = value),
          ),
          TextField(
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Weight (kg)',
              prefixIcon: Icon(Icons.monitor_weight_outlined),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _chiefComplaint,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Chief complaint',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.notes_outlined),
          ),
        ),
      ],
    );
  }

  Widget _clinical() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Clinical history & examination',
          'Use quick fields first. Leave any unavailable finding blank.',
        ),
        _two(
          TextField(
            controller: _temperature,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Temperature (°C)',
              prefixIcon: Icon(Icons.thermostat_outlined),
            ),
          ),
          TextField(
            controller: _heartRate,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Heart rate (bpm)',
              prefixIcon: Icon(Icons.favorite_outline),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _two(
          TextField(
            controller: _respiratoryRate,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Respiratory rate (bpm)',
              prefixIcon: Icon(Icons.air),
            ),
          ),
          TextField(
            controller: _dehydrationPercentController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Dehydration (%)',
              hintText: 'Example: 6',
              prefixIcon: Icon(Icons.water_drop_outlined),
              helperText: 'Optional — enter the estimated percentage only if assessed.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        _two(
          DropdownButtonFormField<String>(
            value: _mucousMembrane,
            decoration: const InputDecoration(
              labelText: 'Mucous membranes',
              prefixIcon: Icon(Icons.colorize_outlined),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not entered')),
              DropdownMenuItem(value: 'pink', child: Text('Pink')),
              DropdownMenuItem(value: 'pale', child: Text('Pale')),
              DropdownMenuItem(value: 'icteric', child: Text('Icteric')),
              DropdownMenuItem(value: 'cyanotic', child: Text('Cyanotic')),
            ],
            onChanged: (value) => setState(() => _mucousMembrane = (value == null || value.isEmpty) ? null : value),
          ),
          DropdownButtonFormField<String>(
            value: _crt,
            decoration: const InputDecoration(
              labelText: 'CRT',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not entered')),
              DropdownMenuItem(value: 'lt2', child: Text('<2 sec')),
              DropdownMenuItem(value: '2to3', child: Text('2–3 sec')),
              DropdownMenuItem(value: 'gt3', child: Text('>3 sec')),
            ],
            onChanged: (value) => setState(() => _crt = (value == null || value.isEmpty) ? null : value),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _history,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'History / onset / vaccination / diet / exposure',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        _two(
          TextField(
            controller: _currentMedications,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Current medications',
              alignLabelWithHint: true,
            ),
          ),
          TextField(
            controller: _examNotes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Other examination findings',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _laboratory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Laboratory data',
          'Enter only available values. Structured fields are sent directly to the local clinical engine.',
        ),
        _two(
          DropdownButtonFormField<String>(
            value: _anemiaPattern,
            decoration: const InputDecoration(
              labelText: 'Anemia pattern',
              prefixIcon: Icon(Icons.bloodtype_outlined),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not entered / not assessed')),
              DropdownMenuItem(value: 'regenerative', child: Text('Regenerative')),
              DropdownMenuItem(value: 'non-regenerative', child: Text('Non-regenerative')),
              DropdownMenuItem(value: 'preregenerative', child: Text('Pre-regenerative / uncertain')),
            ],
            onChanged: (value) => setState(() => _anemiaPattern = (value == null || value.isEmpty) ? null : value),
          ),
          DropdownButtonFormField<String>(
            value: _plateletFlag,
            decoration: const InputDecoration(
              labelText: 'Analyzer platelet flag',
              prefixIcon: Icon(Icons.analytics_outlined),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not entered / not assessed')),
              DropdownMenuItem(value: 'low platelets', child: Text('Low platelets')),
              DropdownMenuItem(value: 'normal platelets', child: Text('Normal')),
              DropdownMenuItem(value: 'high platelets', child: Text('High platelets')),
            ],
            onChanged: (value) => setState(() => _plateletFlag = (value == null || value.isEmpty) ? null : value),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Only choose an anemia pattern when anemia is actually established or the '
          'laboratory/reticulocyte interpretation explicitly supports that classification. '
          'Leave it as “Not entered” otherwise.',
          style: TextStyle(
            color: Color(0xFF71818A),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'CBC / hematology',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: const Text('All fields optional'),
          children: [
            _two(
              _numberField(_hct, 'HCT / PCV'),
              _numberField(_hgb, 'HGB'),
            ),
            const SizedBox(height: 12),
            _two(
              _numberField(_rbc, 'RBC'),
              _numberField(_mcv, 'MCV'),
            ),
            const SizedBox(height: 12),
            _two(
              _numberField(_mchc, 'MCHC'),
              _numberField(_rdw, 'RDW'),
            ),
            const SizedBox(height: 12),
            _two(
              _numberField(_wbc, 'WBC'),
              _numberField(_neutrophils, 'Neutrophils'),
            ),
            const SizedBox(height: 12),
            _two(
              _numberField(_lymphocytes, 'Lymphocytes'),
              _numberField(_platelets, 'Platelets'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reticulocyteNotes,
              decoration: const InputDecoration(
                labelText: 'Reticulocytes / analyzer flags / reference intervals',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _two(
          DropdownButtonFormField<String>(
            value: _bilirubin,
            decoration: const InputDecoration(
              labelText: 'Serum bilirubin',
              prefixIcon: Icon(Icons.science_outlined),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('Not entered / not assessed')),
              DropdownMenuItem(value: 'normal', child: Text('Normal')),
              DropdownMenuItem(value: 'increased', child: Text('Increased')),
              DropdownMenuItem(value: 'decreased', child: Text('Decreased')),
            ],
            onChanged: (value) => setState(() => _bilirubin = (value == null || value.isEmpty) ? null : value),
          ),
          TextField(
            controller: _chemistryNotes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Other biochemistry findings',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _microscopy() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Microscopy & cytology',
          'Structured microscopy findings are connected now. Image interpretation will be added with the vision engine.',
        ),
        _modalityCard(
          title: 'Blood smear',
          subtitle: 'Enter smear findings that are actually observed.',
          icon: Icons.biotech_outlined,
          child: Column(
            children: [
              _two(
                DropdownButtonFormField<String>(
                  value: _spherocytes,
                  decoration: const InputDecoration(labelText: 'Spherocytes'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Not entered')),
                    DropdownMenuItem(value: 'present', child: Text('Present')),
                    DropdownMenuItem(value: 'absent', child: Text('Absent')),
                  ],
                  onChanged: (value) => setState(() => _spherocytes = (value == null || value.isEmpty) ? null : value),
                ),
                DropdownButtonFormField<String>(
                  value: _plateletClumping,
                  decoration: const InputDecoration(labelText: 'Platelet clumping'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Not entered')),
                    DropdownMenuItem(value: 'present', child: Text('Present')),
                    DropdownMenuItem(value: 'absent', child: Text('Absent')),
                  ],
                  onChanged: (value) => setState(() => _plateletClumping = (value == null || value.isEmpty) ? null : value),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bloodSmearNotes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Other smear findings / morphology / organisms',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _modalityCard(
          title: 'Skin / ear cytology / FNA',
          subtitle: 'Paste or type the observed cytology findings.',
          icon: Icons.bubble_chart_outlined,
          child: TextField(
            controller: _skinCytologyNotes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Findings',
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _modalityCard(
          title: 'Fecal / parasitology',
          subtitle: 'Enter direct smear, flotation or microscopy findings.',
          icon: Icons.grain_outlined,
          child: TextField(
            controller: _fecalNotes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Findings',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _imaging() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Diagnostic imaging',
          'For this integration step, report findings are sent to the reasoning engine. Direct image/video analysis comes next with the imaging model.',
        ),
        _modalityCard(
          title: 'Radiography',
          subtitle: 'Enter body region, views and radiographic findings.',
          icon: Icons.image_outlined,
          child: TextField(
            controller: _radiographyNotes,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Radiography report / findings',
              alignLabelWithHint: true,
            ),
          ),
        ),
        const SizedBox(height: 14),
        _modalityCard(
          title: 'Ultrasound',
          subtitle: 'Enter organ/system and sonographic findings.',
          icon: Icons.monitor_heart_outlined,
          child: TextField(
            controller: _ultrasoundNotes,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Ultrasound report / findings',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _otherTestsPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Other diagnostics',
          'Use this step for urinalysis and tests not covered above.',
        ),
        TextField(
          controller: _urinalysisNotes,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Urinalysis findings',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.water_drop_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _otherTests,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'PCR, serology, endocrine tests, pathology or other results',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _veterinarianNotes,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Veterinarian analysis request / notes',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _review() {
    final payload = _buildPayload();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          'Review & analyze',
          'Only sections containing data will be sent as clinical evidence. Empty modalities remain empty.',
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ReviewChip('Patient data', _hasData(payload['patient'])),
            _ReviewChip('Clinical findings', _hasData(payload['clinical'])),
            _ReviewChip('CBC', payload['cbc'] != null),
            _ReviewChip('Biochemistry', payload['biochemistry'] != null),
            _ReviewChip('Blood smear', payload['blood_smear'] != null),
            _ReviewChip('Skin cytology', payload['skin_cytology'] != null),
            _ReviewChip('Fecal', payload['fecal'] != null),
            _ReviewChip(
              'Imaging',
              payload['radiography'] != null || payload['ultrasound'] != null,
            ),
            _ReviewChip('Urinalysis', payload['urinalysis'] != null),
            _ReviewChip('Other tests', payload['other_tests'] != null),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7F6),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFF0AA7A0)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connected to Assistant Vet Brain',
                      style: TextStyle(
                        color: Color(0xFF102F46),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Analyze Case sends this case to the local FastAPI backend, waits for the Qwen clinical reasoning result, then opens a live result page containing differentials, conflicts, next tests, treatment considerations, textbook evidence and articles.',
                      style: TextStyle(
                        color: Color(0xFF47636F),
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Search current literature',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'Retrieve up to 3 relevant article records for this case.',
                      ),
                      value: _searchArticles,
                      onChanged: (value) {
                        setState(() => _searchArticles = value);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _reviewSummary(payload),
      ],
    );
  }

  Widget _reviewSummary(Map<String, dynamic> payload) {
    final patient = Map<String, dynamic>.from(payload['patient'] as Map);
    final clinical = Map<String, dynamic>.from(payload['clinical'] as Map);

    final lines = <String>[];
    if (_clean(patient['name']?.toString()) != null) {
      lines.add('Patient: ${patient['name']}');
    }
    lines.add('Species: ${patient['species'] ?? 'not selected'}');
    if (_clean(patient['breed']?.toString()) != null) {
      lines.add('Breed: ${patient['breed']}');
    }
    if (_clean(clinical['chief_complaint']?.toString()) != null) {
      lines.add('Chief complaint: ${clinical['chief_complaint']}');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E5E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Case snapshot',
            style: TextStyle(
              color: Color(0xFF102F46),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: const TextStyle(color: Color(0xFF526B78)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasData(dynamic value) {
    if (value == null) return false;
    if (value is Map) return value.values.any(_hasData);
    if (value is List) return value.any(_hasData);
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }

  Widget _modalityCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD8E5E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE2F4F2),
                child: Icon(icon, color: const Color(0xFF087B76)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF71818A),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ReviewChip extends StatelessWidget {
  final String label;
  final bool hasData;

  const _ReviewChip(this.label, this.hasData);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: hasData ? const Color(0xFFE3F4F0) : const Color(0xFFF2F4F4),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasData ? Icons.check_circle : Icons.remove_circle_outline,
            size: 16,
            color: hasData
                ? const Color(0xFF0A8D87)
                : const Color(0xFF9AA6AA),
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
