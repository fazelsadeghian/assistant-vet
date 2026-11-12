import 'repro_local_store.dart';

/// Explainable what-if scenarios. Never writes to BreedingCycle.events.
/// A projected window is NOT a probability, medication order or confirmed
/// ovulation. Only clinician-authored records belong in the real timeline.
class ReproProjection {
  final String label;
  final DateTime start;
  final DateTime end;
  final String category;
  final String rationale;
  const ReproProjection({required this.label, required this.start,
    required this.end, required this.category, required this.rationale});
}

class ReproScenarioResult {
  final String status; // informational, conditional, blocked, needs_exam
  final String headline;
  final String explanation;
  final List<String> warnings;
  final List<ReproProjection> windows;
  final String evidence;
  final String evidenceUrl;
  const ReproScenarioResult({required this.status, required this.headline,
    required this.explanation, required this.warnings, required this.windows,
    required this.evidence, required this.evidenceUrl});
  bool get hasPrediction => windows.any((w) => w.category == 'ovulation');
}

class ReproHormonePlanner {
  static const merck = 'https://www.merckvetmanual.com/reproductive-system/'
      'hormonal-control-of-the-estrous-cycle/'
      'hormonal-control-of-the-estrous-cycle-in-horses';
  static const merckCycle = 'https://www.merckvetmanual.com/'
      'management-and-nutrition/management-of-reproduction-horses/'
      'the-reproductive-cycle-of-horses';

  static String methodNameFa(String method) => switch (method) {
    'frozen' => 'اسپرم فریز (Frozen AI)',
    'cooled' => 'اسپرم سرد (Cooled AI)',
    'fresh' => 'اسپرم تازه (Fresh AI)',
    _ => 'کشش طبیعی (Natural)',
  };

  /// Computes a method-dependent breeding/insemination coordination window
  /// relative to a given ovulation monitoring window.
  static ReproProjection methodBreedingWindow(
      BreedingCycle cycle, ReproProjection ovulationWindow) {
    final method = cycle.semenMethod;
    late DateTime breedStart;
    late DateTime breedEnd;
    late String rationale;
    switch (method) {
      case 'frozen':
        breedStart = ovulationWindow.start.subtract(const Duration(hours: 6));
        breedEnd = ovulationWindow.end.add(const Duration(hours: 6));
        rationale = 'برای اسپرم فریز، بازهٔ هماهنگی نزدیک به تخمک‌گذاری (حدود ۶ ساعت پیش تا ۶ ساعت پس از پنجره تخمک‌گذاری با پایش ۶–۸ ساعته) در نظر گرفته می‌شود.';
        break;
      case 'cooled':
        breedStart = ovulationWindow.start.subtract(const Duration(hours: 24));
        breedEnd = ovulationWindow.end.subtract(const Duration(hours: 6));
        if (breedEnd.isBefore(breedStart)) {
          breedEnd = ovulationWindow.end;
        }
        rationale = 'برای اسپرم سرد، هماهنگی ارسال و تلقیح معمولاً ۱۲ تا ۲۴ ساعت پیش از تخمک‌گذاری احتمالی برنامه‌ریزی می‌شود.';
        break;
      case 'fresh':
        breedStart = ovulationWindow.start.subtract(const Duration(hours: 24));
        breedEnd = ovulationWindow.end;
        rationale = 'برای اسپرم تازه، بازهٔ هماهنگی در ۲۴ ساعت منتهی به پنجره تخمک‌گذاری بررسی می‌شود.';
        break;
      default:
        breedStart = ovulationWindow.start.subtract(const Duration(hours: 36));
        breedEnd = ovulationWindow.end;
        rationale = 'برای کشش طبیعی، هماهنگی از حدود ۲۴ تا ۴۸ ساعت پیش از تخمک‌گذاری و تکرار بر اساس نظر دامپزشک بررسی می‌شود.';
        break;
    }
    return ReproProjection(
      label: 'بازهٔ هماهنگی ${methodNameFa(method)}',
      start: breedStart,
      end: breedEnd,
      category: 'breeding',
      rationale: rationale,
    );
  }

