import 'repro_local_store.dart';
import 'repro_cycle_engine_v34.dart';

/// Stage, observed heat day, or a *working estimate* of heat day are different
/// concepts from D0-relative day based on a veterinarian-confirmed ovulation.
class EquineCycleAssessmentV35 {
  final String phase, basis, confidence;
  final int? cycleDay, heatDayMin, heatDayMax;
  final int? referenceDayMin, referenceDayMax;
  final DateTime? anchorOvulation, nextWindowStart, nextWindowEnd, recheckAt;
  final List<String> warnings;
  const EquineCycleAssessmentV35({
    required this.phase, required this.basis, required this.confidence,
    required this.cycleDay, required this.heatDayMin, required this.heatDayMax,
    required this.referenceDayMin, required this.referenceDayMax,
    required this.anchorOvulation, required this.nextWindowStart,
    required this.nextWindowEnd, required this.recheckAt, required this.warnings,
  });
}

class EquineCycleInterpreterV35 {
  static EquineCycleAssessmentV35 assess(BreedingCycle cycle, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final basic = CycleEngineV34.analyze(cycle, now: clock);
    final scans = cycle.events.where((e) =>
        e.type == 'ultrasound' && !e.plannedByVet && !e.at.isAfter(clock)).toList()
      ..sort((a,b) => a.at.compareTo(b.at));
    final scan = scans.isEmpty ? null : scans.last;
    final previous = scans.length >= 2 ? scans[scans.length - 2] : null;
    final ovulations = cycle.events.where((e) =>
        e.type == 'ovulation' && !e.plannedByVet && !e.at.isAfter(clock)).toList()
      ..sort((a,b) => a.at.compareTo(b.at));
    final ov = ovulations.isEmpty ? null : ovulations.last.at;
    int calendarDays(DateTime current, DateTime earlier) =>
      DateTime(current.year,current.month,current.day)
        .difference(DateTime(earlier.year,earlier.month,earlier.day)).inDays;
    final daysFromOv = ov == null ? null : calendarDays(clock, ov);
    final day = daysFromOv == null || daysFromOv < 0 ||
        daysFromOv >= cycle.cycleDisplayDays ? null : daysFromOv;

    final excluded = cycle.pregnancyStatus == 'confirmed' ||
        cycle.pregnancyStatus == 'suspected';
    final dominant = scan?.dominantFollicleMm ?? 0;
    final edema = scan?.edemaScore ?? -1;
    final cl = scan?.corpusLuteum == 'present' ||
        scan?.leftCl == true || scan?.rightCl == true;
    final clChecked = scan?.leftCl != null && scan?.rightCl != null;
    final supportiveSigns = (scan?.estrusScore ?? -1) >= 2 ||
        scan?.cervixStatus == 'open' || scan?.cervixStatus == 'relaxed';
    final fallingEdema = previous != null && scan?.edemaScore != null &&
        previous.edemaScore != null && scan!.edemaScore! < previous.edemaScore!;
    final ch = (scan?.leftChGrade ?? 0) > 0 ||
        (scan?.rightChGrade ?? 0) > 0;
    final warnings = <String>[...basic.alerts];
    String phase = basic.summary;
    String basis = basic.rationale;
    String confidence = scans.length > 1 ? 'متوسط' : 'مقدماتی';
    int? heatMin, heatMax;
    int? refMin, refMax;

    if (excluded) {
      phase = 'نیازمند بررسی آبستنی';
      basis = 'این یافته‌ها را نباید با سیکل طبیعی یک مادیان غیرآبستن تفسیر کرد.';
      confidence = 'مدل سیکل غیرفعال';
    } else if (ch && !cl) {
      phase = 'ساختار CH؛ ارزیابی پس از تخمک‌گذاری / افتراق HAF';
      confidence = 'نیازمند سونوی مقایسه‌ای';
    } else if (basic.phase == 'estrus' || basic.phase == 'periovulatory') {
      // Quantitative stage indicator: deliberately an interval, not a falsely
      // precise D0-relative date. Derived from follicle+edema and their trend.
      if (dominant >= 30 && fallingEdema && edema <= 2) {
        heatMin = 3;
        heatMax = 7;
        phase = 'فحلی انتهایی / پیش‌تخمک‌گذاری محتمل';
      } else if (dominant >= 40 && edema >= 1 && edema <= 2) {
        // EQ-05: F43mm + UE1 + CL unknown with insufficient prior history
        heatMin = 4;
        heatMax = 7;
        phase = 'فحلی انتهایی / تخمک‌گذاری محتمل (نیازمند پایش نزدیک)';
      } else if (dominant >= 25 && dominant < 35 && edema >= 1) {
        // EQ-04: F32mm + UE1 + CL unknown
        heatMin = 1;
        heatMax = 4;
        phase = 'فحلی اولیه تا میانی محتمل';
      } else if (dominant >= 35 && edema >= 1) {
        heatMin = 2;
        heatMax = 6;
        phase = 'فحلی میانی تا انتهایی محتمل';
      } else if (dominant >= 25 && supportiveSigns) {
        heatMin = 1;
        heatMax = 6;
        phase = 'فحلی محتمل';
      }
      confidence = !clChecked ? 'مقدماتی؛ CL کامل بررسی نشده' :
        scans.length > 1 && supportiveSigns ? 'شواهد نسبتاً خوب' : 'مقدماتی';
      if (heatMin != null) {
        basis = 'فولیکول غالب ${dominant.toStringAsFixed(0)} میلی‌متر و ادم ${edema < 0 ? 'ثبت‌نشده' : 'UE$edema'}'
          '${fallingEdema ? ' با روند کاهشی ادم' : ''}'
          '${supportiveSigns ? ' و نشانه‌های فحلی' : ''} با این بازهٔ فحلی سازگارند.';
        if (heatMax! <= 4) {
          refMin = (cycle.cycleDisplayDays * 15 / 21).round();
          refMax = cycle.cycleDisplayDays;
        } else {
          refMin = (cycle.cycleDisplayDays * 17 / 21).round();
          refMax = cycle.cycleDisplayDays;
        }
      }
    } else if (basic.phase == 'diestrus') {
      confidence = 'شواهد فاز لوتئال';
    } else if (basic.phase == 'follicular_activity') {
      confidence = 'پایش سریالی';
    } else if (basic.phase == 'quiet_ovaries') {
      confidence = 'نیازمند زمینهٔ فصلی';
    }

    // Recorded heat start is stronger than any ultrasound-only estimate.
    final heatStart = cycle.heatStart;
    if (heatStart != null && !excluded) {
      final observedDay = calendarDays(clock, heatStart) + 1;
      if (observedDay >= 1 && observedDay <= 15) {
        heatMin = observedDay;
        heatMax = observedDay;
        basis = '$basis شروع فحلیِ ثبت‌شده در پرونده برای شمارش روز فحلی استفاده شده است.';
      }
    } else if (heatMin != null && scan != null && !excluded) {
      final elapsed = calendarDays(clock, scan.at);
      if (elapsed >= 1 && elapsed <= 2) {
        heatMin += elapsed;
        heatMax = heatMax! + elapsed;
      } else if (elapsed > 2) {
        // Keep the scan-time working estimate visible with an explicit staleness note
        // instead of blanking out the clinician's last scan assessment.
        confidence = '$confidence · مربوط به سونوی $elapsed روز قبل';
        basis = '$basis (این تخمین مربوط به زمان آخرین سونو در $elapsed روز قبل است؛ برای وضعیت امروز سونوی جدید ثبت کنید.)';
      }
    }

    DateTime? nextStart, nextEnd;
    if (ov != null && daysFromOv != null && daysFromOv >= 0 &&
        daysFromOv <= 30 && cycle.pregnancyStatus == 'excluded') {
      nextStart = ov.add(Duration(days: cycle.cycleDisplayDays - 3));
      nextEnd = ov.add(Duration(days: cycle.cycleDisplayDays + 3));
      if (nextEnd.isBefore(clock)) {
        nextStart = null;
        nextEnd = null;
      }
    }
    return EquineCycleAssessmentV35(
      phase: phase, basis: basis, confidence: confidence,
      cycleDay: day, heatDayMin: heatMin, heatDayMax: heatMax,
      referenceDayMin: refMin, referenceDayMax: refMax,
      anchorOvulation: ov, nextWindowStart: nextStart,
      nextWindowEnd: nextEnd,
      recheckAt: basic.scanDue, warnings: warnings,
    );
  }
}
