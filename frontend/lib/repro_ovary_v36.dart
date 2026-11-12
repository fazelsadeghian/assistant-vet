import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'repro_local_store.dart';
import 'repro_jalali_v35.dart';

/// Symbolic ovarian view: each colored circle corresponds to one recorded
/// structure. Radius tracks clinician-entered diameter, not actual anatomy.
class ReproOvaryMultiV36 extends StatelessWidget {
  final String name;
  final List<OvarianStructure> structures;
  final bool? clAssessed;
  const ReproOvaryMultiV36({super.key, required this.name,
    required this.structures, required this.clAssessed});

  @override
  Widget build(BuildContext context) {
    final follicles = structures.where((s) => s.kind == 'follicle').length;
    final cls = structures.where((s) => s.kind == 'cl').length;
    final chs = structures.where((s) => s.kind == 'ch').length;
    return Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF2F8F9),
        borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(name, style: const TextStyle(fontSize: 14,
            color: Color(0xFF173B4B), fontWeight: FontWeight.w800))),
          Text('F$follicles · CL$cls · CH$chs',
            style: const TextStyle(color: Color(0xFF647F86), fontSize: 11)),
        ]),
        const SizedBox(height: 5),
        SizedBox(height: 154, width: double.infinity,
          child: CustomPaint(painter: _OvaryMultiPainter(structures))),
        if (structures.isEmpty) Text(
          clAssessed == false ? 'CL مشاهده نشد؛ ساختار دیگری ثبت نشده' :
          'ساختار ثبت نشده / ارزیابی کامل نیست',
          style: const TextStyle(color: Color(0xFF687E87), fontSize: 11)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < structures.length; i++)
            _StructureTag(s: structures[i], ordinal: structures
              .take(i + 1).where((s) => s.kind == structures[i].kind).length),
        ]),
        const SizedBox(height: 4),
        const Text('فولیکول: آبی · CL: زرد · CH: نارنجی. شماتیک، تصویر واقعی سونو نیست.',
          style: TextStyle(color: Color(0xFF647F86), fontSize: 10)),
      ]));
  }
}

class _StructureTag extends StatelessWidget {
  final OvarianStructure s;
  final int ordinal;
  const _StructureTag({required this.s, required this.ordinal});
  @override Widget build(BuildContext context) {
    final name = s.kind == 'follicle' ? 'F$ordinal' :
      s.kind == 'cl' ? 'CL$ordinal' : 'CH${s.chGrade ?? '؟'}';
    final mm = s.meanDiameterMm;
    final color = s.kind == 'follicle' ? const Color(0xFFD4EEF5) :
      s.kind == 'cl' ? const Color(0xFFFFE7A6) : const Color(0xFFFCE0CD);
    return Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(color: color,
        borderRadius: BorderRadius.circular(8)),
      child: Text('$name${mm == null ? '' : ' · ${ReproJalali.persianDigits(mm.toStringAsFixed(1))} mm'}',
        style: const TextStyle(fontSize: 10, color: Color(0xFF173B4B),
          fontWeight: FontWeight.w700)));
  }
}

class _OvaryMultiPainter extends CustomPainter {
  final List<OvarianStructure> items;
  const _OvaryMultiPainter(this.items);
  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rx = math.min(size.width * .44, 180.0);
    final ry = size.height * .41;
    final ovary = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);
    canvas.drawOval(ovary, Paint()..color = const Color(0xFFF0D0C7));
    canvas.drawOval(ovary, Paint()..color = const Color(0xFFC5958A)
      ..style = PaintingStyle.stroke..strokeWidth = 1.7);
    const spots = <Offset>[
      Offset(-.48, -.22), Offset(.35, -.19), Offset(-.05, .42),
      Offset(.46, .30), Offset(-.61, .22), Offset(.05, -.45),
      Offset(-.21, -.11), Offset(.62, -.10),
    ];
    final shown = items.take(spots.length).toList();
    // Local visual radius is proportional to entered diameter. For many
    // structures scale down so circles fit the illustrative layout.
    final crowdScale = shown.length > 5 ? .72 : 1.0;
    var fIndex = 0, clIndex = 0;
    for (var i = 0; i < shown.length; i++) {
      final item = shown[i];
      final mm = item.meanDiameterMm;
      final r = ((mm == null ? 11.0 : 5.0 + mm * .45) * crowdScale)
          .clamp(6.0, ry * .40).toDouble();
      final spot = spots[i];
      final c = center + Offset(spot.dx * rx, spot.dy * ry);
      final shade = item.kind == 'follicle' ? const Color(0xFF8ACCD9) :
        item.kind == 'cl' ? const Color(0xFFFFD15E) : const Color(0xFFECA777);
      final border = item.kind == 'follicle' ? const Color(0xFF317D97) :
        item.kind == 'cl' ? const Color(0xFF9D7A2A) : const Color(0xFFAD6438);
      canvas.drawCircle(c, r, Paint()..color = shade);
      canvas.drawCircle(c, r, Paint()..color = border
        ..style = PaintingStyle.stroke..strokeWidth = 1.8);
      final text = item.kind == 'follicle' ? 'F${++fIndex}' :
        item.kind == 'cl' ? 'CL${++clIndex}' : 'CH';
      final painter = TextPainter(text: TextSpan(text: text,
        style: const TextStyle(color: Color(0xFF193D4B),
          fontWeight: FontWeight.w800, fontSize: 10)),
        textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas, c - Offset(painter.width / 2, painter.height / 2));
    }
    if (items.length > shown.length) {
      final painter = TextPainter(text: TextSpan(
        text: '+${items.length - shown.length} structures',
        style: const TextStyle(fontSize: 11, color: Color(0xFF173B4B))),
        textDirection: TextDirection.ltr)..layout();
      painter.paint(canvas, Offset(8, size.height - 16));
    }
  }
  @override
  bool shouldRepaint(covariant _OvaryMultiPainter old) => old.items != items;
}
