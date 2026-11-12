import 'dart:io';
import 'package:flutter/material.dart';
import 'repro_local_store.dart';
import 'repro_clinical_cycle_v35.dart';
import 'repro_hormone_planner_v33.dart';
import 'repro_v34_widgets.dart';
import 'repro_jalali_v35.dart';
import 'repro_ovary_v36.dart';
import 'repro_timeline_v36.dart';

const _navy35 = Color(0xFF173B4B);
const _sea35 = Color(0xFF078B86);
const _light35 = Color(0xFFF4F9F8);
const _sub35 = Color(0xFF647F86);

String _method35(String method) => switch (method) {
  'natural' => 'کشش طبیعی', 'fresh' => 'Fresh',
  'cooled' => 'Cooled', 'frozen' => 'Frozen', _ => method,
};

String _scanDeltaSummary(BreedingEvent current, BreedingEvent? older) {
  if (older == null) return 'اولین سونوی ثبت‌شده';
  final parts = <String>[];
  if (current.dominantFollicleMm != null && older.dominantFollicleMm != null) {
    final diff = current.dominantFollicleMm! - older.dominantFollicleMm!;
    final sign = diff > 0 ? '+' : '';
    parts.add('ΔF $sign${diff.toStringAsFixed(0)} mm');
  }
  if (current.edemaScore != null && older.edemaScore != null) {
    final diffE = current.edemaScore! - older.edemaScore!;
    final signE = diffE > 0 ? '+' : '';
    parts.add('ΔUE $signE${ReproJalali.persianDigits(diffE)}');
  }
  return parts.isEmpty ? 'بدون تغییر عددی نسبت به سونوی قبل' : parts.join(' · ');
}

class ReproClinicalWorkspaceV35 extends StatelessWidget {
  final MareRecord mare;
  final BreedingCycle? cycle;
  final VoidCallback onEditMare, onNewCycle, onEditCycle, onRecordScan, onEditLatestScan;
  final ValueChanged<BreedingEvent> onEditScan;
  final ValueChanged<String?> onPickCycle;
  final Future<void> Function() onSave;
  final Future<void> Function(DateTime, String) onRecordEvent;

  const ReproClinicalWorkspaceV35({super.key, required this.mare,
    required this.cycle, required this.onEditMare, required this.onNewCycle,
    required this.onEditCycle, required this.onRecordScan, required this.onEditLatestScan,
    required this.onEditScan,
    required this.onPickCycle, required this.onSave, required this.onRecordEvent});

