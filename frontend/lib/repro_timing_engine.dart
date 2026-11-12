import 'repro_local_store.dart';
import 'repro_hormone_planner_v33.dart';

/// Advisory windows are NOT planned events and must never be inserted into
/// BreedingCycle.events unless a veterinarian creates a separate record.
class ReproSuggestion {
  final String title;
  final String explanation;
  final String source;
  final String sourceUrl;
  final DateTime? windowStart;
  final DateTime? windowEnd;
  final String priority;

  const ReproSuggestion({
    required this.title,
    required this.explanation,
    required this.source,
    required this.sourceUrl,
    this.windowStart,
    this.windowEnd,
    this.priority = 'info',
  });
}

/// Historic first-confirmation times are not exact moments of ovulation.
/// They can help personalize monitoring but must not independently schedule AI.
class MareCycleInsights {
  final List<double> priorHeatToConfirmationDays;
  final List<double> priorObservedFollicleMm;
  final double? recentGrowthMmPerDay;
  final double? recentScanGapHours;

  const MareCycleInsights({
    required this.priorHeatToConfirmationDays,
    required this.priorObservedFollicleMm,
    this.recentGrowthMmPerDay,
    this.recentScanGapHours,
  });

  int get historicalCycles => priorHeatToConfirmationDays.length;
  double? get typicalDaysToFirstConfirmation => historicalCycles < 2
      ? null
      : priorHeatToConfirmationDays.reduce((a, b) => a + b) /
          historicalCycles;
  double? get earliestDays => historicalCycles < 2 ? null :
      priorHeatToConfirmationDays.reduce((a, b) => a < b ? a : b);
  double? get latestDays => historicalCycles < 2 ? null :
      priorHeatToConfirmationDays.reduce((a, b) => a > b ? a : b);
  double? get typicalObservedOvulatoryFollicle => priorObservedFollicleMm.length < 2
      ? null
      : priorObservedFollicleMm.reduce((a, b) => a + b) /
          priorObservedFollicleMm.length;

  static MareCycleInsights fromMare(MareRecord mare, BreedingCycle active) {
    final history = <double>[];
    final follicles = <double>[];
    for (final cycle in mare.cycles) {
      if (cycle.id == active.id || cycle.heatStart == null) continue;
      final confirmed = cycle.events.where((e) =>
          e.type == 'ovulation' && !e.plannedByVet &&
          !e.at.isBefore(cycle.heatStart!)).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (confirmed.isEmpty) continue;
      final ovAt = confirmed.first.at;
      final elapsed = ovAt.difference(cycle.heatStart!).inMinutes / 1440;
      // Limit to plausible within-cycle observations; this is data hygiene,
      // not a statement that ovulation outside the range is impossible.
      if (elapsed < 0 || elapsed > 12) continue;
      history.add(elapsed);
      final before = cycle.events.where((e) =>
          e.type == 'ultrasound' && !e.plannedByVet &&
          e.dominantFollicleMm != null &&
          !e.at.isAfter(ovAt) &&
          ovAt.difference(e.at).inHours <= 72).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (before.isNotEmpty) follicles.add(before.last.dominantFollicleMm!);
    }
    final scans = active.events.where((e) =>
        e.type == 'ultrasound' && !e.plannedByVet &&
        e.dominantFollicleMm != null).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    double? gap;
    double? growth;
    if (scans.length >= 2) {
      final older = scans[scans.length - 2];
      final newer = scans.last;
      gap = newer.at.difference(older.at).inMinutes / 60.0;
      // Two scans within a few minutes are not evidence of follicular growth.
      if (gap >= 12 && gap <= 96) {
        growth = (newer.dominantFollicleMm! - older.dominantFollicleMm!) * 24 / gap;
      }
    }
    return MareCycleInsights(
      priorHeatToConfirmationDays: history,
      priorObservedFollicleMm: follicles,
      recentGrowthMmPerDay: growth,
      recentScanGapHours: gap,
    );
  }
}

