import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'repro_local_store.dart';
import 'repro_hormone_planner_v33.dart';

const _chartInk = Color(0xFF27495A);
const _chartTeal = Color(0xFF079F91);

/// Live recorded timeline and hypothetical windows on separate horizontal lanes.
/// The chart never changes or adds a record in cycle.events.
class ReproScenarioStrip extends StatelessWidget {
  final BreedingCycle cycle;
  final ReproScenarioResult result;
  const ReproScenarioStrip({super.key, required this.cycle,
    required this.result});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final anchor = cycle.scenarioInjectionAt ?? now;
    final marks = cycle.events.where((e) => !e.plannedByVet).toList();
    final bounds = <DateTime>[anchor, now];
    bounds.addAll(result.windows.expand((w) => [w.start, w.end]));
    if (cycle.targetBreedingAt != null) bounds.add(cycle.targetBreedingAt!);
    final nearby = marks.where((e) =>
        e.at.isAfter(anchor.subtract(const Duration(days: 16))) &&
        e.at.isBefore(anchor.add(const Duration(days: 18)))).toList();
    bounds.addAll(nearby.map((e) => e.at));
    bounds.sort();
    var from = bounds.first.subtract(const Duration(hours: 12));
    var to = bounds.last.add(const Duration(hours: 12));
    if (to.difference(from).inHours < 96) {
      from = anchor.subtract(const Duration(hours: 36));
      to = anchor.add(const Duration(hours: 84));
    }
    // Keep this readable for the actual planning horizon; no longer than 30d.
    if (to.difference(from).inDays > 30) {
      from = anchor.subtract(const Duration(days: 3));
      to = anchor.add(const Duration(days: 15));
    }
    final start = from;
    final end = to;
    String stamp(DateTime d) => '${d.month}/${d.day} '
      '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: const Color(0xFFF7FAFD),
        border: Border.all(color: const Color(0xFFDDE9EF)),
        borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Dynamic cycle window · پنجره‌های زمانی',
          style: TextStyle(color: _chartInk, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        const Text('بالا: رخداد ثبت‌شده · پایین: سناریوی فرضی؛ هیچ پیشنهادی به سوابق اضافه نمی‌شود.',
          style: TextStyle(fontSize: 11, color: Color(0xFF708391))),
        const SizedBox(height: 12),
        SizedBox(height: 126, width: double.infinity,
          child: CustomPaint(painter: _ScenarioPainter(
            start: start, end: end, events: nearby, result: result,
            injection: cycle.scenarioHormone == 'none' ? null : cycle.scenarioInjectionAt,
            target: cycle.targetBreedingAt))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(stamp(start), style: const TextStyle(fontSize: 11, color: _chartInk)),
          Text(stamp(end), style: const TextStyle(fontSize: 11, color: _chartInk)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 7, children: const [
          _Legend(color: Color(0xFF356B7E), label: 'ثبت واقعی'),
          _Legend(color: Color(0xFFCE9657), label: 'تزریق فرضی'),
          _Legend(color: Color(0xFF14A694), label: 'پنجره احتمالی'),
          _Legend(color: Color(0xFF8A79BE), label: 'هدف دامپزشک'),
        ]),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min,
    children: [Container(width: 11, height: 11,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 11, color: _chartInk))]);
}

class _ScenarioPainter extends CustomPainter {
  final DateTime start, end;
  final List<BreedingEvent> events;
  final ReproScenarioResult result;
  final DateTime? injection, target;
  const _ScenarioPainter({required this.start, required this.end,
    required this.events, required this.result, this.injection, this.target});
  @override
  void paint(Canvas canvas, Size size) {
    final x0 = 15.0, x1 = size.width - 15;
    final total = end.difference(start).inMilliseconds.toDouble();
    if (total <= 0 || x1 <= x0) return;
    double pos(DateTime at) => (x0 +
      at.difference(start).inMilliseconds / total * (x1 - x0)).clamp(x0, x1).toDouble();
    final axis = Paint()..color = const Color(0xFFCADBE2)..strokeWidth = 3;
    canvas.drawLine(Offset(x0, 33), Offset(x1, 33), axis);
    canvas.drawLine(Offset(x0, 90), Offset(x1, 90), axis);
    final textStyle = TextStyle(color: _chartInk.withValues(alpha: .7), fontSize: 10);
    void text(String label, double x, double y) {
      final painter = TextPainter(text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr, maxLines: 1)..layout(maxWidth: size.width);
      painter.paint(canvas, Offset(x, y));
    }
    text('RECORDS', x0, 6);
    text('WHAT IF', x0, 64);
    for (final e in events) {
      final x = pos(e.at);
      canvas.drawCircle(Offset(x, 33), 4.5,
        Paint()..color = const Color(0xFF356B7E));
    }
    for (final w in result.windows) {
      final a = pos(w.start), b = pos(w.end);
      final color = w.category == 'ovulation' ? _chartTeal :
        w.category == 'estrus' ? const Color(0xFF78B4DE) : const Color(0xFF9FBCB2);
      final lo = math.min(a, b), hi = math.max(a, b);
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(lo, 81, math.max(hi - lo, 4.0), 18),
        const Radius.circular(6)), Paint()..color = color.withValues(alpha: .72));
    }
    if (injection != null) {
      final x = pos(injection!);
      canvas.drawLine(Offset(x, 61), Offset(x, 111),
        Paint()..color = const Color(0xFFCE9657)..strokeWidth = 2);
      canvas.drawCircle(Offset(x, 90), 5,
        Paint()..color = const Color(0xFFCE9657));
    }
    if (target != null) {
      final x = pos(target!);
      canvas.drawLine(Offset(x, 12), Offset(x, 113),
        Paint()..color = const Color(0xFF8A79BE)..strokeWidth = 2);
    }
  }
  @override
  bool shouldRepaint(covariant _ScenarioPainter old) =>
      start != old.start || end != old.end || injection != old.injection ||
      target != old.target || events.length != old.events.length ||
      result.windows != old.result.windows;
}

