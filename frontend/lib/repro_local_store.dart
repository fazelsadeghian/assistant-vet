import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Windows-local reproductive records. No dependency on the prescription API.
/// The records reside under %LOCALAPPDATA%\AssistantVet\reproduction.
String newReproId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(999999)}';

double? reproDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString().replaceAll(',', '.'));
}

DateTime reproDate(dynamic value) =>
    DateTime.tryParse((value ?? '').toString()) ?? DateTime.now();

class MareRecord {
  final String id;
  String name;
  String reference;
  String breed;
  String owner;
  String age;
  String imagePath;
  String notes;
  final List<BreedingCycle> cycles;

  MareRecord({
    required this.id,
    required this.name,
    this.reference = '',
    this.breed = '',
    this.owner = '',
    this.age = '',
    this.imagePath = '',
    this.notes = '',
    List<BreedingCycle>? cycles,
  }) : cycles = cycles ?? [];

  factory MareRecord.fromJson(Map<String, dynamic> json) => MareRecord(
        id: '${json['id'] ?? newReproId()}',
        name: '${json['name'] ?? ''}',
        reference: '${json['reference'] ?? ''}',
        breed: '${json['breed'] ?? ''}',
        owner: '${json['owner'] ?? ''}',
        age: '${json['age'] ?? ''}',
        imagePath: '${json['imagePath'] ?? ''}',
        notes: '${json['notes'] ?? ''}',
        cycles: (json['cycles'] is List ? json['cycles'] as List : [])
            .whereType<Map>()
            .map((e) => BreedingCycle.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'reference': reference,
        'breed': breed,
        'owner': owner,
        'age': age,
        'imagePath': imagePath,
        'notes': notes,
        'cycles': cycles.map((e) => e.toJson()).toList(),
      };
}

class BreedingCycle {
  final String id;
  final DateTime createdAt;
  DateTime? heatStart;
  String semenMethod;
  int cycleDisplayDays;
  String stallion;
  String notes;
  /// Stored planning preferences, NOT clinical events or medication orders.
  String pregnancyStatus;
  String scenarioHormone;
  String scenarioProduct;
  DateTime? scenarioInjectionAt;
  DateTime? targetBreedingAt;
  final List<BreedingEvent> events;

  BreedingCycle({
    required this.id,
    required this.createdAt,
    this.heatStart,
    this.semenMethod = 'natural',
    this.cycleDisplayDays = 21,
    this.stallion = '',
    this.notes = '',
    this.pregnancyStatus = 'unknown',
    this.scenarioHormone = 'none',
    this.scenarioProduct = 'unspecified',
    this.scenarioInjectionAt,
    this.targetBreedingAt,
    List<BreedingEvent>? events,
  }) : events = events ?? [];

  factory BreedingCycle.fromJson(Map<String, dynamic> json) => BreedingCycle(
        id: '${json['id'] ?? newReproId()}',
        createdAt: reproDate(json['createdAt']),
        heatStart: json['heatStart'] == null
            ? null
            : DateTime.tryParse('${json['heatStart']}'),
        semenMethod: '${json['semenMethod'] ?? 'natural'}',
        cycleDisplayDays: (json['cycleDisplayDays'] is num ? (json['cycleDisplayDays'] as num).toInt() : 21).clamp(18,30).toInt(),
        stallion: '${json['stallion'] ?? ''}',
        notes: '${json['notes'] ?? ''}',
        pregnancyStatus: '${json['pregnancyStatus'] ?? 'unknown'}',
        scenarioHormone: '${json['scenarioHormone'] ?? 'none'}',
        scenarioProduct: '${json['scenarioProduct'] ?? 'unspecified'}',
        scenarioInjectionAt: DateTime.tryParse('${json['scenarioInjectionAt'] ?? ''}'),
        targetBreedingAt: DateTime.tryParse('${json['targetBreedingAt'] ?? ''}'),
        events: (json['events'] is List ? json['events'] as List : [])
            .whereType<Map>()
            .map((e) => BreedingEvent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'heatStart': heatStart?.toIso8601String(),
        'semenMethod': semenMethod,
        'cycleDisplayDays': cycleDisplayDays,
        'stallion': stallion,
        'notes': notes,
        'pregnancyStatus': pregnancyStatus,
        'scenarioHormone': scenarioHormone,
        'scenarioProduct': scenarioProduct,
        'scenarioInjectionAt': scenarioInjectionAt?.toIso8601String(),
        'targetBreedingAt': targetBreedingAt?.toIso8601String(),
        'events': events.map((e) => e.toJson()).toList(),
      };
}

/// One independently traceable structure on one ovary.
/// kind: follicle, cl (corpus luteum), ch (hemorrhagic body / differential HAF).
/// A measured dimension is not a physical reconstruction of an ovary.
class OvarianStructure {
  final String id;
  final String kind;
  final double? diameterMm;
  final double? secondDiameterMm;
  final int? chGrade;
  final bool dominant;
  final String shape;