class ReproTimingEngine {
  static const _merckBreeding =
      'https://www.merckvetmanual.com/management-and-nutrition/'
      'management-of-reproduction-horses/breeding-in-horse-reproduction';
  static const _merckHormones =
      'https://www.merckvetmanual.com/reproductive-system/'
      'hormonal-control-of-the-estrous-cycle/'
      'hormonal-control-of-the-estrous-cycle-in-horses';
  static const _csu =
      'https://vetmedbiosci.colostate.edu/erl/2022/12/13/'
      'starting-a-breeding-program-with-your-mare/';
  static const _bevaFrozen =
      'https://www.beva.org.uk/resources/artificial-insemination-in-equine-'
      'reproduction-guidance/appendix-8/';
  static const _bevaFollowup =
      'https://www.beva.org.uk/resources/artificial-insemination-in-equine-'
      'reproduction-guidance/appendix-7/';
  static const _rvc =
      'https://www.rvc.ac.uk/equine-vet/practice/services-and-facilities/'
      'equine-reproduction-services/equine-artificial-insemination';

  static List<ReproSuggestion> evaluate(BreedingCycle cycle,
      {DateTime? now, MareRecord? mare}) {
    final clock = now ?? DateTime.now();
    final events = [...cycle.events]..sort((a, b) => a.at.compareTo(b.at));
    final completed = events.where((e) => !e.plannedByVet).toList();
    BreedingEvent? last(String type) {
      for (final e in completed.reversed) {
        if (e.type == type) return e;
      }
      return null;
    }

    final scan = last('ultrasound');
    final confirmedOvulation = last('ovulation');
    final induction = completed.where((e) {
      if (e.type != 'hormone') return false;
      final name = e.medicine.toLowerCase();
      return name.contains('hcg') || name.contains('deslorelin') ||
          name.contains('دسلورلین');
    }).lastOrNull;
    final suggestions = <ReproSuggestion>[];
    final method = cycle.semenMethod;
    final history = mare == null ? null : MareCycleInsights.fromMare(mare, cycle);
    final estrusObservations = completed.where((e) => e.estrusScore != null).toList();
    final latestEstrus = estrusObservations.isEmpty ? null : estrusObservations.last;
    // A documented lack of receptive behavior blocks automatic breeding prompts.
    final receptive = latestEstrus == null || latestEstrus.estrusScore! >= 2;
    final scanFresh = scan != null && clock.difference(scan.at).inHours >= -2 &&
        clock.difference(scan.at).inHours <= 72;
    final abnormalFluid = scan?.uterineFluid == 'present';

    if (scan == null) {
      suggestions.add(const ReproSuggestion(
        title: 'ابتدا سونوگرافی و وضعیت فحلی را ثبت کنید',
        explanation: 'بدون اندازهٔ فولیکول و ارزیابی رحم/ادم، زمان کشش یا تلقیح قابل پیش‌بینی نیست.',
        source: 'Merck Veterinary Manual',
        sourceUrl: _merckBreeding,
        priority: 'review',
      ));
    } else {
      final follicle = scan.dominantFollicleMm;
      if (follicle == null || follicle <= 0) {
        suggestions.add(const ReproSuggestion(
          title: 'اندازهٔ فولیکول غالب ثبت نشده',
          explanation: 'برای پیشنهاد نوبت بعدی پایش، قطر فولیکول و علائم فحلی لازم است.',
          source: 'CSU Equine Reproduction Laboratory',
          sourceUrl: _csu,
          priority: 'review',
        ));
      } else if (confirmedOvulation == null || confirmedOvulation.at.isBefore(scan.at)) {
        // The scan date is used as an anchor, not the current clock. Stale
        // recommended windows remain explanatory and are never auto-booked.
        final hours = method == 'frozen' && follicle >= 30
            ? 24
            : follicle >= 30
                ? 24
                : 48;
        final start = scan.at.add(Duration(hours: hours));
        suggestions.add(ReproSuggestion(
          title: method == 'frozen' && follicle >= 30
              ? 'پیشنهاد پایش نزدیک‌تر فولیکول (فریز)'
              : 'پیشنهاد نوبت معاینهٔ مجدد',
          explanation: follicle >= 30
              ? 'فولیکول ${follicle.toStringAsFixed(1)} میلی‌متر است. پایش مجدد حدود ۲۴ ساعت پس از آخرین سونو برای بررسی روند و علائم توصیه می‌شود؛ با نزدیک‌شدن به تخمک‌گذاری، فاصلهٔ پایش باید بر اساس دامپزشک کمتر شود.'
              : 'فولیکول ${follicle.toStringAsFixed(1)} میلی‌متر است. زمان معاینهٔ مجدد پیشنهادی حدود ۴۸ ساعت پس از آخرین سونو است و با تغییر علائم قابل اصلاح است.',
          source: 'IFCE / CSU — ovarian monitoring',
          sourceUrl: _csu,
          windowStart: start,
          windowEnd: start,
          priority: follicle >= 30 ? 'review' : 'info',
        ));
        if (method == 'natural' && follicle >= 30 && cycle.heatStart != null &&
            scanFresh && receptive && !abnormalFluid) {
          final day2 = cycle.heatStart!.add(const Duration(days: 2));
          final possibleStart = day2.isAfter(scan.at) ? day2 : scan.at;
          suggestions.add(ReproSuggestion(
            title: 'کشش طبیعی: پنجرهٔ قابل بررسی در فحلی فعلی',
            explanation: 'در فحلی تأییدشده با فولیکول غالب حدود ۳۰–۳۵ میلی‌متر یا بیشتر، بررسی کشش طبیعی از روز ۲–۳ فحلی و سپس هر ۴۸ ساعت تا تأیید تخمک‌گذاری در منابع مطرح است. اگر امتیاز رفتار فحلی ثبت نشده، قبل از کشش حتماً آن را بررسی کنید. این پنجره پیشنهاد مشروط است؛ در گذار فصلی اعتبار کمتری دارد و رویداد یا دستور تلقیح نیست.',
            source: 'Merck — Natural Service',
            sourceUrl: _merckBreeding,
            windowStart: possibleStart,
            windowEnd: possibleStart.add(const Duration(hours: 24)),
            priority: 'review',
          ));
        }
        if (method == 'natural' && follicle >= 30 &&
            (!scanFresh || !receptive || abnormalFluid)) {
          suggestions.add(ReproSuggestion(
            title: 'زمان کشش هنوز قابل پیشنهاد نیست',
            explanation: !scanFresh
                ? 'سونوی قبلی قدیمی است؛ پیش از توصیهٔ کشش، معاینهٔ تازه و ارزیابی رفتار فحلی لازم است.'
                : abnormalFluid
                    ? 'مایع داخل رحم ثبت شده؛ دامپزشک باید علت و مناسب بودن کشش را بررسی کند.'
                    : 'آخرین امتیاز رفتار فحلی پذیرندگی کافی نشان نمی‌دهد؛ صرف قطر فولیکول برای کشش کافی نیست.',
            source: 'Merck — Natural Service',
            sourceUrl: _merckBreeding,
            priority: 'warning',
          ));
        }
        if ((method == 'fresh' || method == 'cooled') && follicle >= 30) {
          suggestions.add(const ReproSuggestion(
            title: 'اسپرم تازه / سرد: زمان‌بندی نزدیک به تخمک‌گذاری',
            explanation: 'تلقیح تازه یا سرد معمولاً در بازهٔ حدود ۲۴ ساعت پیش از تخمک‌گذاری مدنظر قرار می‌گیرد. قطر فولیکول به‌تنهایی ساعت تخمک‌گذاری را مشخص نمی‌کند؛ تأیید روند سونو و کیفیت/زمان دریافت اسپرم لازم است.',
            source: 'Royal Veterinary College — Equine AI',
            sourceUrl: _rvc,
            priority: 'review',
          ));
        }
        if (method == 'frozen' && follicle >= 30) {
          suggestions.add(const ReproSuggestion(
            title: 'فریز: پایش ۶ تا ۸ ساعته در دورهٔ بحرانی',
            explanation: 'برای اسپرم فریز، نزدیک تخمک‌گذاری سونوهای مکرر ۶–۸ ساعته ممکن است لازم باشد. پنجرهٔ بررسی‌شده در راهنمای BEVA حدود ۱۲ ساعت پیش تا ۶ ساعت پس از تخمک‌گذاری است؛ زمان دقیق نیازمند تأیید دامپزشک است.',
            source: 'BEVA — Frozen semen AI, Appendix 8',
            sourceUrl: _bevaFrozen,
            priority: 'review',
          ));
        }
      }
    }

    if (history != null && history.historicalCycles >= 2 &&
        cycle.heatStart != null && confirmedOvulation == null) {
      final minDays = history.earliestDays!;
      final maxDays = history.latestDays!;
      suggestions.add(ReproSuggestion(
        title: 'الگوی اختصاصی مادیان در سیکل‌های قبلی — برای تنظیم پایش',
        explanation: 'در ${history.historicalCycles} سیکل قبلی، نخستین تأیید تخمک‌گذاری بین '
            '${minDays.toStringAsFixed(1)} تا ${maxDays.toStringAsFixed(1)} روز پس از شروع فحلی ثبت شده است. '
            'این زمان، ساعت مشاهدهٔ دامپزشک است نه ساعت دقیق آزادسازی تخمک. '
            'برای سیکل فعلی فقط به برنامه‌ریزی معاینه کمک می‌کند و زمان کشش/تلقیح نیست.',
        source: 'Individual mare records + Merck estrous cycle',
        sourceUrl: _merckBreeding,
        windowStart: cycle.heatStart!.add(Duration(minutes: (minDays * 1440).round())),
        windowEnd: cycle.heatStart!.add(Duration(minutes: (maxDays * 1440).round())),
        priority: 'info',
      ));
    }

    if (induction != null && confirmedOvulation == null) {
      final name = induction.medicine.toLowerCase();
      final scanBefore = completed.where((e) =>
          e.type == 'ultrasound' && !e.at.isAfter(induction.at)).lastOrNull;
      // A recorded date/follicle is only a minimal gate for discussing
      // expected response. Uterine edema must be assessed and free-fluid
      // flags must be reviewed; never call this a confirmed ovulation.
      final eligible = cycle.heatStart != null &&
          (scanBefore?.dominantFollicleMm ?? 0) >= 35 &&
          scanBefore?.edemaScore != null &&
          scanBefore?.uterineFluid != 'present';
      if (!eligible) {
        suggestions.add(const ReproSuggestion(
          title: 'شرایط پاسخ به هورمون تأیید نشده',
          explanation: 'هورمون ثبت شده، اما اطلاعات کافی از فحلی، سونوی پیش‌تخمک‌گذاری، ادم رحم یا وضعیت مایع رحمی موجود نیست. هیچ ساعت تخمک‌گذاری از این ثبت محاسبه نمی‌شود.',
          source: 'Merck — Hormonal control of estrus',
          sourceUrl: _merckHormones,
          priority: 'warning',
        ));
      } else if (name.contains('hcg')) {
        suggestions.add(ReproSuggestion(
          title: 'پنجرهٔ احتمالی پاسخ به hCG — فقط جهت پایش',
          explanation: 'در مادیان واجد شرایط، تخمک‌گذاری اغلب ۳۶ تا ۴۸ ساعت پس از hCG رخ می‌دهد، نه لزوماً. تزریق ثبت‌شده به معنای اثبات اثر دارو نیست؛ با سونوگرافی تأیید شود.',
          source: 'Merck — Hormonal Control in Horses',
          sourceUrl: _merckHormones,
          windowStart: induction.at.add(const Duration(hours: 36)),
          windowEnd: induction.at.add(const Duration(hours: 48)),
          priority: 'review',
        ));
      } else {
        suggestions.add(ReproSuggestion(
          title: 'پنجرهٔ احتمالی پاسخ به Deslorelin — فقط جهت پایش',
          explanation: 'برای شکل تزریقی و مادیان واجد شرایط، حدود ۴۰ تا ۴۴ ساعت پس از تجویز گزارش شده است؛ شکل فرآورده و پاسخ فردی متفاوت است. با سونوگرافی تأیید شود.',
          source: 'Merck — Hormonal Control in Horses',
          sourceUrl: _merckHormones,
          windowStart: induction.at.add(const Duration(hours: 40)),
          windowEnd: induction.at.add(const Duration(hours: 44)),
          priority: 'review',
        ));
      }
    }

    // Recorded PGF2a and named GnRH administrations are assessed separately
    // from hypothetical planning settings. No event or drug order is created.
    final recordedHormones = completed.where((e) => e.type == 'hormone').toList();
    if (recordedHormones.isNotEmpty) {
      final recorded = recordedHormones.last;
      final name = recorded.medicine.toLowerCase();
      final family = name.contains('pgf') || name.contains('prostaglandin') ||
          name.contains('dinoprost') || name.contains('cloprostenol')
        ? 'pg' : name.startsWith('gnrh') ? 'gnrh' : '';
      if (family.isNotEmpty) {
        String product = 'unspecified';
        if (name.contains('deslorelin_injectable')) {
          product = 'deslorelin_injectable';
        } else if (name.contains('histrelin_injectable')) {
          product = 'histrelin_injectable';
        } else if (name.contains('buserelin')) {
          product = 'buserelin';
        } else if (name.contains('gonadorelin')) {
          product = 'gonadorelin';
        }
        final assessment = ReproHormonePlanner.analyze(cycle,
          hormone: family, product: product, plannedAt: recorded.at,
          useRecordedInjection: true, now: clock);
        suggestions.add(ReproSuggestion(
          title: 'پیگیری هورمون ثبت‌شده: ${assessment.headline}',
          explanation: '${assessment.explanation} ${assessment.warnings.join(' ')}',
          source: assessment.evidence, sourceUrl: assessment.evidenceUrl,
          windowStart: assessment.windows.isEmpty ? null : assessment.windows.first.start,
          windowEnd: assessment.windows.isEmpty ? null : assessment.windows.first.end,
          priority: assessment.status == 'blocked' ? 'warning' : 'review',
        ));
      }
    }

    if (confirmedOvulation != null) {
      if (method == 'frozen' && !completed.any((e) =>
          e.type == 'insemination' && !e.at.isBefore(confirmedOvulation.at))) {
        suggestions.add(ReproSuggestion(
          title: 'فریز: پس از تأیید تخمک‌گذاری، بررسی فوری زمان تلقیح',
          explanation: 'پنجرهٔ مورد اشاره در BEVA تا حدود ۶ ساعت پس از تخمک‌گذاری است. زمان ثبتِ مشاهده لزوماً زمان دقیق تخمک‌گذاری نیست؛ پروتکل مرکز، تعداد دوز و وضعیت مادیان تعیین‌کننده‌اند.',
          source: 'BEVA — Frozen semen AI',
          sourceUrl: _bevaFrozen,
          windowStart: confirmedOvulation.at,
          windowEnd: confirmedOvulation.at.add(const Duration(hours: 6)),
          priority: clock.difference(confirmedOvulation.at).inHours > 6
              ? 'warning'
              : 'review',
        ));
      }
      suggestions.add(ReproSuggestion(
        title: 'پیشنهاد سونو بارداری اولیه / بررسی دوقلویی',
        explanation: 'BEVA بررسی بارداری در حدود روز ۱۴ تا ۱۶ پس از تخمک‌گذاری تأییدشده را مطرح می‌کند؛ زمان از تخمک‌گذاری محاسبه می‌شود، نه صرفاً روز تلقیح.',
        source: 'BEVA — Follow-up, Appendix 7',
        sourceUrl: _bevaFollowup,
        windowStart: confirmedOvulation.at.add(const Duration(days: 14)),
        windowEnd: confirmedOvulation.at.add(const Duration(days: 16)),
        priority: 'info',
      ));
    }

    if (completed.any((e) => e.type == 'insemination' || e.type == 'cover')) {
      final breeding = completed.where((e) =>
          e.type == 'insemination' || e.type == 'cover').last;
      if (!completed.any((e) => e.type == 'recheck' && e.at.isAfter(breeding.at))) {
        suggestions.add(ReproSuggestion(
          title: 'پایش پس از تلقیح و بررسی مایع داخل رحم',
          explanation: 'پس از تلقیح، ارزیابی رحم و تأیید تخمک‌گذاری برای بررسی اندومتریت پس از جفت‌گیری اهمیت دارد. برای اسپرم فریز، BEVA معاینهٔ ۶–۱۲ ساعت و برای سرد ۱۲–۲۴ ساعت پس از تلقیح را به‌عنوان زمان‌های مرجع مطرح می‌کند.',
          source: 'BEVA — Appendix 7',
          sourceUrl: _bevaFollowup,
          windowStart: breeding.at.add(Duration(hours: method == 'frozen' ? 6 : 12)),
          windowEnd: breeding.at.add(Duration(hours: method == 'frozen' ? 12 : 24)),
          priority: 'review',
        ));
      }
    }
    return suggestions;
  }
}