/// Purely educational normalized curves. These NEVER represent hormone assays
/// for the selected mare and must not be used to infer an ovulation date.
class EquineHormoneCycleChart extends StatelessWidget {
  final String scenario;
  const EquineHormoneCycleChart({super.key, this.scenario = 'none'});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white,
      border: Border.all(color: const Color(0xFFE0ECEF)),
      borderRadius: BorderRadius.circular(17)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Hormone physiology · نمودار شماتیک سیکل',
        style: TextStyle(fontSize: 14, color: _chartInk, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      const Text('استروژن، پروژسترون و LH — مقادیر نسبی آموزشی، نه آزمایش همین مادیان',
        style: TextStyle(fontSize: 11, color: Color(0xFF708391))),
      const SizedBox(height: 8),
      const SizedBox(height: 128, width: double.infinity,
        child: CustomPaint(painter: _HormonePainter())),
      const SizedBox(height: 6),
      Wrap(spacing: 11, runSpacing: 7, children: const [
        _Legend(color: Color(0xFF1D9E92), label: 'Estrogen'),
        _Legend(color: Color(0xFF8266BA), label: 'Progesterone'),
        _Legend(color: Color(0xFFE5A852), label: 'LH (schematic)'),
      ]),
      const SizedBox(height: 7),
      Text(scenario == 'pg' || scenario == 'sequence'
          ? 'PGF₂α (در صورت لوتئولیز موفق): کاهش فعالیت جسم زرد و P₄؛ سپس احتمال بازگشت فحلی. خطوط بالا منحنی پیش‌بینی‌شدهٔ این بیمار نیستند.'
          : scenario == 'hcg' || scenario == 'gnrh'
              ? 'القا (در صورت آمادگی فولیکول): هدف، زمان‌بندی تخمک‌گذاری است؛ منحنی E₂ / LH / P₄ برای این مادیان از تزریق محاسبه نمی‌شود.'
              : 'بدون القا: سیکل طبیعی با تغییرات فردی و فصلی؛ خطوط بالا زمان تخمک‌گذاری این مادیان را نشان نمی‌دهند.',
        style: const TextStyle(fontSize: 11, color: _chartInk, height: 1.4)),
      const SizedBox(height: 7),
      const Text('نمودار ۲۱ روزه فقط یک نمای آموزشی از سیکل معمول است؛ با ثبت آزمایش هورمونی، دادهٔ واقعی باید جدا رسم شود.',
        style: TextStyle(fontSize: 10.5, color: Color(0xFF708391), height: 1.4)),
    ]),
  );
}

class _HormonePainter extends CustomPainter {
  const _HormonePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final left = 22.0, top = 9.0, bottom = size.height - 20;
    final width = size.width - left - 8, height = bottom - top;
    if (width < 20 || height < 20) return;
    final grid = Paint()..color = const Color(0xFFDDE8EA)..strokeWidth = .7;
    for (var i = 0; i <= 3; i++) {
      final y = top + i * height / 3;
      canvas.drawLine(Offset(left, y), Offset(left + width, y), grid);
    }
    double gauss(double x, double center, double spread) =>
      math.exp(-math.pow((x - center) / spread, 2).toDouble());
    double est(double day) => (.12 + .81 * gauss(day, 19.7, 3.1) +
        .27 * gauss(day, 1.0, 2.2)).clamp(0.0, 1.0).toDouble();
    double progesterone(double day) => (.08 +
      .85 / (1 + math.exp(-(day - 3.8) * 1.2)) *
      (1 - 1 / (1 + math.exp(-(day - 15.0) * 1.5)))).clamp(0.0, 1.0).toDouble();
    double lh(double day) => (.10 + .70 * gauss(day, 20.5, 2.4) +
        .14 * gauss(day, 1.0, 1.8)).clamp(0.0, 1.0).toDouble();
    void line(double Function(double) fn, Color color) {
      final path = Path();
      for (var i = 0; i <= 100; i++) {
        final d = i / 100 * 21;
        final x = left + (d / 21) * width;
        final y = bottom - fn(d) * height;
        if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
      }
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke
        ..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    }
    line(est, const Color(0xFF1D9E92));
    line(progesterone, const Color(0xFF8266BA));
    line(lh, const Color(0xFFE5A852));
    final style = TextStyle(fontSize: 10, color: _chartInk.withValues(alpha:.8));
    for (final day in [0, 5, 10, 15, 21]) {
      final p = TextPainter(text: TextSpan(text: '$day', style: style),
        textDirection: TextDirection.ltr)..layout();
      p.paint(canvas, Offset(left + day / 21 * width - 4, bottom + 4));
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