  const OvarianStructure({required this.id, required this.kind,
    this.diameterMm, this.secondDiameterMm, this.chGrade,
    this.dominant = false, this.shape = 'unknown'});

  factory OvarianStructure.fromJson(Map<String, dynamic> json) =>
      OvarianStructure(
        id: '${json['id'] ?? newReproId()}',
        kind: const ['follicle', 'cl', 'ch'].contains(json['kind'])
            ? '${json['kind']}' : 'follicle',
        diameterMm: reproDouble(json['diameterMm']),
        secondDiameterMm: reproDouble(json['secondDiameterMm']),
        chGrade: (json['chGrade'] as num?)?.toInt(),
        dominant: json['dominant'] == true,
        shape: '${json['shape'] ?? 'unknown'}',
      );

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind, 'diameterMm': diameterMm,
    'secondDiameterMm': secondDiameterMm, 'chGrade': chGrade,
    'dominant': dominant, 'shape': shape,
  };
  double? get meanDiameterMm => diameterMm == null ? null :
      secondDiameterMm == null ? diameterMm :
      (diameterMm! + secondDiameterMm!) / 2;
}

class BreedingEvent {
  final String id;
  final DateTime at;
  final String type;
  final String details;
  final String imagePath;
  final double? leftFollicleMm;
  final double? rightFollicleMm;
  final int? edemaScore;
  /// Mare teasing/receptivity observed by the clinician: 0=no estrus, 4=strong.
  /// Null means not assessed. This is distinct from uterine edema.
  final int? estrusScore;
  final String cervixStatus;
  final String uterineFluid;
  final String corpusLuteum;
  final bool? leftCl, rightCl;
  /// v36 multiple independently recorded structures, with v35 fallback.
  final List<OvarianStructure> leftStructures, rightStructures;
  /// Local, clinician-entered CH appearance stage: null=unknown, 0=absent, 1-3=label only.
  final int? leftChGrade, rightChGrade;
  final double? leftClMm, rightClMm;
  final bool sameLeftFollicle, sameRightFollicle;
  final String leftShape, rightShape;
  final String medicine;
  final String administeredDose;
  final String route;
  final String semenBatch;
  final bool plannedByVet;

  const BreedingEvent({
    required this.id,
    required this.at,
    required this.type,
    this.details = '',
    this.imagePath = '',
    this.leftFollicleMm,
    this.rightFollicleMm,
    this.edemaScore,
    this.estrusScore,
    this.cervixStatus = 'not_assessed',
    this.uterineFluid = 'not_assessed',
    this.corpusLuteum = 'not_assessed',
    this.leftCl,this.rightCl,this.leftClMm,this.rightClMm,
    this.leftStructures = const [], this.rightStructures = const [],
    this.leftChGrade,this.rightChGrade,
    this.sameLeftFollicle=false,this.sameRightFollicle=false,
    this.leftShape='unknown',this.rightShape='unknown',
    this.medicine = '',
    this.administeredDose = '',
    this.route = '',
    this.semenBatch = '',
    this.plannedByVet = false,
  });

