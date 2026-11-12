import 'package:flutter/material.dart';
import 'repro_local_store.dart';
import 'repro_clinical_cycle_v35.dart';
import 'repro_hormone_planner_v33.dart';
import 'repro_jalali_v35.dart';

const _navy = Color(0xFF244858);
const _green = Color(0xFFDBF2E3);
const _blue = Color(0xFFDDECFB);
const _orange = Color(0xFFFFE5BD);
const _purple = Color(0xFFE8DBFA);
const _teal = Color(0xFF008B81);

String _methodShortFa(String method) => switch (method) {
  'frozen' => 'Frozen',
  'cooled' => 'Cooled',
  'fresh' => 'Fresh',
  _ => 'طبیعی',
};

/// Editable paging of the teaching cycle and a *separate* unlimited, dated
/// clinical rail. Proposed events are visually distinct from confirmed scans.
class EquineCycleRailV36 extends StatefulWidget {
  final BreedingCycle cycle;
  final EquineCycleAssessmentV35 assessment;
  final ReproScenarioResult scenario;
  final Future<void> Function(DateTime, String) onRecordEvent;
  final List<BreedingEvent>? allMareScans;
  final ValueChanged<BreedingEvent>? onEditScan;

  const EquineCycleRailV36({
    super.key,
    required this.cycle,
    required this.assessment,
    required this.scenario,
    required this.onRecordEvent,
    this.allMareScans,
    this.onEditScan,
  });

  @override
  State<EquineCycleRailV36> createState() => _EquineCycleRailV36State();
}

class _EquineCycleRailV36State extends State<EquineCycleRailV36> {
  int _phasePage = 0;
  int _calendarShift = 0;
  static const int pageSize = 7;

  DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
  bool _covers(DateTime date, ReproProjection window) =>
    !date.isBefore(_date(window.start)) && !date.isAfter(_date(window.end));