  /// A population-level reference anchored to a hypothetical intervention.
  /// This is intentionally NOT placed in the validated patient windows.
  /// The actual date of ovulation must never be shifted from this function.
  static ReproProjection? educationalReference(BreedingCycle cycle) {
    if (cycle.pregnancyStatus == 'confirmed' || cycle.pregnancyStatus == 'suspected') {
      return null;
    }
    final at = cycle.scenarioInjectionAt;
    if (at == null) return null;
    int? startHours, endHours;
    String? label;
    switch (cycle.scenarioHormone) {
      case 'hcg':
        startHours = 36;
        endHours = 48;
        label = 'پاسخ جمعیتی به hCG در مادیان واجد شرایط';
        break;
      case 'gnrh':
        if (cycle.scenarioProduct != 'deslorelin_injectable' &&
            cycle.scenarioProduct != 'histrelin_injectable') return null;
        startHours = 40;
        endHours = 48;
        label = 'پاسخ جمعیتی به آگونیست تزریقی منتخب در مادیان واجد شرایط';
        break;
      case 'pg' || 'sequence':
        startHours = 72;
        endHours = 240;
        label = 'دامنه وسیع پایش پس از PGF₂α فقط در حضور CL بالغ';
        break;
      default:
        return null;
    }
    return ReproProjection(
      label: label!,
      start: at.add(Duration(hours: startHours!)),
      end: at.add(Duration(hours: endHours!)),
      category: 'reference_ovulation',
      rationale: 'صرفاً بازه مرجع منتشرشده با فرض احراز شرایط بالینی، نه پیش‌بینی بیمار، دستور تجویز یا رویداد واقعی.',
    );
  }