  factory BreedingEvent.fromJson(Map<String, dynamic> json) => BreedingEvent(
        id: '${json['id'] ?? newReproId()}',
        at: reproDate(json['at']),
        type: '${json['type'] ?? 'note'}',
        details: '${json['details'] ?? ''}',
        imagePath: '${json['imagePath'] ?? ''}',
        leftFollicleMm: reproDouble(json['leftFollicleMm']),
        rightFollicleMm: reproDouble(json['rightFollicleMm']),
        edemaScore: (json['edemaScore'] as num?)?.toInt(),
        estrusScore: (json['estrusScore'] is num &&
                (json['estrusScore'] as num) >= 0 &&
                (json['estrusScore'] as num) <= 4)
            ? (json['estrusScore'] as num).toInt()
            : null,
        cervixStatus: '${json['cervixStatus'] ?? 'not_assessed'}',
        uterineFluid: '${json['uterineFluid'] ?? 'not_assessed'}',
        corpusLuteum: '${json['corpusLuteum'] ?? 'not_assessed'}',
        leftStructures: _structuresFromJson(json, 'left'),
        rightStructures: _structuresFromJson(json, 'right'),
        leftCl: json['leftCl'] is bool ? json['leftCl'] as bool : null,
        leftChGrade: (json['leftChGrade'] is num && (json['leftChGrade'] as num) >= 0 && (json['leftChGrade'] as num) <= 3) ? (json['leftChGrade'] as num).toInt() : null,
        rightChGrade: (json['rightChGrade'] is num && (json['rightChGrade'] as num) >= 0 && (json['rightChGrade'] as num) <= 3) ? (json['rightChGrade'] as num).toInt() : null,
        rightCl: json['rightCl'] is bool ? json['rightCl'] as bool : null,
        leftClMm: reproDouble(json['leftClMm']),rightClMm:reproDouble(json['rightClMm']),
        sameLeftFollicle:json['sameLeftFollicle']==true,sameRightFollicle:json['sameRightFollicle']==true,
        leftShape:'${json['leftShape'] ?? 'unknown'}',rightShape:'${json['rightShape'] ?? 'unknown'}',
        medicine: '${json['medicine'] ?? ''}',
        administeredDose: '${json['administeredDose'] ?? ''}',
        route: '${json['route'] ?? ''}',
        semenBatch: '${json['semenBatch'] ?? ''}',
        plannedByVet: json['plannedByVet'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'type': type,
        'details': details,
        'imagePath': imagePath,
        'leftFollicleMm': leftFollicleMm,
        'rightFollicleMm': rightFollicleMm,
        'edemaScore': edemaScore,
        'estrusScore': estrusScore,
        'cervixStatus': cervixStatus,
        'uterineFluid': uterineFluid,
        'corpusLuteum': corpusLuteum,
        'leftCl':leftCl,'rightCl':rightCl,
        'leftStructures': leftStructures.map((s) => s.toJson()).toList(),
        'rightStructures': rightStructures.map((s) => s.toJson()).toList(),
        'leftChGrade':leftChGrade,'rightChGrade':rightChGrade,
        'leftClMm':leftClMm,'rightClMm':rightClMm,
        'sameLeftFollicle':sameLeftFollicle,'sameRightFollicle':sameRightFollicle,
        'leftShape':leftShape,'rightShape':rightShape,
        'medicine': medicine,
        'administeredDose': administeredDose,
        'route': route,
        'semenBatch': semenBatch,
        'plannedByVet': plannedByVet,
      };

  /// For a historical record with no v36 arrays, create a read-only in-memory
  /// representation of the v34/v35 single observations. Never discard old data.
  static List<OvarianStructure> _structuresFromJson(Map<String, dynamic> j, String side) {
    final k = '${side}Structures';
    if (j[k] is List) {
      return (j[k] as List).whereType<Map>().map((x) =>
        OvarianStructure.fromJson(Map<String, dynamic>.from(x))).toList();
    }
    final result = <OvarianStructure>[];
    final follicle = reproDouble(j['${side}FollicleMm']);
    if (follicle != null && follicle > 0) result.add(OvarianStructure(
      id: '${j['id'] ?? 'old'}_${side}_f1', kind: 'follicle',
      diameterMm: follicle, dominant: true));
    if (j['${side}Cl'] == true) result.add(OvarianStructure(
      id: '${j['id'] ?? 'old'}_${side}_cl1', kind: 'cl',
      diameterMm: reproDouble(j['${side}ClMm'])));
    final ch = (j['${side}ChGrade'] as num?)?.toInt();
    if (ch != null && ch > 0) result.add(OvarianStructure(
      id: '${j['id'] ?? 'old'}_${side}_ch1', kind: 'ch', chGrade: ch));
    return result;
  }

  List<OvarianStructure> structures(String side) =>
      side == 'left' ? leftStructures : rightStructures;

  int get clCount => [...leftStructures, ...rightStructures]
      .where((s) => s.kind == 'cl').length;

  int get largeFollicleCount => [...leftStructures, ...rightStructures]
      .where((s) => s.kind == 'follicle' &&
          (s.meanDiameterMm ?? 0) >= 30).length;

  double? get dominantFollicleMm {
    final values = <double>[
      ...[...leftStructures, ...rightStructures]
          .where((s) => s.kind == 'follicle')
          .map((s) => s.meanDiameterMm).whereType<double>(),
      if (leftStructures.isEmpty && leftFollicleMm != null) leftFollicleMm!,
      if (rightStructures.isEmpty && rightFollicleMm != null) rightFollicleMm!,
    ];
    if (values.isEmpty) return null;
    return values.reduce(max);
  }

}

class ProstateObservation {
  final String id;
  final DateTime at;
  final String dogName;
  final String reference;
  final double weightKg;
  final double ageYears;
  final String neuterStatus;
  final double measuredCm3;
  /// Original dimensions are saved for NEW ellipsoid measurements only.
  /// Historical records saved before v39 may contain volume but no dimensions.
  final double? lengthCm, widthCm, heightCm;
  final String method;
  final String imagePath;
  final String notes;