  Widget _legend(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: const TextStyle(fontSize: 11, color: _navy)),
  );

  Widget _navButton(String label, IconData icon, VoidCallback? onPressed, String key) =>
    OutlinedButton.icon(key: Key(key), onPressed: onPressed,
      icon: Icon(icon, size: 17), label: Text(label),
      style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact));

  Widget _phaseStrip(int count) {
    final begin = _phasePage * pageSize;
    final end = (begin + pageSize - 1) > count ? count : begin + pageSize - 1;
    final lastPage = count ~/ pageSize;
    final cutoff = (count * 14 / 21).round();
    final startEstrus = (count * 16 / 21).round();
    Color bg(int d) => d == 0 || d == count ? _orange :
      d <= cutoff ? _green : d < startEstrus ? const Color(0xFFFFF0D3) : _blue;
    String phase(int d) => d == 0 || d == count ? 'Ov' :
      d <= cutoff ? 'دای‌استروس' : d < startEstrus ? 'گذار' : 'فحلی';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('نقشه فازهای سیکل · مرجع آموزشی (روز صفر = تخمک‌گذاری)',
        style: TextStyle(color: _navy, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      Wrap(spacing: 8, runSpacing: 5, crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _navButton('روزهای قبل', Icons.chevron_right,
            _phasePage > 0 ? () => setState(() => _phasePage--) : null, 'phase_prev'),
          _navButton('روزهای بعد', Icons.chevron_left,
            _phasePage < lastPage ? () => setState(() => _phasePage++) : null, 'phase_next'),
          Text('D${ReproJalali.persianDigits(begin)} تا D${ReproJalali.persianDigits(end)}',
            style: const TextStyle(color: _navy, fontWeight: FontWeight.bold)),
        ]),
      const SizedBox(height: 7),
      LayoutBuilder(builder: (_, bounds) => SizedBox(
        width: bounds.maxWidth,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(children: [for (var d = begin; d <= end; d++)
            Container(width: 105, margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(color: bg(d), borderRadius: BorderRadius.circular(7)),
              child: Column(children: [
                Text(phase(d), style: const TextStyle(fontSize: 11, color: _navy,
                  fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('D${ReproJalali.persianDigits(d)}',
                  style: TextStyle(color: widget.assessment.cycleDay == d ? _teal : _navy,
                    fontWeight: FontWeight.w800)),
                if (widget.assessment.cycleDay == d)
                  const Icon(Icons.arrow_drop_up, color: _teal, size: 14),
              ])),
          ])),
      )),
      const SizedBox(height: 7),
      Wrap(spacing: 6, runSpacing: 5, children: [
        _legend('دای‌استروس', _green), _legend('فحلی', _blue),
        _legend('تخمک‌گذاری', _orange),
      ]),
      const SizedBox(height: 4),
      Text(widget.assessment.anchorOvulation == null
        ? 'D0 در این مادیان تأیید نشده؛ این نوار صرفاً مرجع است و تاریخ‌های واقعی در پایین نشان داده می‌شوند.'
        : 'مبدأ ثبت‌شده D0: ${ReproJalali.date(widget.assessment.anchorOvulation!)}',
        style: const TextStyle(fontSize: 11, color: Color(0xFF657E89))),
    ]);
  }

  Widget _clinicalRail(DateTime now, List<BreedingEvent> scans,
      ReproScenarioResult natural) {
    final latest = scans.isEmpty ? null : scans.last;
    final base = _date(latest?.at ?? now).subtract(const Duration(days: 3));
    final start = base.add(Duration(days: _calendarShift));
    final end = start.add(const Duration(days: pageSize - 1));
    final naturalWindows = natural.windows.where((w) => w.category == 'ovulation').toList();
    final naturalBreeding = natural.windows.where((w) => w.category == 'breeding').toList();
    final eligibleWindows = widget.scenario.status == 'conditional'
      ? widget.scenario.windows.where((w) => w.category == 'ovulation').toList()
      : <ReproProjection>[];
    final reference = ReproHormonePlanner.educationalReference(widget.cycle);
    final scenarioWindows = eligibleWindows.isNotEmpty ? eligibleWindows :
      reference == null ? <ReproProjection>[] : <ReproProjection>[reference];
    final scenarioBreeding = scenarioWindows.isEmpty
      ? <ReproProjection>[]
      : <ReproProjection>[ReproHormonePlanner.methodBreedingWindow(widget.cycle, scenarioWindows.first)];
    final hasClinicalScenario = eligibleWindows.isNotEmpty;
    final scenarioChecks = widget.cycle.scenarioHormone == 'none'
      ? <ReproProjection>[]
      : widget.scenario.windows.where((w) => w.category == 'recheck').toList();
    final goToWindows = scenarioWindows.isNotEmpty ? scenarioWindows : scenarioChecks;
    final methodTag = _methodShortFa(widget.cycle.semenMethod);

    String follicleText(BreedingEvent e) => e.dominantFollicleMm == null
      ? 'F—' : 'F${e.dominantFollicleMm!.toStringAsFixed(0)} mm';
    String eventName(BreedingEvent e) => switch (e.type) {
      'ovulation' => 'Ov تأیید', 'hormone' => 'هورمون ثبت‌شده',
      'insemination' => 'تلقیح', 'cover' => 'کشش',
      'recheck' => 'معاینه', _ => 'رویداد',
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('تقویم پرونده (${ReproHormonePlanner.methodNameFa(widget.cycle.semenMethod)}) · سونوهای واقعی و سناریوهای احتمالی',
        style: const TextStyle(color: _navy, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Wrap(spacing: 7, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _navButton('هفته قبل', Icons.chevron_right,
          () => setState(() => _calendarShift -= pageSize), 'calendar_prev'),
        _navButton('هفته بعد', Icons.chevron_left,
          () => setState(() => _calendarShift += pageSize), 'calendar_next'),
        _navButton('بازگشت به امروز', Icons.today_outlined,
          () => setState(() => _calendarShift = _date(now).difference(_date(latest?.at ?? now)).inDays),
          'calendar_today'),
        if (goToWindows.isNotEmpty) _navButton('رفتن به سناریوی هورمون',
          Icons.science_outlined,
          () => setState(() => _calendarShift =
            _date(goToWindows.first.start).difference(base).inDays),
          'calendar_scenario'),
        if (scans.length > 1) _navButton('رفتن به سونو ۱',
          Icons.history_outlined,
          () => setState(() => _calendarShift =
            _date(scans.first.at).difference(base).inDays),
          'calendar_first_scan'),
      ]),
      const SizedBox(height: 5),
      Text('${ReproJalali.date(start)} تا ${ReproJalali.date(end)} · تقویم بدون محدودیت رفت‌وبرگشت',
        style: const TextStyle(fontSize: 11, color: Color(0xFF657E89))),
      const SizedBox(height: 9),
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < pageSize; i++)
            Builder(builder: (_) {
              final date = start.add(Duration(days: i));
              final dayEvents = widget.cycle.events.where((e) =>
                _sameDay(e.at, date) && (e.plannedByVet || !e.at.isAfter(now))).toList()
                ..sort((a,b) => a.at.compareTo(b.at));
              final dayScans = scans.where((e) => _sameDay(e.at, date)).toList();
              final scan = dayScans.isEmpty ? null : dayScans.last;
              final scanIndex = scan == null ? 0 : scans.indexWhere((e) => e.id == scan.id) + 1;
              final prevScan = (scanIndex > 1 && scanIndex - 2 < scans.length)
                ? scans[scanIndex - 2]
                : null;
              final diffMm = (scan?.dominantFollicleMm != null && prevScan?.dominantFollicleMm != null)
                ? (scan!.dominantFollicleMm! - prevScan!.dominantFollicleMm!)
                : null;
              final events = dayEvents.where((e) => e.type != 'ultrasound').toList();
              final recheck = widget.assessment.recheckAt != null &&
                _sameDay(widget.assessment.recheckAt!, date);
              final inNatural = naturalWindows.any((w) => _covers(date,w));
              final inNaturalBreed = naturalBreeding.any((w) => _covers(date,w));
              final inScenario = scenarioWindows.any((w) => _covers(date,w));
              final inScenarioBreed = scenarioBreeding.any((w) => _covers(date,w));
              final inScenarioRecheck = scenarioChecks.any((w) => _covers(date,w));
              final isToday = _sameDay(now,date);
              final heatDay = widget.cycle.heatStart == null ? null :
                date.difference(_date(widget.cycle.heatStart!)).inDays + 1;
              final tint = scan != null ? _blue : inScenario ? _purple :
                inScenarioRecheck || recheck ? _orange : inNatural ? const Color(0xFFEAF3FA) :
                const Color(0xFFF4F8F9);
              return Container(
                width: 132,
                constraints: const BoxConstraints(minHeight: 210),
                margin: const EdgeInsets.only(right: 5),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isToday ? _teal : const Color(0xFFDCE7E9),
                    width: isToday ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(isToday ? 'امروز' : 'تقویم',
                      style: const TextStyle(fontSize: 11, color: _navy, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(ReproJalali.date(date), style: const TextStyle(fontSize: 10, color: _navy)),
                    const Divider(height: 13),
                    if (scan != null) ...[
                      InkWell(
                        onTap: widget.onEditScan == null ? null : () => widget.onEditScan!(scan),
                        child: Text('سونو ${ReproJalali.persianDigits(scanIndex)} ✎',
                          style: const TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w900)),
                      ),
                      Text(follicleText(scan), style: const TextStyle(fontSize: 11, color: _navy)),
                      if (diffMm != null)
                        Text('ΔF ${diffMm >= 0 ? '+' : ''}${diffMm.toStringAsFixed(0)} mm',
                          style: const TextStyle(fontSize: 10, color: _teal, fontWeight: FontWeight.w700)),
                      Text('UE${scan.edemaScore == null ? '—' : ReproJalali.persianDigits(scan.edemaScore!)}',
                        style: const TextStyle(fontSize: 11, color: _navy)),
                      if (scan.clCount > 0)
                        Text('CL${ReproJalali.persianDigits(scan.clCount)} ثبت شد',
                          style: const TextStyle(fontSize: 10, color: _navy)),
                    ],
                    if (heatDay != null && heatDay >= 1 && heatDay <= 14)
                      Text('فحلی روز ${ReproJalali.persianDigits(heatDay)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: _teal)),
                    if (events.isNotEmpty)
                      Text(eventName(events.first),
                        maxLines: 1, style: const TextStyle(fontSize: 10, color: _navy)),
                    if (recheck)
                      const Text('سونوی پیشنهادی',
                        style: TextStyle(color: Color(0xFF94672B), fontSize: 10)),
                    if (inNatural)
                      const Text('پایش طبیعی ≈',
                        style: TextStyle(color: Color(0xFF38638D), fontSize: 10)),
                    if (inNaturalBreed && widget.cycle.scenarioHormone == 'none')
                      Text('تلقیح $methodTag · طبیعی',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _teal, fontSize: 10, fontWeight: FontWeight.w700)),
                    if (inScenario)
                      Text(hasClinicalScenario ? 'سناریوی مشروط ◇' : 'مرجع علمی* ◇',
                        style: const TextStyle(color: Color(0xFF6939A5), fontSize: 10)),
                    if (inScenarioBreed && widget.cycle.scenarioHormone != 'none')
                      Text('تلقیح $methodTag · هورمون',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF5B3582), fontSize: 10, fontWeight: FontWeight.w700)),
                    if (inScenarioRecheck)
                      const Text('بازبینی هورمون ○',
                        style: TextStyle(color: Color(0xFF94672B), fontSize: 10)),
                  ],
                ),
              );
            }),
        ])),
      const SizedBox(height: 8),
      Wrap(spacing: 7, runSpacing: 5, children: [
        _legend('آبی: سونوی ثبت‌شده', _blue),
        _legend('بنفش: پنجره هورمونی/مرجع مشروط*', _purple),
        _legend('نارنجی: سونوی پیشنهادی / بازبینی هورمون', _orange),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final scans = widget.allMareScans != null && widget.allMareScans!.isNotEmpty
      ? ([...widget.allMareScans!.where((e) => !e.plannedByVet && !e.at.isAfter(now))]
          ..sort((a, b) => a.at.compareTo(b.at)))
      : (widget.cycle.events.where((e) => e.type == 'ultrasound' &&
          !e.plannedByVet && !e.at.isAfter(now)).toList()
          ..sort((a, b) => a.at.compareTo(b.at)));
    final natural = ReproHormonePlanner.analyze(widget.cycle, hormone: 'none', now: now);
    final naturalOv = natural.windows.where((w) => w.category == 'ovulation').toList();
    final naturalBreed = natural.windows.where((w) => w.category == 'breeding').toList();
    final eligibleOv = widget.scenario.status == 'conditional'
      ? widget.scenario.windows.where((w) => w.category == 'ovulation').toList()
      : <ReproProjection>[];
    final reference = ReproHormonePlanner.educationalReference(widget.cycle);
    final scenarioOv = eligibleOv.isNotEmpty ? eligibleOv :
      reference == null ? <ReproProjection>[] : <ReproProjection>[reference];
    final scenarioBreed = scenarioOv.isEmpty
      ? <ReproProjection>[]
      : <ReproProjection>[ReproHormonePlanner.methodBreedingWindow(widget.cycle, scenarioOv.first)];
    String dates(ReproProjection w) => '${ReproJalali.stamp(w.start)} تا ${ReproJalali.stamp(w.end)}';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _phaseStrip(widget.cycle.cycleDisplayDays),
      const SizedBox(height: 15),
      _clinicalRail(now, scans, natural),
      const SizedBox(height: 10),
      Container(width: double.infinity, padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(color: const Color(0xFFF4F8F9),
          borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('مقایسه زمان‌بندی (${ReproHormonePlanner.methodNameFa(widget.cycle.semenMethod)} · فقط پیش‌نمایش)',
            style: const TextStyle(color: _navy, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(naturalOv.isEmpty ? 'بدون هورمون: موعد سونوی مجدد مهم‌تر از تخمین زمان Ov است.'
              : 'بدون هورمون · بازه پایش Ov: ${dates(naturalOv.first)}',
            style: const TextStyle(fontSize: 11, color: _navy)),
          if (naturalBreed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('بدون هورمون · ${naturalBreed.first.label}: ${dates(naturalBreed.first)}',
                style: const TextStyle(fontSize: 11, color: _teal, fontWeight: FontWeight.w700)),
            ),
          if (widget.cycle.scenarioHormone != 'none') ...[
            const SizedBox(height: 6),
            Text(scenarioOv.isEmpty
                ? 'با ${widget.cycle.scenarioHormone}: بازه معتبر ثابت تعریف نشده؛ ${widget.scenario.headline}'
                : 'با ${widget.cycle.scenarioHormone} · ${eligibleOv.isNotEmpty ? 'سناریوی مشروط' : 'مرجع علمی*'}: ${dates(scenarioOv.first)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6D3B94),
                fontWeight: FontWeight.bold)),
            if (scenarioBreed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('با ${widget.cycle.scenarioHormone} · ${scenarioBreed.first.label}: ${dates(scenarioBreed.first)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF5B3582), fontWeight: FontWeight.w700)),
              ),
          ],
          const SizedBox(height: 5),
          const Text('*مرجع علمی فقط برای مادیان واجد شرایط است، نه پیش‌بینی همین بیمار. '
            'سناریو هیچ رویداد واقعی یا تاریخ تخمک‌گذاری تأییدشده را تغییر نمی‌دهد.',
            style: TextStyle(fontSize: 10, color: Color(0xFF647F86))),
        ])),
      const SizedBox(height: 9),
      if (scans.isNotEmpty) ...[
        const Text('خلاصه تمام سونوهای ثبت‌شده مادیان (با روند تغییرات)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _navy)),
        for (var i = 0; i < scans.length; i++)
          Builder(builder: (_) {
            final s = scans[i];
            final prev = i > 0 ? scans[i - 1] : null;
            final dF = (s.dominantFollicleMm != null && prev?.dominantFollicleMm != null)
              ? (s.dominantFollicleMm! - prev!.dominantFollicleMm!)
              : null;
            return Padding(padding: const EdgeInsets.only(top: 4), child: Text(
              'سونو ${ReproJalali.persianDigits(i + 1)} · ${ReproJalali.stamp(s.at)} · '
              'F${s.dominantFollicleMm?.toStringAsFixed(0) ?? '—'} mm'
              '${dF == null ? '' : ' (${dF >= 0 ? '+' : ''}${dF.toStringAsFixed(0)} mm)'} · '
              'UE${s.edemaScore == null ? '—' : ReproJalali.persianDigits(s.edemaScore!)}',
              style: const TextStyle(color: _navy, fontSize: 11)));
          }),
      ],
      if (widget.assessment.recheckAt != null)
        Padding(padding: const EdgeInsets.only(top: 7), child: Text(
          'سونوی پیشنهادی: ${ReproJalali.stamp(widget.assessment.recheckAt!)}',
          style: const TextStyle(color: _teal, fontWeight: FontWeight.bold))),
      const SizedBox(height: 7),
      OutlinedButton.icon(
        onPressed: () => widget.onRecordEvent(DateTime.now(), 'recheck'),
        icon: const Icon(Icons.event_available_outlined),
        label: const Text('ثبت نوبت با تأیید دامپزشک'),
      ),
    ]);
  }
}