  Widget _card(String heading, Widget child, {IconData icon = Icons.circle_outlined}) =>
    Container(width: double.infinity, padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE9E8))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: _sea35, size: 21),
          const SizedBox(width: 8), Expanded(child: Text(heading,
            style: const TextStyle(fontWeight: FontWeight.w800,
              color: _navy35, fontSize: 17)))]),
        const SizedBox(height: 14), child,
      ]));

  Widget _pill(String value, {Color fill = const Color(0xFFE7F4F1)}) =>
    Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(30)),
      child: Text(value, style: const TextStyle(fontSize: 12,
        color: _navy35, fontWeight: FontWeight.w700)));

  @override
  Widget build(BuildContext context) {
    final c = cycle;
    final now = DateTime.now();
    // Show the mare's full exam history (including examinations stored in
    // older cycles), not just the most recent scan of the active cycle.
    final exams = mare.cycles
      .expand((breedingCycle) => breedingCycle.events)
      .where((e) => e.type == 'ultrasound' && !e.plannedByVet)
      .toList()..sort((a,b) => b.at.compareTo(a.at));
    final chronologicalAllScans = [...exams]..sort((a,b) => a.at.compareTo(b.at));
    final activeExams = c == null ? <BreedingEvent>[] : c.events
      .where((e) => e.type == 'ultrasound' && !e.plannedByVet && !e.at.isAfter(now))
      .toList()..sort((a,b) => b.at.compareTo(a.at));
    // Fallback to latest mare scan if active cycle has no scan yet so the
    // ovary/uterus schematic is never blank when the mare has saved scans.
    final exam = activeExams.isNotEmpty
      ? activeExams.first
      : (exams.isNotEmpty ? exams.first : null);
    final stage = c == null ? null : EquineCycleInterpreterV35.assess(c, now: now);
    final scenario = c == null ? null : ReproHormonePlanner.analyze(c, now: now);
    final baseline = c == null ? null : ReproHormonePlanner.analyze(c, hormone: 'none', now: now);
    final reference = c == null ? null : ReproHormonePlanner.educationalReference(c);
    final conditionalOv = scenario?.status == 'conditional'
      ? scenario!.windows.where((w) => w.category == 'ovulation').toList()
      : <ReproProjection>[];
    final scenarioPreview = conditionalOv.isNotEmpty ? conditionalOv.first : reference;
    final scenarioBreeding = c == null || scenarioPreview == null
      ? null
      : ReproHormonePlanner.methodBreedingWindow(c, scenarioPreview);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _header(context),
      const SizedBox(height: 13),
      _card('۱ · مادیان، نریان و سیکل', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 9, runSpacing: 9, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (mare.cycles.isNotEmpty) SizedBox(width: 230,
              child: DropdownButtonFormField<String>(
                value: c?.id, isExpanded: true,
                decoration: const InputDecoration(labelText: 'سیکل انتخاب‌شده', isDense: true),
                items: [for (final item in mare.cycles)
                  DropdownMenuItem(value: item.id, child: Text(
                    ReproJalali.date(item.createdAt),
                    overflow: TextOverflow.ellipsis))],
                onChanged: onPickCycle)),
            OutlinedButton.icon(onPressed: onNewCycle,
              icon: const Icon(Icons.add_circle_outline), label: const Text('سیکل جدید')),
            if (c != null) OutlinedButton.icon(onPressed: onEditCycle,
              icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش نریان / شروع فحلی')),
          ]),
        const SizedBox(height: 11),
        if (c == null)
          const Text('برای شروع، نام نریان و اطلاعات سیکل را ثبت کنید.',
            style: TextStyle(color: _sub35))
        else Wrap(spacing: 8, runSpacing: 8, children: [
          _pill('نریان: ${c.stallion.isEmpty ? 'ثبت نشده' : c.stallion}'),
          _pill('شروع فحلی: ${c.heatStart == null ? 'نامشخص' : ReproJalali.date(c.heatStart!)}'),
          _pill('روش تلقیح: ${_method35(c.semenMethod)}'),
          _pill('طول نمای سیکل: ${ReproJalali.persianDigits(c.cycleDisplayDays)} روز'),
        ]),
        const SizedBox(height: 7),
        const Text('نژاد صرفاً اطلاعات پرونده است؛ عدد ۲۱ روز پیش‌فرض قابل تنظیم است، نه قانون ثابت یک نژاد.',
          style: TextStyle(fontSize: 11, color: _sub35)),
      ]), icon: Icons.assignment_ind_outlined),
      if (c != null) ...[
        const SizedBox(height: 13),
        _card('۲ · سونوگرافی تخمدان و رحم', Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(onPressed: onRecordScan,
                  icon: const Icon(Icons.add), label: const Text('ثبت سونوی جدید'),
                  style: FilledButton.styleFrom(backgroundColor: _sea35)),
                if (exams.isNotEmpty) OutlinedButton.icon(
                  onPressed: onEditLatestScan,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('ویرایش آخرین سونو')),
                if (exam != null) _pill('سونوی نمایش‌داده‌شده در شماتیک: ${ReproJalali.stamp(exam.at)}'),
              ]),
            if (exams.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('تمام سونوهای مادیان (سونوی ۱ تا آخر) · برای بازکردن و ویرایش هر مورد روی آن بزنید',
                style: TextStyle(color: _navy35, fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 6),
              LayoutBuilder(builder: (context, limits) {
                final tileWidth = limits.maxWidth < 410 ? limits.maxWidth : 400.0;
                return Wrap(spacing: 7, runSpacing: 7, children: [
                  for (var i = 0; i < exams.length; i++)
                    Builder(builder: (_) {
                      final currentScan = exams[i];
                      final olderScan = (i + 1 < exams.length) ? exams[i + 1] : null;
                      final scanNumber = exams.length - i;
                      final clLabel = currentScan.clCount > 0
                        ? 'CL${ReproJalali.persianDigits(currentScan.clCount)}'
                        : (currentScan.leftCl == false && currentScan.rightCl == false ? 'CL0' : 'CL؟');
                      final chCount = [...currentScan.leftStructures, ...currentScan.rightStructures]
                        .where((s) => s.kind == 'ch').length;
                      return SizedBox(width: tileWidth, child: OutlinedButton.icon(
                        key: ValueKey('equine_scan_edit_${currentScan.id}'),
                        onPressed: () => onEditScan(currentScan),
                        icon: const Icon(Icons.edit_note_outlined, size: 18),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'سونو ${ReproJalali.persianDigits(scanNumber)}  ·  ${ReproJalali.stamp(currentScan.at)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'F${currentScan.dominantFollicleMm?.toStringAsFixed(0) ?? '—'} mm  ·  $clLabel${chCount > 0 ? ' · CH${ReproJalali.persianDigits(chCount)}' : ''}  ·  '
                                'UE${currentScan.edemaScore == null ? '—' : ReproJalali.persianDigits(currentScan.edemaScore!)}  ·  '
                                '${_scanDeltaSummary(currentScan, olderScan)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ));
                    }),
                ]);
              }),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(builder: (ctx, bounds) {
              final left = ReproOvaryMultiV36(name: 'تخمدان چپ',
                structures: exam?.leftStructures ?? const [],
                clAssessed: exam?.leftCl);
              final right = ReproOvaryMultiV36(name: 'تخمدان راست',
                structures: exam?.rightStructures ?? const [],
                clAssessed: exam?.rightCl);
              if (bounds.maxWidth < 580) return Column(children: [
                left, const SizedBox(height: 10), right]);
              return Row(crossAxisAlignment: CrossAxisAlignment.start,
                children: [Expanded(child: left), const SizedBox(width: 10),
                  Expanded(child: right)]);
            }),
            const SizedBox(height: 10),
            UterusEdemaDiagramV35(edema: exam?.edemaScore),
            if (exam != null) ...[
              const SizedBox(height: 9),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _pill('پذیرش نریان (۰–۴): ${exam.estrusScore == null ? 'ارزیابی نشده' : ReproJalali.persianDigits('${exam.estrusScore}/4')}'),
                _pill('سرویکس: ${exam.cervixStatus}'),
                _pill('مایع رحم: ${exam.uterineFluid}'),
              ]),
            ],
            const SizedBox(height: 6),
            const Text('فولیکول آبی، CL زرد، CH نارنجی. CH1–CH3 فقط برچسب یافته دامپزشک است؛ وقوع تخمک‌گذاری را ثابت نمی‌کند.',
              style: TextStyle(fontSize: 11, color: _sub35)),
          ]), icon: Icons.monitor_heart_outlined),
        const SizedBox(height: 13),
        _card('۳ · ارزیابی بالینی و زمان معاینه بعدی', Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(stage!.phase, style: const TextStyle(color: _sea35,
              fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 9),
            if (stage.heatDayMin != null)
              Container(width: double.infinity, padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(color: const Color(0xFFE4F4ED),
                  borderRadius: BorderRadius.circular(13)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.heatStart != null
                      ? 'روز واقعی فحلی · بر اساس تاریخ شروع فحلی ثبت‌شده'
                      : 'بازهٔ احتمالی روز فحلی · تخمین عملیاتی از سونو (نه روز قطعی سیکل)',
                    style: const TextStyle(fontSize: 11, color: _navy35,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(stage.heatDayMin == stage.heatDayMax
                    ? 'روز ${ReproJalali.persianDigits(stage.heatDayMin!)}'
                    : 'روز ${ReproJalali.persianDigits(stage.heatDayMin!)} تا ${ReproJalali.persianDigits(stage.heatDayMax!)}',
                    style: const TextStyle(fontSize: 25, color: _sea35,
                      fontWeight: FontWeight.w900)),
                ])),
            const SizedBox(height: 9),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (stage.cycleDay != null)
                _pill('روز واقعی پس از تخمک‌گذاری تأییدشده: D${ReproJalali.persianDigits(stage.cycleDay!)}')
              else
                _pill('روز واقعی D: تخمک‌گذاری (D0) ثبت نشده', fill: const Color(0xFFF1F5F7)),
              _pill('وضعیت شواهد: ${stage.confidence}'),
              if (stage.cycleDay == null && stage.heatDayMin == null)
                _pill('نزدیک‌ترین فاز: ${stage.phase}'),
            ]),
            const SizedBox(height: 9),
            Text(stage.basis, style: const TextStyle(color: _navy35, height: 1.5)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.event_available_outlined, color: _sea35, size: 19),
              const SizedBox(width: 6),
              Expanded(child: Text(stage.recheckAt == null
                ? 'گام بعدی: ثبت سونوی فعلی'
                : 'سونوی بعدی (پیشنهادی · ${_method35(c.semenMethod)}): ${ReproJalali.stamp(stage.recheckAt!)}',
                style: const TextStyle(color: _sea35, fontWeight: FontWeight.bold))),
            ]),
            if (stage.nextWindowStart != null && stage.nextWindowEnd != null)
              Padding(padding: const EdgeInsets.only(top: 7), child: Text(
                'پایش تخمک‌گذاری سیکل بعد: ${ReproJalali.date(stage.nextWindowStart!)} تا ${ReproJalali.date(stage.nextWindowEnd!)}',
                style: const TextStyle(color: _sub35, fontSize: 12))),
            if (c.scenarioHormone != 'none') Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Builder(builder: (_) {
                return Text(scenarioPreview == null
                  ? 'سناریوی ${c.scenarioHormone}: ساعت پاسخ قابل‌اتکا تعریف نشده؛ ${scenario!.headline}'
                  : '${conditionalOv.isEmpty ? 'مرجع آموزشی مشروط' : 'سناریوی بالینی مشروط'} با ${c.scenarioHormone}: '
                    '${ReproJalali.stamp(scenarioPreview.start)} تا ${ReproJalali.stamp(scenarioPreview.end)}',
                  style: const TextStyle(color: Color(0xFF744A9C),
                    fontWeight: FontWeight.bold, fontSize: 12));
              })),
            if (stage.warnings.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ExpansionTile(dense: true, initiallyExpanded: false,
                tilePadding: EdgeInsets.zero,
                title: Text('نکات نیازمند بررسی (${stage.warnings.length})',
                  style: const TextStyle(color: _navy35, fontSize: 12)),
                children: [for (final warning in stage.warnings)
                  ListTile(dense: true, title: Text(warning,
                    style: const TextStyle(fontSize: 12)))])),
          ]), icon: Icons.fact_check_outlined),
        const SizedBox(height: 13),
        _card('۴ · روش تلقیح و سناریوی هورمونی', Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('روش موردنظر دامپزشک',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 7, children: [
              for (final method in ['natural', 'fresh', 'cooled', 'frozen'])
                ChoiceChip(label: Text(_method35(method)),
                  selected: c.semenMethod == method,
                  onSelected: (_) async { c.semenMethod = method; await onSave(); }),
            ]),
            const SizedBox(height: 12),
            const Text('اثر هورمون فقط شبیه‌سازی است؛ هیچ تزریقی ثبت نمی‌شود.',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 9),
            Wrap(spacing: 9, runSpacing: 9, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 210, child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: ['none','hcg','gnrh','pg','sequence'].contains(c.scenarioHormone)
                    ? c.scenarioHormone : 'none',
                  decoration: const InputDecoration(labelText: 'سناریوی فرضی'),
                  items: const [
                    DropdownMenuItem(value: 'none', child: Text('بدون هورمون')),
                    DropdownMenuItem(value: 'hcg', child: Text('hCG')),
                    DropdownMenuItem(value: 'gnrh', child: Text('GnRH / آگونیست')),
                    DropdownMenuItem(value: 'pg', child: Text('PGF₂α / بررسی لوتئولیز')),
                    DropdownMenuItem(value: 'sequence', child: Text('PG → بررسی القا (مرحله‌ای)')),
                  ],
                  onChanged: (value) async {
                    final nextHormone = value ?? 'none';
                    c.scenarioHormone = nextHormone;
                    if (nextHormone == 'none') {
                      c.scenarioInjectionAt = null;
                    } else {
                      c.scenarioInjectionAt ??= DateTime.now();
                    }
                    await onSave();
                  })),
                SizedBox(width: 200, child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: ['unknown', 'excluded', 'suspected', 'confirmed'].contains(c.pregnancyStatus)
                    ? c.pregnancyStatus : 'unknown',
                  decoration: const InputDecoration(labelText: 'وضعیت آبستنی'),
                  items: const [
                    DropdownMenuItem(value: 'unknown', child: Text('نامشخص')),
                    DropdownMenuItem(value: 'excluded', child: Text('توسط دامپزشک رد شده')),
                    DropdownMenuItem(value: 'suspected', child: Text('مشکوک')),
                    DropdownMenuItem(value: 'confirmed', child: Text('تأییدشده')),
                  ],
                  onChanged: (value) async {
                    c.pregnancyStatus = value ?? 'unknown'; await onSave();
                  })),
              ]),
            if (c.scenarioHormone == 'gnrh') Padding(
              padding: const EdgeInsets.only(top: 9),
              child: SizedBox(width: 285, child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: ['unspecified','deslorelin_injectable','histrelin_injectable',
                    'buserelin','gonadorelin'].contains(c.scenarioProduct)
                  ? c.scenarioProduct : 'unspecified',
                decoration: const InputDecoration(labelText: 'فرآورده GnRH'),
                items: const [
                  DropdownMenuItem(value: 'unspecified', child: Text('نامشخص')),
                  DropdownMenuItem(value: 'deslorelin_injectable', child: Text('Deslorelin injectable')),
                  DropdownMenuItem(value: 'histrelin_injectable', child: Text('Histrelin injectable')),
                  DropdownMenuItem(value: 'buserelin', child: Text('Buserelin')),
                  DropdownMenuItem(value: 'gonadorelin', child: Text('Gonadorelin')),
                ], onChanged: (v) async { c.scenarioProduct = v ?? 'unspecified'; await onSave(); }))),
            if (c.scenarioHormone != 'none') ...[
              const SizedBox(height: 9),
              OutlinedButton.icon(icon: const Icon(Icons.edit_calendar_outlined),
                label: Text('زمان فرضی مداخله: ${ReproJalali.stamp(c.scenarioInjectionAt ?? DateTime.now())}'),
                onPressed: () async {
                  final picked = await ReproJalali.pickDateTime(context,
                    c.scenarioInjectionAt ?? DateTime.now());
                  if (picked != null) { c.scenarioInjectionAt = picked; await onSave(); }
                }),
            ],
            const SizedBox(height: 12),
            Container(width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF1F5FC),
                borderRadius: BorderRadius.circular(13)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مقایسه زمان‌بندی (${_method35(c.semenMethod)}) · بدون هورمون / با هورمون',
                  style: const TextStyle(fontWeight: FontWeight.w900, color: _navy35)),
                const SizedBox(height: 7),
                Builder(builder: (context) {
                  final baseOv = baseline!.windows.where((w) => w.category == 'ovulation').toList();
                  final baseBreed = baseline.windows.where((w) => w.category == 'breeding').toList();
                  if (baseOv.isEmpty) {
                    return const Text('بدون هورمون: هنوز پنجره قابل اتکای تخمک‌گذاری نداریم؛ سونوی پیگیری ملاک است.',
                      style: TextStyle(color: _navy35, fontSize: 12));
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('بدون هورمون (پایش تخمک‌گذاری): ${ReproJalali.stamp(baseOv.first.start)} تا ${ReproJalali.stamp(baseOv.first.end)}',
                      style: const TextStyle(color: _navy35, fontSize: 12)),
                    if (baseBreed.isNotEmpty)
                      Text('بدون هورمون (${baseBreed.first.label}): ${ReproJalali.stamp(baseBreed.first.start)} تا ${ReproJalali.stamp(baseBreed.first.end)}',
                        style: const TextStyle(color: _sea35, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]);
                }),
                const SizedBox(height: 6),
                Builder(builder: (context) {
                  if (c.scenarioHormone == 'none') {
                    return const Text('هورمونی انتخاب نشده؛ تاریخ‌های طبیعی بدون تغییر می‌مانند.',
                      style: TextStyle(color: _navy35, fontSize: 12));
                  }
                  if (scenarioPreview == null) {
                    return Text('با ${c.scenarioHormone}: بازهٔ ساعت‌دار معتبر تعریف نشده؛ ${scenario!.headline}',
                      style: const TextStyle(color: Color(0xFF744A9C), fontSize: 12,
                        fontWeight: FontWeight.bold));
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('با ${c.scenarioHormone} · ${conditionalOv.isNotEmpty ? 'مشروط به ارزیابی بالینی' : 'صرفاً مرجع پژوهشی و غیرقابل‌اجرا'}: '
                      '${ReproJalali.stamp(scenarioPreview.start)} تا ${ReproJalali.stamp(scenarioPreview.end)}',
                      style: const TextStyle(color: Color(0xFF744A9C), fontSize: 12,
                        fontWeight: FontWeight.bold)),
                    if (scenarioBreeding != null)
                      Text('پنجرهٔ هماهنگی ${_method35(c.semenMethod)} در سناریوی هورمونی: '
                        '${ReproJalali.stamp(scenarioBreeding.start)} تا ${ReproJalali.stamp(scenarioBreeding.end)}',
                        style: const TextStyle(color: Color(0xFF5B3582), fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  ]);
                }),
                const SizedBox(height: 6),
                const Text('این مقایسه یک پیش‌نمایش مشروط است؛ تزریق، تخمک‌گذاری یا تغییر سیکل واقعی را ثبت نمی‌کند.',
                  style: TextStyle(fontSize: 10, color: _sub35)),
              ])),
            const SizedBox(height: 12),
            Container(width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _light35,
                borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(scenario!.headline, style: const TextStyle(
                  fontWeight: FontWeight.w900, color: _navy35)),
                const SizedBox(height: 5),
                Text(scenario.explanation, style: const TextStyle(height: 1.45)),
                if (reference != null && conditionalOv.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text('مرجع علمی مشروط: ${reference.label}',
                    style: const TextStyle(color: Color(0xFF744A9C), fontSize: 12,
                      fontWeight: FontWeight.w800)),
                  Text('${ReproJalali.stamp(reference.start)} تا ${ReproJalali.stamp(reference.end)}',
                    style: const TextStyle(color: Color(0xFF744A9C), fontSize: 13,
                      fontWeight: FontWeight.w800)),
                  const Text('فقط الگوی گزارش‌شده در شرایط واجد صلاحیت است؛ '
                    'برای این مادیان پیش‌بینی تأییدشده یا اجازه تزریق نیست.',
                    style: TextStyle(color: Color(0xFF805287), fontSize: 11)),
                ],
                for (final w in scenario.windows)
                  Padding(padding: const EdgeInsets.only(top: 6),
                    child: Text('◇ ${w.label}: ${ReproJalali.stamp(w.start)} تا ${ReproJalali.stamp(w.end)}',
                      style: const TextStyle(color: _sea35, fontSize: 12))),
                for (final warning in scenario.warnings.take(3))
                  Padding(padding: const EdgeInsets.only(top: 5),
                    child: Text('• $warning', style: const TextStyle(
                      color: Color(0xFF956126), fontSize: 12))),
              ])),
          ]), icon: Icons.science_outlined),
        const SizedBox(height: 13),
        _card('۵ · تایم‌لاین مادیان (روز صفر = تخمک‌گذاری)', Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            EquineCycleRailV36(key: ValueKey('equine_rail_${c.id}'),
              cycle: c, assessment: stage,
              scenario: scenario, onRecordEvent: onRecordEvent,
              allMareScans: chronologicalAllScans,
              onEditScan: onEditScan),
          ]), icon: Icons.timeline_outlined),
        const SizedBox(height: 12),
        ExpansionTile(title: const Text('سوابق و بانک علمی مامایی اسب'),
          subtitle: const Text('اختیاری؛ برای صفحه اصلی شلوغ نشود'),
          children: [
            for (final event in ([...c.events]..sort((a,b) => b.at.compareTo(a.at))).take(7))
              ListTile(dense: true,
                leading: const Icon(Icons.event_note_outlined, color: _sea35),
                title: Text('${event.type} · ${ReproJalali.stamp(event.at)}'),
                subtitle: Text(event.plannedByVet ? 'برنامه‌ریزی‌شده' : 'ثبت واقعی')),
            Padding(padding: const EdgeInsets.all(12),
              child: EquineWordSearchV34(summary:
                'Mare: ${mare.name}; Breed: ${mare.breed}; '
                'Ultrasound: ${exam?.dominantFollicleMm ?? 'unknown'} mm; '
                'Edema: ${exam?.edemaScore ?? 'unknown'}; Stage: ${stage.phase}; '
                'Method: ${c.semenMethod}.')),
          ]),
        const SizedBox(height: 12),
        const Text('تصمیم نهایی درباره تلقیح، هورمون و زمان معاینه با دامپزشک است. داده‌های گذشته حذف یا بازنویسی نمی‌شوند.',
          style: TextStyle(color: _sub35, fontSize: 11)),
      ],
    ]);
  }

  Widget _header(BuildContext context) {
    final path = mare.imagePath;
    final exists = path.isNotEmpty && File(path).existsSync();
    return Container(width: double.infinity, padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [_navy35, Color(0xFF087A80)])),
      child: Wrap(spacing: 16, runSpacing: 9, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CircleAvatar(radius: 36,
            backgroundImage: exists ? FileImage(File(path)) : null,
            backgroundColor: const Color(0xFFDAF2ED),
            child: exists ? null : const Icon(Icons.pets, color: _sea35, size: 30)),
          Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mare.name, style: const TextStyle(color: Colors.white,
                fontSize: 23, fontWeight: FontWeight.bold)),
              Text('${mare.breed.isEmpty ? 'نژاد نامشخص' : mare.breed}  ·  '
                '${mare.age.isEmpty ? 'سن نامشخص' : '${mare.age} سال'}  ·  '
                '${mare.owner.isEmpty ? 'مالک نامشخص' : mare.owner}',
                style: const TextStyle(color: Color(0xFFDAEDEC), fontSize: 12)),
            ]),
          OutlinedButton.icon(onPressed: onEditMare,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70)),
            icon: const Icon(Icons.edit_outlined), label: const Text('ویرایش / تصویر')),
        ]));
  }
}