  const ProstateObservation({
    required this.id,
    required this.at,
    required this.dogName,
    required this.reference,
    required this.weightKg,
    required this.ageYears,
    required this.neuterStatus,
    required this.measuredCm3,
    this.lengthCm, this.widthCm, this.heightCm,
    required this.method,
    this.imagePath = '',
    this.notes = '',
  });

  factory ProstateObservation.fromJson(Map<String, dynamic> json) =>
      ProstateObservation(
        id: '${json['id'] ?? newReproId()}',
        at: reproDate(json['at']),
        dogName: '${json['dogName'] ?? ''}',
        reference: '${json['reference'] ?? ''}',
        weightKg: reproDouble(json['weightKg']) ?? 0,
        ageYears: reproDouble(json['ageYears']) ?? 0,
        neuterStatus: '${json['neuterStatus'] ?? 'unknown'}',
        measuredCm3: reproDouble(json['measuredCm3']) ?? 0,
        lengthCm: reproDouble(json['lengthCm']),
        widthCm: reproDouble(json['widthCm']),
        heightCm: reproDouble(json['heightCm']),
        method: '${json['method'] ?? 'manual'}',
        imagePath: '${json['imagePath'] ?? ''}',
        notes: '${json['notes'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'dogName': dogName,
        'reference': reference,
        'weightKg': weightKg,
        'ageYears': ageYears,
        'neuterStatus': neuterStatus,
        'measuredCm3': measuredCm3,
        'lengthCm': lengthCm,
        'widthCm': widthCm,
        'heightCm': heightCm,
        'method': method,
        'imagePath': imagePath,
        'notes': notes,
      };
}

class ReproLocalStore {
  Directory get root {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Platform.environment['HOME'];
    if (base == null || base.isEmpty) {
      throw const FileSystemException('User data directory not available');
    }
    return Directory('$base${Platform.pathSeparator}AssistantVet'
        '${Platform.pathSeparator}reproduction');
  }

  Future<List<MareRecord>> loadMares() async {
    final json = await _readList('mares.json');
    return json.map(MareRecord.fromJson).toList();
  }

  Future<void> saveMares(List<MareRecord> values) async =>
      _writeList('mares.json', values.map((e) => e.toJson()).toList());

  Future<List<ProstateObservation>> loadProstates() async {
    final json = await _readList('prostate_history.json');
    return json.map(ProstateObservation.fromJson).toList();
  }