  /// Back-plans a candidate injection review window from a veterinarian's
  /// intended breeding time. It never recommends administering a drug.
  /// Eligibility MUST be reconfirmed by an examination at the proposed time.
  static ReproProjection? backPlan(BreedingCycle cycle, {DateTime? now}) {
    final target = cycle.targetBreedingAt;
    if (target == null || cycle.pregnancyStatus != 'excluded') return null;
    final hormone = cycle.scenarioHormone;
    int earliest, latest;
    if (hormone == 'hcg') {
      earliest = 36; latest = 48;
    } else if (hormone == 'gnrh' &&
      (cycle.scenarioProduct == 'deslorelin_injectable' ||
       cycle.scenarioProduct == 'histrelin_injectable')) {
      earliest = 40; latest = 48;
    } else {
      return null; // PGF2a and unknown GnRH products cannot be back-timed.
    }
    final clock = now ?? DateTime.now();
    final scans = cycle.events.where((e) => !e.plannedByVet &&
        e.type == 'ultrasound' && !e.at.isAfter(clock)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (scans.isEmpty || cycle.heatStart == null) return null;
    final scan = scans.last;
    if ((scan.dominantFollicleMm ?? 0) < 35 || scan.edemaScore == null ||
        scan.corpusLuteum == 'present' || scan.uterineFluid == 'present' ||
        clock.difference(scan.at).inHours > 48) return null;
    if (target.isBefore(clock) || target.difference(clock).inHours > 72) return null;
    int pre, post;
    switch (cycle.semenMethod) {
      case 'frozen': pre = 12; post = 6; break;
      case 'cooled': pre = 24; post = 12; break;
      case 'fresh': pre = 36; post = 8; break;
      default: pre = 48; post = 0; break;
    }
    final start = target.subtract(Duration(hours: post + latest));
    final end = target.add(Duration(hours: pre - earliest));
    if (end.isBefore(start)) return null;
    return ReproProjection(
      label: 'پنجرهٔ فرضی بررسی زمان القا بر اساس هدف تلقیح',
      start: start, end: end, category: 'injection_candidate',
      rationale: 'این بازه فقط یک محاسبهٔ برنامه‌ریزی معکوس با فرض پاسخ جمعیتی است. '
          'در روز احتمالی تزریق باید بلوغ فولیکول، ادم، فحلی، وضعیت آبستنی و فرآورده دوباره بررسی شوند. '
          'در صورت قدیمی‌شدن سونو، این پیشنهاد اعتبار ندارد.');
  }

  static ReproScenarioResult analyze(BreedingCycle cycle, {
    String? hormone, String? product, DateTime? plannedAt,
    DateTime? breedingTarget, bool useRecordedInjection = false,
    DateTime? now,
  }) {
    final h = hormone ?? cycle.scenarioHormone;
    final p = product ?? cycle.scenarioProduct;
    final at = plannedAt ?? cycle.scenarioInjectionAt;
    final target = breedingTarget ?? cycle.targetBreedingAt;
    final clock = now ?? DateTime.now();
    final actual = cycle.events.where((e) => !e.plannedByVet).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final scans = actual.where((e) => e.type == 'ultrasound').toList();
    final latest = scans.isEmpty ? null : scans.last;
    final ovulation = actual.where((e) => e.type == 'ovulation').toList();
    final lastOv = ovulation.isEmpty ? null : ovulation.last;
    final estrus = actual.where((e) => e.estrusScore != null).toList();
    final latestHeat = estrus.isEmpty ? null : estrus.last.estrusScore;
    final estrusEvidence = (latestHeat != null && latestHeat > 0) ||
      (latest?.edemaScore ?? 0) >= 1 || latest?.cervixStatus == 'open' ||
      latest?.cervixStatus == 'relaxed';
    final warnings = <String>[];
    final windows = <ReproProjection>[];
    final selected = cycle.semenMethod;
    final methodLabel = methodNameFa(selected);
    final recordKind = useRecordedInjection ? 'ثبت واقعیِ دامپزشک' : 'سناریوی فرضی';
    final pregnancy = cycle.pregnancyStatus;
    final source = h == 'none' ? merckCycle : merck;
    final sourceLabel = h == 'none' ? 'Merck — Reproductive cycle' :
      'Merck — Hormonal control of estrous cycle';

    ReproScenarioResult result(String status, String headline,
        String explanation) {
      if (h != 'none' && windows.isEmpty && latest != null) {
        final base = latest.at.add(const Duration(hours: 24));
        final next = base.isBefore(clock) ? clock : base;
        windows.add(ReproProjection(
          label: 'بازبینی سونو و شرایط پیش از تصمیم هورمونی',
          start: next,
          end: next.add(const Duration(hours: 12)),
          category: 'recheck',
          rationale: 'این یک موعد بررسی دوباره است، نه زمان تزریق یا زمان تأییدشدهٔ تخمک‌گذاری.',
        ));
      }
      return ReproScenarioResult(status: status,
        headline: headline, explanation: explanation,
        warnings: List.unmodifiable(warnings),
        windows: List.unmodifiable(windows),
        evidence: sourceLabel, evidenceUrl: source);
    }
    if (pregnancy == 'confirmed' || pregnancy == 'suspected') {
      warnings.add('آبستنی تأییدشده/مشکوک: این سیکل برای سناریوی القای فحلی یا تخمک‌گذاری مناسب نیست.');
      return result('blocked', 'ابتدا وضعیت آبستنی بررسی شود',
        'هیچ پنجرهٔ تزریق یا تلقیح از این داده‌ها محاسبه نمی‌شود.');
    }
    if (h != 'none' && ((latest?.leftChGrade ?? 0) > 0 ||
        (latest?.rightChGrade ?? 0) > 0)) {
      warnings.add('CH ثبت شده؛ افتراق CH و فولیکول خونریزی‌دهنده بدون تخمک‌گذاری (HAF) لازم است.');
      return result('needs_exam', 'بازبینی CH پیش از سناریوی هورمونی',
        'وجود یک ساختار CH در سونو به‌تنهایی تأیید تخمک‌گذاری یا سن جسم زرد نیست.');
    }
    if (latest?.uterineFluid == 'present') {
      warnings.add('مایع داخل رحم گزارش شده؛ بررسی سلامت رحم پیش از برنامه‌ریزی تلقیح ضروری است.');
    }
    if (latestHeat != null && latestHeat == 0) {
      warnings.add('آخرین آزمون رفتار فحلی پذیرندگی نشان نمی‌دهد.');
    }
    if (latest?.corpusLuteum == 'present' && h != 'pg' && h != 'sequence') {
      warnings.add('جسم زرد ثبت شده؛ فاز لوتئال باید پیش از پیشنهاد القای تخمک‌گذاری بررسی شود.');
    }
    if (h == 'none') {
      warnings.add('در سیکل طبیعی، تاریخ‌ها تقریبی‌اند و فقط برای پایش و تصمیم بالینی دامپزشک نمایش داده می‌شوند.');
      if (latest != null && latest.dominantFollicleMm != null) {
        final size = latest.dominantFollicleMm!;
        final edema = latest.edemaScore ?? -1;
        final nextHours = selected == 'frozen' && size >= 35
            ? 6
            : selected == 'cooled' && size >= 35
                ? 12
                : size >= 35
                    ? 24
                    : 48;
        windows.add(ReproProjection(
          label: 'بررسی مجدد پیشنهادی ($methodLabel)',
          start: latest.at.add(Duration(hours: nextHours)),
          end: latest.at.add(Duration(hours: nextHours + 6)),
          category: 'recheck',
          rationale: 'فاصلهٔ پایش مشروط به وضعیت بالینی، روش $methodLabel و نظر دامپزشک است.',
        ));
        final clPresent = latest.corpusLuteum == 'present';
        if (!clPresent && size >= 25 && edema >= 1) {
          late DateTime ovStart;
          late DateTime ovEnd;
          if (size >= 40) {
            ovStart = latest.at.add(const Duration(hours: 12));
            ovEnd = latest.at.add(const Duration(days: 4));
          } else if (size >= 35) {
            ovStart = latest.at.add(const Duration(hours: 24));
            ovEnd = latest.at.add(const Duration(days: 5));
          } else if (size >= 30) {
            ovStart = latest.at.add(const Duration(days: 2));
            ovEnd = latest.at.add(const Duration(days: 7));
          } else {
            ovStart = latest.at.add(const Duration(days: 3));
            ovEnd = latest.at.add(const Duration(days: 8));
          }
          final ovProj = ReproProjection(
            label: 'دورهٔ وسیع پایش احتمال تخمک‌گذاری',
            start: ovStart,
            end: ovEnd,
            category: 'ovulation',
            rationale: 'این بازه فقط افق پایش بر پایهٔ اطلاعات اولیه و تغییرپذیری طبیعی مادیان است؛ ساعت یا روز تخمک‌گذاری نیست.',
          );
          windows.add(ovProj);
          windows.add(methodBreedingWindow(cycle, ovProj));
        }
      }
      return result('informational', 'سیکل طبیعی · پایش و زمان‌بندی تقریبی ($methodLabel)',
        target == null
          ? 'برنامه، تاریخ احتمالی معاینه و پنجرهٔ تقریبی پایش/تلقیح را بر اساس روش $methodLabel از روی آخرین سونو نشان می‌دهد.'
          : 'زمان تلقیح موردنظر ثبت شده است؛ تاریخ‌های زیر فقط برای تطبیق تقریبی با وضعیت فعلی ($methodLabel) نمایش داده می‌شوند.');
    }
    if (at == null) {
      final back = backPlan(cycle, now: clock);
      if (back != null) windows.add(back);
      warnings.add('زمان پیشنهادی تزریق فقط حاصل بازبرنامه‌ریزیِ هدف تلقیح است؛ باید با معاینهٔ نزدیک به همان روز بازبینی شود.');
      warnings.add('برای بررسی سناریو، تاریخ و ساعت فرضی تزریق لازم است.');
      return result('needs_exam', 'زمان تزریق فرضی انتخاب نشده',
        'تاریخ موردنظر را انتخاب کنید؛ انتخاب سناریو هیچ تزریقی ثبت نمی‌کند.');
    }
    if (at.isBefore(clock.subtract(const Duration(days: 365)))) {
      warnings.add('تاریخ سناریو خیلی قدیمی است؛ داده‌های فعلی برای بازسازی وضعیت آن زمان کافی نیست.');
      return result('needs_exam', 'تاریخ سناریو نیازمند بازبینی است',
        'برای بازسازی تاریخی از پروندهٔ همان زمان استفاده کنید.');
    }
    if (pregnancy != 'excluded') {
      warnings.add('آبستنی هنوز توسط دامپزشک رد نشده؛ پیش از هورمون‌تراپی وضعیت آبستنی ثبت شود.');
      return result('blocked', 'وضعیت آبستنی نامشخص ($methodLabel)',
        'موتور پیش از رد مستند آبستنی، پنجرهٔ دارویی بالینی تولید نمی‌کند (بازهٔ مرجع علمی در صورت وجود جداگانه نشان داده می‌شود).');
    }
    BreedingEvent? scanBefore;
    for (final s in scans) {
      if (!s.at.isAfter(at)) scanBefore = s;
    }
    final hrs = scanBefore == null ? null :
      at.difference(scanBefore.at).inMinutes / 60.0;
    final recentScan = hrs != null && hrs >= 0 && hrs <= 48;
    if (scanBefore?.uterineFluid == 'present') {
      warnings.add('وجود مایع رحم در سونو نیازمند بررسی جداگانه است.');
      return result('blocked', 'سلامت رحم نیازمند بررسی است',
        'پیش از پیشنهاد هورمون و تلقیح، یافتهٔ مایع رحم باید ارزیابی شود.');
    }
    final fieldReady = recentScan && latestHeat != 0;
    if (!fieldReady) {
      warnings.add('سونو/وضعیت رحم نزدیک زمان تزریق کافی نیست، یا دادهٔ نامساعد وجود دارد.');
      return result('needs_exam', 'معاینهٔ تازه قبل از برنامه‌ریزی لازم است',
        'سونو باید پیش از تزریق فرضی و نزدیک به همان زمان باشد؛ توصیهٔ دقیق تولید نمی‌شود.');
    }
    if (h == 'pg' || h == 'sequence') {
      if (scanBefore?.corpusLuteum != 'present') {
        warnings.add('PGF₂α تنها در حضور جسم زرد پاسخ‌گوی بالغ برای لوتئولیز مطرح است.');
        return result('blocked', 'جسم زرد فعال تأیید نشده',
          'PGF₂α محرک مستقیم تخمک‌گذاری نیست؛ در آنستروس یا بدون جسم زرد، این زمان‌بندی معتبر نیست.');
      }
      if (lastOv == null || lastOv.at.isAfter(at)) {
        warnings.add('سن جسم زرد نامشخص است؛ تاریخ آخرین تخمک‌گذاری تأییدشده لازم است.');
        return result('needs_exam', 'سن جسم زرد مشخص نیست',
          'به دلیل نبود شاهد کافی از بلوغ جسم زرد، بازهٔ پاسخ PG محاسبه نشد.');
      }
      final ageDays = at.difference(lastOv.at).inHours / 24;
      if (ageDays < 5 || ageDays > 14) {
        warnings.add('بازهٔ پاسخ‌گویی معمول جسم زرد در Merck حدود روزهای ۵ تا ۱۴ پس از تخمک‌گذاری است؛ این مشاهده خارج از آن بازه است.');
        return result('blocked', 'شرایط زمانی جسم زرد نیازمند بازبینی است',
          'از تاریخ موردنظر، پاسخ قابل اتکای PGF₂α پیش‌بینی نمی‌شود.');
      }
      windows.add(ReproProjection(label: 'بازگشت احتمالی فحلی پس از PGF₂α',
        start: at.add(const Duration(days: 2)),
        end: at.add(const Duration(days: 5)),
        category: 'estrus',
        rationale: 'بازهٔ جمعیتی، نه زمان قطعی فحلی برای این مادیان.'));
      final pgOv = ReproProjection(label: 'پنجرهٔ وسیع پایش تخمک‌گذاری پس از PGF₂α',
        start: at.add(const Duration(days: 3)),
        end: at.add(const Duration(days: 10)),
        category: 'ovulation',
        rationale: 'بازهٔ بسیار متغیر و وابسته به موج فولیکولی؛ سونوی متوالی ضروری است.');
      windows.add(pgOv);
      windows.add(methodBreedingWindow(cycle, pgOv));
      if (h == 'sequence') {
        warnings.add('گام دوم hCG / GnRH ساعت ثابتی بعد از PG ندارد؛ باید پس از برگشت فحلی و بلوغ فولیکول دوباره ارزیابی شود.');
      }
      return result('conditional', h == 'pg'
          ? 'PGF₂α · بررسی لوتئولیز جسم زرد ($methodLabel)'
          : 'PGF₂α → سپس ارزیابی hCG یا GnRH ($methodLabel)',
        'برای مادیان دارای جسم زرد بالغ و آبستنی ردشده، پنجره‌های پاسخ جمعیتی نمایش داده شده‌اند. '
        'این‌ها برنامهٔ تزریق یا گواه تخمک‌گذاری نیستند ($recordKind).');
    }
    if (h != 'hcg' && h != 'gnrh') {
      return result('needs_exam', 'هورمون انتخاب‌شده ناشناخته است',
        'موتور برای این ماده پروتکل قابل نمایش ندارد.');
    }
    // Check GnRH product validity FIRST so Gonadorelin/Buserelin always give
    // a clear product-specific explanation (EQ-07).
    if (h == 'gnrh' && p != 'deslorelin_injectable' && p != 'histrelin_injectable') {
      warnings.add('برای فرآوردهٔ GnRH انتخاب‌شده یک پنجرهٔ قابل تعمیمِ تک‌تزریقی تأیید نشده؛ از بازهٔ Deslorelin برای همهٔ آگونیست‌ها استفاده نمی‌کنیم.');
      if (scanBefore != null) {
        final nextHours = selected == 'frozen' ? 6 : 12;
        windows.add(ReproProjection(
          label: 'سونوی پیشنهادی پایش فولیکول ($methodLabel)',
          start: at.add(Duration(hours: nextHours)),
          end: at.add(Duration(hours: nextHours + 6)),
          category: 'recheck',
          rationale: 'به دلیل نبود پنجرهٔ ساعت‌دار ثابت برای این فرآورده، تصمیم‌گیری بر پایهٔ سونوی متوالی انجام می‌شود.',
        ));
      }
      return result('needs_exam', 'فرآوردهٔ GnRH نیازمند پروتکل خاص است ($methodLabel)',
        'Buserelin، Gonadorelin و فرآورده‌های دیگر معادل Deslorelin تزریقی نیستند و ساعت قطعی ساختگی برای آن‌ها نمایش داده نمی‌شود.');
    }
    if (scanBefore?.corpusLuteum == 'present' ||
        scanBefore?.edemaScore == null ||
        !estrusEvidence ||
        (scanBefore?.dominantFollicleMm ?? 0) < 35) {
      warnings.add('برای القای تخمک‌گذاری، فحلی و فولیکول پیش‌تخمک‌گذاری بالغ (≥۳۵ میلی‌متر) همراه با ارزیابی رحم لازم است.');
      if (scanBefore != null && scanBefore.dominantFollicleMm != null) {
        final size = scanBefore.dominantFollicleMm!;
        final nextHours = size >= 35 ? 12 : 24;
        windows.add(ReproProjection(
          label: 'سونوی بازبینی پیش از تصمیم هورمونی ($methodLabel)',
          start: at.add(Duration(hours: nextHours)),
          end: at.add(Duration(hours: nextHours + 12)),
          category: 'recheck',
          rationale: 'به‌علت کامل نبودن شرایط القا، تاریخ زیر فقط برای بازبینی بالینی و سونوی بعدی پیشنهاد می‌شود.',
        ));
      }
      return result('blocked', 'شرایط پیش‌تخمک‌گذاری هنوز کامل تأیید نشده ($methodLabel)',
        'تزریق از این سیستم توصیه نمی‌شود، اما زمان سونوی بعدی برای تکمیل تصمیم‌گیری نمایش داده شده است.');
    }
    int minHours, maxHours;
    String qualifier;
    if (h == 'hcg') {
      minHours = 36; maxHours = 48;
      qualifier = 'در مادیان‌های واجد شرایط و در مطالعات hCG، پاسخ اغلب طی ۳۶ تا ۴۸ ساعت گزارش شده است.';
    } else {
      minHours = 40; maxHours = 48;
      qualifier = 'این بازه فقط مرجع جمعیتیِ آگونیست تزریقی انتخاب‌شده است؛ شکل فرآورده و دوز معتبر باید جداگانه کنترل شود.';
    }
    final ovWindow = ReproProjection(label: 'پنجرهٔ مشروط پاسخ پیش‌تخمک‌گذاری',
      start: at.add(Duration(hours: minHours)),
      end: at.add(Duration(hours: maxHours)),
      category: 'ovulation', rationale: qualifier);
    windows.add(ovWindow);
    windows.add(methodBreedingWindow(cycle, ovWindow));
    final checkFrom = selected == 'frozen' ? 6 : 12;
    windows.add(ReproProjection(label: 'بررسی نزدیک‌تر پس از سناریوی القا ($methodLabel)',
      start: at.add(Duration(hours: 24)),
      end: at.add(Duration(hours: 24 + checkFrom)),
      category: 'recheck',
      rationale: 'پایش و فاصلهٔ دقیق معاینه با نوع تلقیح ($methodLabel) و دامپزشک تنظیم شود.'));
    if (target != null) {
      final w = windows.first;
      if (selected == 'frozen' &&
          (target.isBefore(w.start.subtract(const Duration(hours: 12))) ||
            target.isAfter(w.end.add(const Duration(hours: 6))))) {
        warnings.add('هدف زمانی Frozen خارج از پنجرهٔ معمول نزدیک تخمک‌گذاری است؛ برنامهٔ تلقیح و دوز موجود را دوباره بررسی کنید.');
      } else if (selected == 'cooled') {
        warnings.add('هماهنگی ساعت جمع‌آوری/رسیدن اسپرم سرد و کیفیت هنگام دریافت ضروری است.');
      } else if (selected == 'natural') {
        warnings.add('برای کشش طبیعی پذیرندگی مادیان و وضعیت نریان جداگانه تأیید شود.');
      }
    }
    return result('conditional',
      h == 'hcg'
          ? 'hCG · پاسخ احتمالی مشروط ($methodLabel)'
          : 'GnRH agonist · پاسخ احتمالی مشروط ($methodLabel)',
      '$qualifier زمان تزریق، ساعت تأیید تخمک‌گذاری نیست؛ نتیجه با سونو باید ارزیابی شود ($recordKind).');
  }
}
