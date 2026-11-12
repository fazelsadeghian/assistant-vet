import 'repro_local_store.dart';

/// Evidence-oriented examination summary. Phases are clinical hypotheses;
/// neither a precise cycle day nor ovulation is diagnosed from one scan.
class CycleReviewV34 {
  final String phase, summary, rationale;
  final List<String> alerts;
  final DateTime? scanDue;
  final double? leftRate, rightRate, leftHypothetical48h, rightHypothetical48h;
  const CycleReviewV34({required this.phase,required this.summary,required this.rationale,
    required this.alerts,this.scanDue,this.leftRate,this.rightRate,
    this.leftHypothetical48h,this.rightHypothetical48h});
}

class CycleEngineV34 {
  static CycleReviewV34 analyze(BreedingCycle cycle, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final scans = cycle.events.where((e) =>
      e.type == 'ultrasound' && !e.plannedByVet && !e.at.isAfter(clock)).toList()
      ..sort((a,b) => a.at.compareTo(b.at));
    if (scans.isEmpty) {
      return const CycleReviewV34(
        phase: 'unknown', summary: 'هنوز سونوگرافی ثبت نشده',
        rationale: 'برای شروع پایش، یافته‌های دو تخمدان و ادم رحم را ثبت کنید.',
        alerts: [],
      );
    }
    final last = scans.last;
    final previous = scans.length > 1 ? scans[scans.length - 2] : null;
    final cl = last.leftCl == true || last.rightCl == true ||
      last.corpusLuteum == 'present';
    final absentCl = last.leftCl == false && last.rightCl == false ||
      last.corpusLuteum == 'absent';
    final size = last.dominantFollicleMm ?? 0.0;
    final edema = last.edemaScore;
    final edemaFalling = previous?.edemaScore != null && edema != null &&
      edema < previous!.edemaScore!;
    final estrusSigns = (last.estrusScore ?? -1) >= 2 ||
      last.cervixStatus == 'open' || last.cervixStatus == 'relaxed';
    final lutealSigns = last.cervixStatus == 'closed' && (edema ?? -1) <= 1;
    final warnings = <String>[];
    if (last.uterineFluid == 'present') {
      warnings.add('مایع رحم ثبت شده؛ بررسی سلامت آندومتر و خطر پاکسازی ناکافی لازم است.');
    }
    if (last.edemaScore == 5) {
      warnings.add('UE5 ثبت شده؛ وضعیت غیرطبیعی آندومتر را بررسی کنید.');
    }
    if (last.largeFollicleCount >= 2) {
      warnings.add('چند فولیکول بزرگ دیده شده؛ هر فولیکول را جداگانه پایش کنید (خطر تخمک‌گذاری دوتایی).');
    }
    if (cycle.pregnancyStatus == 'confirmed' || cycle.pregnancyStatus == 'suspected') {
      return CycleReviewV34(
        phase: 'pregnancy_review',
        summary: 'ابتدا وضعیت آبستنی بررسی شود',
        rationale: 'الگوی سیکل طبیعی برای آبستنی تأییدشده یا مشکوک قابل استفاده نیست.',
        alerts: warnings,
        scanDue: clock,
      );
    }

    String phase;
    String summary;
    String why;
    if (cl) {
      phase = 'diestrus';
      summary = 'فاز لوتئال / دای‌استروس محتمل';
      why = 'وجود CL با فاز لوتئال سازگار است؛ سن دقیق CL از این یک معاینه مشخص نمی‌شود.';
    } else if (size >= 30 && edemaFalling && (edema ?? 0) <= 2) {
      phase = 'periovulatory';
      summary = 'فحلی انتهایی؛ پایش نزدیک تخمک‌گذاری';
      why = 'فولیکول بزرگ و کاهش ثبت‌شدهٔ ادم نسبت به سونوی قبلی به نفع فاز پیش‌تخمک‌گذاری است.';
    } else if (size >= 40 && edema != null && edema >= 1 && edema <= 2 && !lutealSigns) {
      // EQ-05: Large follicle (>=40mm) with low edema (UE1-2) and insufficient prior history
      // warrants attention to late estrus / impending ovulation without inventing an exact hour.
      phase = 'periovulatory';
      summary = 'فحلی انتهایی / نزدیک تخمک‌گذاری محتمل';
      why = 'فولیکول بزرگ (${size.toStringAsFixed(0)} mm) همراه با ادم پایین (UE$edema) می‌تواند با فحلی انتهایی و نزدیکی تخمک‌گذاری سازگار باشد؛ بدون تعیین ساعت ساختگی، پایش نزدیک توصیه می‌شود.'
          '${absentCl ? ' CL مشاهده نشده است.' : ' وضعیت CL کامل ثبت نشده است.'}';
    } else if (size >= 25 && edema != null && edema >= 1 && !lutealSigns) {
      // EQ-04: Unassessed CL is not interpreted as absent, but reports the working stage.
      phase = 'estrus';
      summary = 'فعالیت فولیکولی سازگار با فحلی';
      why = 'فولیکول ${size.toStringAsFixed(0)} میلی‌متر و ادم UE$edema با فعالیت فحلی سازگارند.'
          '${absentCl ? ' CL در دو تخمدان مشاهده نشده است.' : ' وضعیت CL هنوز تکمیل نشده؛ فاز به‌صورت احتمالی گزارش می‌شود.'}'
          '${estrusSigns ? ' رفتار یا سرویکس نیز از فحلی حمایت می‌کند.' : ''}';
    } else if (size >= 25 && estrusSigns && !lutealSigns) {
      phase = 'estrus';
      summary = 'فحلی بر اساس علائم رفتاری و فولیکولی محتمل';
      why = 'فولیکول در حال رشد همراه با شواهد رفتاری/سرویکس، با فحلی سازگار است.';
    } else if (size >= 10) {
      phase = 'follicular_activity';
      summary = 'فعالیت فولیکولی؛ پایش مرحله سیکل';
      why = 'رشد فولیکولی دیده می‌شود؛ بررسی روند ادم، CL و معاینات متوالی برای افتراق فازها کمک‌کننده است.';
    } else if (size < 10 && !cl && edema == 0) {
      phase = 'quiet_ovaries';
      summary = 'تخمدان کم‌فعال؛ بررسی آن‌استروس یا دوره انتقالی';
      why = 'فولیکول شاخص کوچک و ادم صفر ثبت شده؛ برای افتراق وضعیت فصلی باید سابقه و معاینات بعدی بررسی شود.';
    } else {
      phase = 'incomplete';
      summary = 'مرحله سیکل در دست بررسی';
      why = 'یافته‌ها ثبت شده‌اند؛ تکمیل ادم، CL و سونوهای پیگیری برای مشخص‌شدن فاز کمک می‌کند.';
    }

    double? rate(double? earlier, double? current, bool confirmed) {
      if (previous == null || !confirmed || earlier == null || current == null) return null;
      final hours = last.at.difference(previous.at).inMinutes / 60.0;
      if (hours < 12 || hours > 168) return null;
      return (current - earlier) / (hours / 24.0);
    }
    final leftRate = rate(previous?.leftFollicleMm, last.leftFollicleMm, last.sameLeftFollicle);
    final rightRate = rate(previous?.rightFollicleMm, last.rightFollicleMm, last.sameRightFollicle);
    double? hypothetical(double? mm, double? growth) {
      if (mm == null || growth == null) return null;
      final v = mm + 2 * growth;
      return v < 0 || v > 100 ? null : v;
    }
    int hours = phase == 'periovulatory' ? 12 : phase == 'estrus' ? 24 :
      phase == 'diestrus' ? 48 : 48;
    if (cycle.semenMethod == 'frozen' &&
        (phase == 'periovulatory' || phase == 'estrus')) {
      hours = 6;
    }
    final proposed = last.at.add(Duration(hours: hours));
    return CycleReviewV34(
      phase: phase, summary: summary, rationale: why, alerts: warnings,
      scanDue: proposed.isBefore(clock) ? clock : proposed,
      leftRate: leftRate, rightRate: rightRate,
      leftHypothetical48h: hypothetical(last.leftFollicleMm, leftRate),
      rightHypothetical48h: hypothetical(last.rightFollicleMm, rightRate),
    );
  }
}