  Future<void> saveProstates(List<ProstateObservation> values) async =>
      _writeList('prostate_history.json', values.map((e) => e.toJson()).toList());

  Future<List<Map<String, dynamic>>> _readList(String filename) async {
    final file = File('${root.path}${Platform.pathSeparator}$filename');
    final backup = File('${file.path}.bak');
    if (!await file.exists() && !await backup.exists()) return [];
    Future<List<Map<String, dynamic>>> decode(File source) async {
      final raw = jsonDecode(await source.readAsString());
      if (raw is! List) throw const FormatException('Expected a JSON list');
      return raw.whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m)).toList();
    }
    try {
      return await decode(await file.exists() ? file : backup);
    } catch (_) {
      if (await backup.exists()) return decode(backup);
      rethrow;
    }
  }

  Future<void> _writeList(String filename, List<Map<String, dynamic>> data) async {
    await root.create(recursive: true);
    final path = '${root.path}${Platform.pathSeparator}$filename';
    final tmp = File('$path.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    final target = File(path);
    // Retain one restorable prior snapshot before replacing the current data.
    if (await target.exists()) {
      await target.copy('$path.bak');
      await target.delete();
    }
    await tmp.rename(path);
  }

  /// Open native Windows picker without changing pubspec.yaml/dependencies.
  Future<void> openDataFolder() async {
    await root.create(recursive: true);
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [root.path]);
    }
  }

  Future<String?> selectImage() async {
    if (!Platform.isWindows) return null;
    const script = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Select horse or ultrasound image'
$dialog.Filter = 'Images|*.jpg;*.jpeg;*.png;*.webp;*.bmp|All files|*.*'
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
  [Console]::WriteLine($dialog.FileName)
}
''';
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-STA', '-Command', script],
    );
    if (result.exitCode != 0) {
      throw FileSystemException('Image picker failed: ${result.stderr}');
    }
    final picked = result.stdout.toString().trim();
    if (picked.isEmpty) return null;
    final file = File(picked);
    if (!await file.exists()) throw const FileSystemException('Image file missing');
    return picked;
  }

  /// After a permanent user-confirmed case deletion, replace the application's
  /// previous mares.json.bak with the current record set. This prevents the
  /// deleted mare from returning if recovery falls back to the backup file.
  Future<void> synchronizeMareBackup() async {
    final file = File('${root.path}${Platform.pathSeparator}mares.json');
    if (await file.exists()) {
      await file.copy('${file.path}.bak');
    }
  }

  /// Remove image copies belonging exclusively to a deleted mare. Only files
  /// inside this app's managed reproduction/images folder can be deleted.
  Future<void> deleteOrphanMareImages(
      MareRecord removed, List<MareRecord> retained) async {
    Iterable<String> pathsFor(MareRecord mare) sync* {
      if (mare.imagePath.isNotEmpty) yield mare.imagePath;
      for (final cycle in mare.cycles) {
        for (final event in cycle.events) {
          if (event.imagePath.isNotEmpty) yield event.imagePath;
        }
      }
    }
    final used = retained.expand(pathsFor).map((x) => x.toLowerCase()).toSet();
    final managed = '${root.path}${Platform.pathSeparator}images${Platform.pathSeparator}'
        .toLowerCase();
    for (final path in pathsFor(removed).toSet()) {
      if (!path.toLowerCase().startsWith(managed) ||
          used.contains(path.toLowerCase())) continue;
      final candidate = File(path);
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Future<String> importImage(String original) async {
    final file = File(original);
    if (!await file.exists()) throw const FileSystemException('Image not found');
    final extension = original.split('.').last.toLowerCase();
    if (!{'png', 'jpg', 'jpeg', 'webp', 'bmp'}.contains(extension)) {
      throw const FormatException('Unsupported image type');
    }
    if (await file.length() > 20 * 1024 * 1024) {
      throw const FormatException('Image is larger than 20 MB');
    }
    final images = Directory('${root.path}${Platform.pathSeparator}images');
    await images.create(recursive: true);
    final dest = '${images.path}${Platform.pathSeparator}${newReproId()}.$extension';
    await file.copy(dest);
    return dest;
  }
}
