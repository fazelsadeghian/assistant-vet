import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

import 'repro_local_store.dart';
import 'repro_timing_engine.dart';
import 'repro_hormone_planner_v33.dart';
import 'repro_cycle_visuals_v33.dart';
import 'repro_cycle_engine_v34.dart';
import 'repro_v34_widgets.dart';
import 'repro_jalali_v35.dart';
import 'repro_clinical_workspace_v35.dart';
import 'repro_multi_exam_v36.dart';

const _ink = Color(0xFF12384C);
const _teal = Color(0xFF008E87);
const _muted = Color(0xFF6F858E);
const _paper = Color(0xFFF3F7F8);

String _stamp(DateTime date) => ReproJalali.stamp(date);
String _dateOnly(DateTime date) => ReproJalali.date(date);

String _methodLabel(String method) => switch (method) {
      'natural' => 'Natural cover · کشش طبیعی',
      'fresh' => 'Fresh AI · اسپرم تازه',
      'cooled' => 'Cooled AI · اسپرم سرد',
      'frozen' => 'Frozen AI · اسپرم فریز',
      _ => method,
    };

String _eventLabel(String type) => switch (type) {
      'ultrasound' => 'Ultrasound / سونوگرافی',
      'heat_check' => 'Estrus observation / ارزیابی فحلی',
      'hormone' => 'Hormone / تزریق هورمون',
      'cover' => 'Natural cover / کشش طبیعی',
      'insemination' => 'Insemination / تلقیح',
      'semen' => 'Semen logistics / دریافت اسپرم',
      'ovulation' => 'Ovulation confirmed / تخمک‌گذاری',
      'recheck' => 'Re-examination / معاینهٔ مجدد',
      'pregnancy' => 'Pregnancy scan / بررسی آبستنی',
      'note' => 'Clinical note / یادداشت',
      _ => type,
    };

IconData _eventIcon(String type) => switch (type) {
      'ultrasound' => Icons.monitor_heart_outlined,
      'heat_check' => Icons.favorite_border_outlined,
      'hormone' => Icons.vaccines_outlined,
      'cover' => Icons.favorite_outline,
      'insemination' => Icons.science_outlined,
      'semen' => Icons.inventory_2_outlined,
      'ovulation' => Icons.check_circle_outline,
      'recheck' => Icons.event_repeat_outlined,
      'pregnancy' => Icons.child_friendly_outlined,
      _ => Icons.notes_outlined,
    };

class EquineReproductionPage extends StatefulWidget {
  const EquineReproductionPage({super.key});
  @override
  State<EquineReproductionPage> createState() => _EquineReproductionPageState();
}

class _EquineReproductionPageState extends State<EquineReproductionPage> {
  final _store = ReproLocalStore();
  final _search = TextEditingController();
  List<MareRecord> _mares = [];
  String? _selectedMareId;
  String? _selectedCycleId;
  bool _loading = true;

  MareRecord? get _mare {
    for (final m in _mares) {
      if (m.id == _selectedMareId) return m;
    }
    return null;
  }

  BreedingCycle? get _cycle {
    final mare = _mare;
    if (mare == null) return null;
    for (final c in mare.cycles) {
      if (c.id == _selectedCycleId) return c;
    }
    return mare.cycles.isNotEmpty ? mare.cycles.last : null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final mares = await _store.loadMares();
      if (!mounted) return;
      setState(() {
        _mares = mares;
        _selectedMareId = mares.isEmpty ? null : mares.first.id;
        _selectedCycleId = mares.isEmpty || mares.first.cycles.isEmpty
            ? null : mares.first.cycles.last.id;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('خطا در خواندن اطلاعات: $e', error: true);
    }
  }

  void _toast(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? const Color(0xFFB24D46) : _teal,
      content: Text(value),
    ));
  }

  Future<bool> _persist() async {
    try {
      await _store.saveMares(_mares);
      if (mounted) setState(() {});
      return true;
    } catch (e) {
      if (mounted) _toast('ذخیره انجام نشد: $e', error: true);
      return false;
    }
  }

  Future<DateTime?> _chooseDateTime(DateTime current) =>
      ReproJalali.pickDateTime(context, current);

  Future<void> _addOrEditMare({MareRecord? original}) async {
    final name = TextEditingController(text: original?.name ?? '');
    final reference = TextEditingController(text: original?.reference ?? '');
    final age = TextEditingController(text: original?.age ?? '');
    final breed = TextEditingController(text: original?.breed ?? '');
    final owner = TextEditingController(text: original?.owner ?? '');
    final notes = TextEditingController(text: original?.notes ?? '');
    var image = original?.imagePath ?? '';
    var newImage = false;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
          title: Text(original == null ? 'Register mare · ثبت مادیان' : 'Edit mare profile'),
          content: SizedBox(width: 550, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _field('نام مادیان *', name),
              const SizedBox(height: 10),
              _field('کد اسب / شناسه', reference),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Row(children: [
                  Expanded(child: _field('نژاد مادیان', breed)),
                  PopupMenuButton<String>(tooltip: 'انتخاب نژاد',
                    icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                    onSelected: (v) => breed.text = v,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'Thoroughbred', child: Text('تروبرد · Thoroughbred')),
                      PopupMenuItem(value: 'Arabian', child: Text('عرب · Arabian')),
                      PopupMenuItem(value: 'Quarter Horse', child: Text('کوارتر · Quarter Horse')),
                      PopupMenuItem(value: 'Standardbred', child: Text('استانداردبرد · Standardbred')),
                      PopupMenuItem(value: 'Warmblood', child: Text('وارم‌بلاد · Warmblood')),
                      PopupMenuItem(value: 'Akhal-Teke', child: Text('آخال تکه · Akhal-Teke')),
                      PopupMenuItem(value: 'Caspian', child: Text('کاسپین · Caspian')),
                      PopupMenuItem(value: 'Turkmen', child: Text('ترکمن · Turkmen')),
                      PopupMenuItem(value: 'Kurdish', child: Text('کرد · Kurdish')),
                      PopupMenuItem(value: 'Mixed', child: Text('دورگه · Mixed')),
                    ]),
                ])),
                const SizedBox(width: 10),
                Expanded(child: _field('سن (سال)', age)),
              ]),
              const SizedBox(height: 10),
              _field('مالک (اختیاری)', owner),
              const SizedBox(height: 10),
              _field('یادداشت', notes, lines: 2),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final selected = await _store.selectImage();
                    if (selected != null) {
                      update(() { image = selected; newImage = true; });
                    }
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('$e')));
                  }
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('عکس اسب / Select photo'),
              ),
              if (image.isNotEmpty) ...[
                const SizedBox(height: 9),
                ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(image), height: 120,
                    errorBuilder: (_, __, ___) => const Text('Preview unavailable'))),
              ],
            ]),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
            FilledButton(onPressed: () {
              if (name.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('نام مادیان الزامی است.')));
                return;
              }
              Navigator.pop(ctx, true);
            }, child: const Text('Save profile')),
          ],
        )),
      );
      if (accepted != true) return;
      var path = image;
      if (newImage) path = await _store.importImage(image);
      if (original == null) {
        final mare = MareRecord(
          id: newReproId(), name: name.text.trim(),
          reference: reference.text.trim(), breed: breed.text.trim(),
          owner: owner.text.trim(), age: age.text.trim(),
          notes: notes.text.trim(), imagePath: path,
        );
        _mares.add(mare);
        _selectedMareId = mare.id;
        _selectedCycleId = null;
      } else {
        original.name = name.text.trim();
        original.reference = reference.text.trim();
        original.breed = breed.text.trim();
        original.owner = owner.text.trim();
        original.age = age.text.trim();
        original.notes = notes.text.trim();
        original.imagePath = path;
      }
      if (await _persist() && mounted) _toast('پروندهٔ مادیان ذخیره شد.');
    } catch (e) {
      if (mounted) _toast('ثبت پرونده ناموفق بود: $e', error: true);
    } finally {
      for (final c in [name, reference, breed, age, owner, notes]) { c.dispose(); }
    }
  }

  Future<void> _removeMare(MareRecord mare) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کامل پرونده مادیان؟'),
        content: Text('پرونده «${mare.name}» با ${mare.cycles.length} سیکل، همه سونوها و رویدادهای آن حذف می‌شود. این عملیات قابل بازگشت نیست. آیا ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB53A3A)),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('حذف قطعی پرونده')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final index = _mares.indexWhere((m) => m.id == mare.id);
    if (index < 0) return;
    _mares.removeAt(index);
    final previousId = _selectedMareId;
    final previousCycleId = _selectedCycleId;
    if (_selectedMareId == mare.id) {
      _selectedMareId = _mares.isEmpty ? null : _mares.first.id;
      _selectedCycleId = _mares.isEmpty || _mares.first.cycles.isEmpty
          ? null : _mares.first.cycles.last.id;
    }
    if (!await _persist()) {
      _mares.insert(index, mare);
      _selectedMareId = previousId;
      _selectedCycleId = previousCycleId;
      if (mounted) setState(() {});
      return;
    }
    try {
      await _store.synchronizeMareBackup();
      await _store.deleteOrphanMareImages(mare, _mares);
    } catch (_) {
      // Case removed from primary storage; backup/image cleanup is best effort.
    }
    if (mounted) _toast('پرونده مادیان و همه سیکل‌های آن حذف شد.');
  }

  Future<void> _newCycle() async => _cycleEditor();

  Future<void> _cycleEditor({BreedingCycle? original}) async {
    final mare = _mare;
    if (mare == null) return;
    String method = original?.semenMethod ?? 'natural';
    int displayDays = original?.cycleDisplayDays ?? 21;
    final stallion = TextEditingController(text: original?.stallion ?? '');
    final notes = TextEditingController(text: original?.notes ?? '');
    DateTime? heatStart = original?.heatStart;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
          title: Text(original == null ? 'New breeding cycle · سیکل جدید' : 'Edit breeding cycle'),
          content: SizedBox(width: 480, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'نوع کشش / تلقیح'),
                items: const [
                  DropdownMenuItem(value: 'natural', child: Text('Natural cover · کشش طبیعی')),
                  DropdownMenuItem(value: 'fresh', child: Text('Fresh semen AI · تازه')),
                  DropdownMenuItem(value: 'cooled', child: Text('Cooled semen AI · سرد')),
                  DropdownMenuItem(value: 'frozen', child: Text('Frozen semen AI · فریز')),
                ],
                onChanged: (v) => update(() => method = v ?? method),
              ),
              const SizedBox(height: 14),
              _field('نام نریان / Stallion', stallion),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(heatStart == null ? 'ثبت شروع فحلی (اختیاری)'
                    : 'Heat start: ${_stamp(heatStart!)}'),
                onPressed: () async {
                  final chosen = await _chooseDateTime(heatStart ?? DateTime.now());
                  if (chosen != null) update(() => heatStart = chosen);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(initialValue:displayDays,
                decoration:const InputDecoration(labelText:'طول محور شماتیک (۱۸–۳۰ روز؛ پیش‌فرض ۲۱)'),
                items:[for(int d=18;d<=30;d++) DropdownMenuItem(value:d,child:Text('$d days'))],
                onChanged:(v)=>update(()=>displayDays=v??21)),
              const SizedBox(height:10),
              _field('یادداشت سیکل', notes, lines: 2),
              const SizedBox(height: 10),
              const Text('زمان‌های پیشنهادی فقط پس از ثبت سونو و معاینه محاسبه می‌شوند.',
                  style: TextStyle(color: _muted, fontSize: 12)),
            ]),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(original == null ? 'Create cycle' : 'Save cycle')),
          ],
        )),
      );
      if (accepted != true) return;
      if (original == null) {
        final cycle = BreedingCycle(
          id: newReproId(), createdAt: DateTime.now(), heatStart: heatStart,
          semenMethod: method, cycleDisplayDays:displayDays, stallion: stallion.text.trim(),
          notes: notes.text.trim(),
        );
        mare.cycles.add(cycle);
        _selectedCycleId = cycle.id;
      } else {
        original.heatStart = heatStart;
        original.semenMethod = method;
        original.cycleDisplayDays = displayDays;
        original.stallion = stallion.text.trim();
        original.notes = notes.text.trim();
      }
      if (await _persist() && mounted) {
        _toast(original == null ? 'سیکل جدید ایجاد شد.' : 'اطلاعات سیکل به‌روزرسانی شد.');
      }
    } finally {
      stallion.dispose(); notes.dispose();
    }
  }

  Future<void> _recordScanV34({BreedingEvent? original}) async {
    // Editing an old scan must update its *own* cycle and switch active view
    // to that cycle so the updated schematics and analysis are immediately visible.
    BreedingCycle? cycle = _cycle;
    if (original != null) {
      for (final previousCycle in _mare?.cycles ?? <BreedingCycle>[]) {
        if (previousCycle.events.any((event) => event.id == original.id)) {
          cycle = previousCycle;
          break;
        }
      }
    }
    if (cycle == null) return;
    try {
      final scan = await recordEquineScanV36(context, _store, original: original);
      if (scan == null) return;
      if (original == null) {
        cycle.events.add(scan);
      } else {
        final index = cycle.events.indexWhere((e) => e.id == original.id);
        if (index >= 0) {
          cycle.events[index] = scan;
        } else {
          cycle.events.add(scan);
        }
        _selectedCycleId = cycle.id;
      }
      if (await _persist() && mounted) {
        _toast(original == null
            ? 'سونوی راست/چپ ثبت شد و تحلیل سیکل به‌روزرسانی شد.'
            : 'سونوی انتخاب‌شده ویرایش شد و تحلیل سیکل به‌روزرسانی شد.');
      }
    } catch (e) {
      if (mounted) _toast('خطا در ثبت سونو: $e', error: true);
    }
  }

  Future<void> _addEvent({DateTime? initialAt,String initialType='note'}) async {
    if (initialType == 'ultrasound') {
      await _recordScanV34();
      return;
    }
    final cycle = _cycle;
    if (cycle == null) return;
    String type = initialType;
    var at = initialAt??DateTime.now();
    bool planned = initialAt!=null&&initialAt.isAfter(DateTime.now());
    String cervixStatus = 'not_assessed';
    String uterineFluid = 'not_assessed';
    String corpusLuteum = 'not_assessed';
    int? estrusScore;
    final left = TextEditingController(), right = TextEditingController();
    final edema = TextEditingController(), medicine = TextEditingController();
    final dose = TextEditingController(), route = TextEditingController();
    final semenBatch = TextEditingController(), details = TextEditingController();
    String photo = '';
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
          title: const Text('Add timeline event · ثبت رویداد'),
          content: SizedBox(width: 620, child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('فقط رویدادی که دامپزشک وارد می‌کند در تایم‌لاین ظاهر می‌شود.',
                style: TextStyle(color: _muted)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'نوع رویداد'),
                items: const [
                  DropdownMenuItem(value: 'heat_check', child: Text('Heat / estrus score · فحلی')),
                  DropdownMenuItem(value: 'hormone', child: Text('Hormone / تزریق گناد و هورمون')),
                  DropdownMenuItem(value: 'cover', child: Text('Natural cover / کشش طبیعی')),
                  DropdownMenuItem(value: 'insemination', child: Text('Insemination / تلقیح')),
                  DropdownMenuItem(value: 'semen', child: Text('Semen received / دریافت اسپرم')),
                  DropdownMenuItem(value: 'ovulation', child: Text('Ovulation confirmed / تخمک‌گذاری تأییدشده')),
                  DropdownMenuItem(value: 'recheck', child: Text('Recheck / معاینه مجدد')),
                  DropdownMenuItem(value: 'pregnancy', child: Text('Pregnancy ultrasound / سونو آبستنی')),
                  DropdownMenuItem(value: 'note', child: Text('Other clinical note / یادداشت')),
                ],
                onChanged: (v) => update(() => type = v ?? 'note'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text('تاریخ و ساعت: ${_stamp(at)}'),
                onPressed: () async {
                  final chosen = await _chooseDateTime(at);
                  if (chosen != null) update(() => at = chosen);
                },
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('برنامه‌ریزی‌شده توسط دامپزشک / Planned'),
                subtitle: const Text('خاموش = انجام‌شده و مستند؛ روشن = نوبت ثبت‌شده، نه انجام‌شده'),
                value: planned,
                onChanged: (v) => update(() => planned = v),
              ),
              if (type == 'ultrasound' || type == 'heat_check') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: estrusScore ?? -1,
                  decoration: const InputDecoration(
                    labelText: 'رفتار فحلی / Teasing response (0–4)',
                    helperText: 'مقیاس ثبت داخلی: ۰ = عدم پذیرش، ۴ = پذیرندگی قوی؛ مستقل از ادم رحم.',
                  ),
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: -1, child: Text('ارزیابی نشده')),
                    DropdownMenuItem(value: 0, child: Text('0 — No receptive signs')),
                    DropdownMenuItem(value: 1, child: Text('1 — Weak / equivocal')),
                    DropdownMenuItem(value: 2, child: Text('2 — Moderate')),
                    DropdownMenuItem(value: 3, child: Text('3 — Strong')),
                    DropdownMenuItem(value: 4, child: Text('4 — Very strong')),
                  ],
                  onChanged: (v) => update(() => estrusScore = v == -1 ? null : v),
                ),
              ],
              if (type == 'ultrasound') ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _field('Left follicle (mm)', left)),
                  const SizedBox(width: 10),
                  Expanded(child: _field('Right follicle (mm)', right)),
                ]),
                const SizedBox(height: 10),
                _field('Uterine edema score (0–5)', edema),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: cervixStatus,
                  decoration: const InputDecoration(labelText: 'Cervix / سرویکس'),
                  items: const [
                    DropdownMenuItem(value: 'not_assessed', child: Text('Not assessed')),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'relaxed', child: Text('Relaxed')),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  onChanged: (v) => update(() => cervixStatus = v ?? 'not_assessed'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: uterineFluid,
                  decoration: const InputDecoration(labelText: 'Uterine fluid / مایع رحم'),
                  items: const [
                    DropdownMenuItem(value: 'not_assessed', child: Text('Not assessed')),
                    DropdownMenuItem(value: 'absent', child: Text('Absent')),
                    DropdownMenuItem(value: 'present', child: Text('Present')),
                  ],
                  onChanged: (v) => update(() => uterineFluid = v ?? 'not_assessed'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: corpusLuteum,
                  decoration: const InputDecoration(labelText: 'Corpus luteum / جسم زرد'),
                  items: const [
                    DropdownMenuItem(value: 'not_assessed', child: Text('Not assessed')),
                    DropdownMenuItem(value: 'absent', child: Text('Absent')),
                    DropdownMenuItem(value: 'present', child: Text('Present')),
                  ],
                  onChanged: (v) => update(() => corpusLuteum = v ?? 'not_assessed'),
                ),
              ],
              if (type == 'hormone') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'هورمون ثبت‌شده'),
                  items: const [
                    DropdownMenuItem(value: 'hCG', child: Text('hCG')),
                    DropdownMenuItem(value: 'GnRH: deslorelin_injectable', child: Text('GnRH agonist — injectable deslorelin')),
                    DropdownMenuItem(value: 'GnRH: buserelin', child: Text('GnRH agonist — buserelin')),
                    DropdownMenuItem(value: 'GnRH: histrelin_injectable', child: Text('GnRH agonist — injectable histrelin')),
                    DropdownMenuItem(value: 'GnRH: gonadorelin', child: Text('GnRH — gonadorelin')),
                    DropdownMenuItem(value: 'PGF2α: dinoprost', child: Text('PGF₂α — dinoprost')),
                    DropdownMenuItem(value: 'PGF2α: cloprostenol', child: Text('PGF₂α — cloprostenol')),
                    DropdownMenuItem(value: 'Oxytocin', child: Text('Oxytocin')),
                    DropdownMenuItem(value: 'Altrenogest', child: Text('Altrenogest')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (v) => medicine.text = v ?? '',
                ),
                const SizedBox(height: 8),
                _field('نام دقیق دارو / اگر سایر', medicine),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _field('دوز تجویز شده (ثبت واقعی؛ نه پیشنهاد)', dose)),
                  const SizedBox(width: 10),
                  Expanded(child: _field('Route / مسیر مصرف', route)),
                ]),
              ],
              if (type == 'insemination' || type == 'cover' || type == 'semen') ...[
                const SizedBox(height: 10),
                _field('Stallion / Batch / Straw count / Motility', semenBatch),
                const SizedBox(height: 8),
                Text('Current cycle type: ${_methodLabel(cycle.semenMethod)}',
                    style: const TextStyle(color: _teal, fontSize: 12)),
              ],
              const SizedBox(height: 10),
              _field('یافته‌ها / سرویکس / ادم رحم / مایع / توضیحات', details, lines: 3),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final selected = await _store.selectImage();
                    if (selected != null) update(() => photo = selected);
                  } catch (e) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text('$e')));
                  }
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(photo.isEmpty ? 'Attach ultrasound / image'
                    : 'Image attached'),
              ),
            ]),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('انصراف')),
            FilledButton(onPressed: () {
              if (type == 'ultrasound') {
                final ls = reproDouble(left.text), rs = reproDouble(right.text);
                if ((ls == null && rs == null) ||
                    (ls != null && (ls <= 0 || ls > 100)) ||
                    (rs != null && (rs <= 0 || rs > 100))) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('حداقل یک قطر فولیکول معتبر (mm) ثبت کنید.')));
                  return;
                }
                final e = edema.text.trim();
                if (e.isNotEmpty &&
                    (int.tryParse(e) == null || int.parse(e) < 0 || int.parse(e) > 5)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('امتیاز ادم باید بین ۰ تا ۵ باشد.')));
                  return;
                }
              }
              if (type == 'heat_check' && estrusScore == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('برای ثبت رویداد فحلی، امتیاز رفتار (۰ تا ۴) را وارد کنید.')));
                return;
              }
              if (type == 'hormone' && medicine.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('نام گناد / هورمون را ثبت کنید.')));
                return;
              }
              Navigator.pop(ctx, true);
            }, child: const Text('Record event')),
          ],
        )),
      );
      if (accepted != true) return;
      final path = photo.isEmpty ? '' : await _store.importImage(photo);
      cycle.events.add(BreedingEvent(
        id: newReproId(), at: at, type: type,
        details: details.text.trim(), imagePath: path,
        leftFollicleMm: reproDouble(left.text),
        rightFollicleMm: reproDouble(right.text),
        edemaScore: int.tryParse(edema.text.trim()),
        estrusScore: estrusScore,
        cervixStatus: cervixStatus,
        uterineFluid: uterineFluid,
        corpusLuteum: corpusLuteum,
        medicine: medicine.text.trim(),
        administeredDose: dose.text.trim(),
        route: route.text.trim(), semenBatch: semenBatch.text.trim(),
        plannedByVet: planned,
      ));
      if (await _persist() && mounted) _toast('رویداد در تایم‌لاین ثبت شد.');
    } catch (e) {
      if (mounted) _toast('ثبت رویداد ناموفق بود: $e', error: true);
    } finally {
      for (final c in [left, right, edema, medicine, dose, route,
        semenBatch, details]) { c.dispose(); }
    }
  }

  Future<void> _deleteEvent(BreedingEvent event) async {
    final cycle = _cycle;
    if (cycle == null) return;
    final yes = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete timeline event?'),
        content: Text('${_eventLabel(event.type)} · ${_stamp(event.at)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف')),
        ],
      ));
    if (yes != true) return;
    cycle.events.removeWhere((e) => e.id == event.id);
    await _persist();
  }

  Widget _field(String label, TextEditingController controller,
      {int lines = 1}) => TextField(
        controller: controller, maxLines: lines,
        decoration: InputDecoration(labelText: label),
      );

  Widget _panel(String title, Widget body, {IconData? icon}) => Container(
        padding: const EdgeInsets.all(21),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDEE8EA)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, color: _teal), const SizedBox(width: 8)],
            Expanded(child: Text(title,
              style: const TextStyle(color: _ink,
                  fontWeight: FontWeight.w900, fontSize: 18))),
          ]),
          const SizedBox(height: 14), body,
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _paper,
        appBar: AppBar(
          backgroundColor: Colors.white, foregroundColor: _ink,
          title: const Text('Assistant Vet · مامایی اسب',
            style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            IconButton(tooltip: 'Open local records / Backup',
                onPressed: () async {
                  try { await _store.openDataFolder(); }
                  catch (e) { if (mounted) _toast('$e', error: true); }
                },
                icon: const Icon(Icons.folder_open_outlined)),
            IconButton(tooltip: 'Reload saved records', onPressed: _load,
                icon: const Icon(Icons.refresh_rounded)),
            const SizedBox(width: 12),
          ],
        ),
        body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, space) {
              if (space.maxWidth < 860) {
                return ListView(padding: const EdgeInsets.all(14), children: [
                  _marePicker(compact: true),
                  const SizedBox(height: 16),
                  _mainWorkspace(),
                ]);
              }
              return Row(children: [
                SizedBox(width: 284, child: _marePicker()),
                Expanded(child: SingleChildScrollView(
                  padding: const EdgeInsets.all(23),
                  child: _mainWorkspace(),
                )),
              ]);
            }),
      );

  Widget _marePicker({bool compact = false}) {
    final query = _search.text.trim().toLowerCase();
    final filtered = _mares.where((e) => e.name.toLowerCase().contains(query) ||
        e.reference.toLowerCase().contains(query)).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: compact ? BorderSide.none :
            const BorderSide(color: Color(0xFFDEE8EA))),
      ),
      child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min, children: [
          const Row(children: [
            Icon(Icons.pets_outlined, color: _teal),
            SizedBox(width: 7),
            Text('Mare registry', style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 17, color: _ink)),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _addOrEditMare(),
            icon: const Icon(Icons.add),
            label: const Text('Register horse'),
            style: FilledButton.styleFrom(backgroundColor: _teal,
              padding: const EdgeInsets.symmetric(vertical: 15)),
          ),
          const SizedBox(height: 14),
          TextField(controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
              hintText: 'Search horse name or ID'),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            const Padding(padding: EdgeInsets.all(16),
              child: Text('No mares found.', style: TextStyle(color: _muted))),
          for (final mare in filtered)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Material(color: _selectedMareId == mare.id
                  ? const Color(0xFFE9F8F4) : const Color(0xFFF7FAFA),
                borderRadius: BorderRadius.circular(13),
                child: InkWell(borderRadius: BorderRadius.circular(13),
                  onTap: () => setState(() {
                    _selectedMareId = mare.id;
                    _selectedCycleId = mare.cycles.isEmpty ? null : mare.cycles.last.id;
                  }),
                  child: Padding(padding: const EdgeInsets.all(11),
                    child: Row(children: [
                      _avatar(mare, radius: 23), const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(mare.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _ink,
                                fontWeight: FontWeight.w800)),
                          Text(mare.reference.isEmpty ? '${mare.cycles.length} cycles'
                              : mare.reference,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _muted, fontSize: 11)),
                        ])),
                      IconButton(
                        tooltip: 'حذف پرونده مادیان',
                        icon: const Icon(Icons.delete_outline, size: 19,
                          color: Color(0xFFAE5350)),
                        onPressed: () => _removeMare(mare),
                      ),
                    ])),
                  ),
                ),
              ),
        ])),
    );
  }

  Widget _avatar(MareRecord mare, {double radius = 32}) => CircleAvatar(
    radius: radius,
    backgroundColor: const Color(0xFFDAF2ED),
    backgroundImage: mare.imagePath.isNotEmpty && File(mare.imagePath).existsSync()
        ? FileImage(File(mare.imagePath)) : null,
    child: mare.imagePath.isEmpty || !File(mare.imagePath).existsSync()
      ? Icon(Icons.pets_outlined, size: radius * .9, color: _teal) : null,
  );

  Widget _mainWorkspace() {
    final mare = _mare;
    if (mare == null) return _emptyState();
    return ReproClinicalWorkspaceV35(
      mare: mare,
      cycle: _cycle,
      onEditMare: () => _addOrEditMare(original: mare),
      onNewCycle: _newCycle,
      onEditCycle: () { if (_cycle != null) _cycleEditor(original: _cycle); },
      onPickCycle: (id) => setState(() => _selectedCycleId = id),
      onRecordScan: _recordScanV34,
      onEditScan: (scan) { _recordScanV34(original: scan); },
      onEditLatestScan: () {
        final mare = _mare;
        if (mare == null) return;
        final exams = mare.cycles.expand((cycle) => cycle.events)
          .where((event) => event.type == 'ultrasound' && !event.plannedByVet)
          .toList()..sort((a, b) => b.at.compareTo(a.at));
        if (exams.isNotEmpty) {
          _recordScanV34(original: exams.first);
        }
      },
      onSave: () async { await _persist(); },
      onRecordEvent: (at, kind) => _addEvent(initialAt: at, initialType: kind),
    );
  }

  Widget _emptyState() => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 650),
    child: Padding(padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.pets_outlined, size: 84, color: _teal),
        const SizedBox(height: 14),
        const Text('Your mare registry starts here',
          style: TextStyle(color: _ink, fontSize: 24,
            fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        const Text('یک مادیان ثبت کن، تصویر اضافه کن و سپس سیکل، سونو، گناد و زمان تلقیح را به صورت واقعی وارد کن.',
          textAlign: TextAlign.center, style: TextStyle(color: _muted)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: () => _addOrEditMare(),
          icon: const Icon(Icons.add), label: const Text('Register first mare'),
          style: FilledButton.styleFrom(backgroundColor: _teal)),
      ]),
    ),
  ));
}
