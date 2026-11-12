import 'package:flutter/material.dart';
import 'repro_local_store.dart';
import 'repro_jalali_v35.dart';

/// Rapid multi-structure ultrasound entry. Data are entered by a clinician;
/// these shapes and CH grades are descriptive, not automated diagnosis.
class _DraftOvaryItem {
  final String id;
  final String kind;
  final TextEditingController diameter = TextEditingController();
  final TextEditingController second = TextEditingController();
  int chGrade = 1;
  bool dominant = false;

  _DraftOvaryItem(this.kind, {String? id}) : id = id ?? newReproId();

  factory _DraftOvaryItem.fromStructure(OvarianStructure structure) {
    final item = _DraftOvaryItem(structure.kind, id: structure.id);
    if (structure.diameterMm != null) {
      item.diameter.text = structure.diameterMm!.toStringAsFixed(
          structure.diameterMm!.truncateToDouble() == structure.diameterMm ? 0 : 1);
    }
    if (structure.secondDiameterMm != null) {
      item.second.text = structure.secondDiameterMm!.toStringAsFixed(
          structure.secondDiameterMm!.truncateToDouble() == structure.secondDiameterMm ? 0 : 1);
    }
    item.chGrade = structure.chGrade ?? 1;
    item.dominant = structure.dominant;
    return item;
  }

  void dispose() {
    diameter.dispose();
    second.dispose();
  }
}

Future<BreedingEvent?> recordEquineScanV36(
  BuildContext context,
  ReproLocalStore store, {
  BreedingEvent? original,
}) async {
  final left = <_DraftOvaryItem>[];
  final right = <_DraftOvaryItem>[];
  final allocated = <_DraftOvaryItem>[];
  final note = TextEditingController(text: original?.details ?? '');
  DateTime at = original?.at ?? DateTime.now();
  int edema = original?.edemaScore ?? -1;
  int behaviour = original?.estrusScore ?? -1;
  String cervix = original?.cervixStatus ?? 'not_assessed';
  String fluid = original?.uterineFluid ?? 'not_assessed';
  String leftClStatus = original == null
      ? 'unknown'
      : (original.leftCl == true
          ? 'present'
          : original.leftCl == false
              ? 'absent'
              : 'unknown');
  String rightClStatus = original == null
      ? 'unknown'
      : (original.rightCl == true
          ? 'present'
          : original.rightCl == false
              ? 'absent'
              : 'unknown');
  String imagePath = original?.imagePath ?? '';
  bool sameLeft = original?.sameLeftFollicle ?? false;
  bool sameRight = original?.sameRightFollicle ?? false;
  String error = '';

  void seed(List<_DraftOvaryItem> into, List<OvarianStructure> source) {
    for (final structure in source) {
      final item = _DraftOvaryItem.fromStructure(structure);
      allocated.add(item);
      into.add(item);
    }
  }

  if (original != null) {
    seed(left, original.leftStructures);
    seed(right, original.rightStructures);
  }

  void add(List<_DraftOvaryItem> values, String kind, StateSetter update) {
    update(() {
      final item = _DraftOvaryItem(kind);
      allocated.add(item);
      if (kind == 'follicle' && !values.any((e) => e.kind == 'follicle' && e.dominant)) {
        item.dominant = true;
      }
      values.add(item);
      if (kind == 'cl') {
        if (identical(values, left)) {
          leftClStatus = 'present';
        } else {
          rightClStatus = 'present';
        }
      }
      error = '';
    });
  }

  Widget ovaryPanel(
    String heading,
    List<_DraftOvaryItem> entries,
    String clStatus,
    bool sameFollicle,
    StateSetter update,
    ValueChanged<String> onClStatus,
    ValueChanged<bool> onSameFollicle,
  ) {
    int follicleIndex = 0;
    int clIndex = 0;
    int chIndex = 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F7F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(heading,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF173B4B))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          OutlinedButton.icon(
              onPressed: () => add(entries, 'follicle', update),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('فولیکول')),
          OutlinedButton.icon(
              onPressed: () => add(entries, 'cl', update),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('CL')),
          OutlinedButton.icon(
              onPressed: () => add(entries, 'ch', update),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('CH')),
        ]),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 9),
            child: Text(
              'برای هر ساختار روی + بزنید؛ می‌توانید چند فولیکول و چند CL ثبت کنید.',
              style: TextStyle(fontSize: 11, color: Color(0xFF647F86)),
            ),
          ),
        for (final item in entries)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Builder(builder: (ctx) {
              final label = item.kind == 'follicle'
                  ? 'F${++follicleIndex} · فولیکول'
                  : item.kind == 'cl'
                      ? 'CL${++clIndex} · جسم زرد'
                      : 'CH${++chIndex} · جسم خونریزی‌دهنده';
              return Container(
                key: ValueKey(item.id),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFFE2EBEA)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                        child: Text(label,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                    IconButton(
                        tooltip: 'حذف ساختار',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, color: Color(0xFF9C5151), size: 18),
                        onPressed: () => update(() {
                              entries.remove(item);
                              if (item.kind == 'cl' && !entries.any((s) => s.kind == 'cl')) {
                                onClStatus('unknown');
                              }
                            })),
                  ]),
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: item.diameter,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          isDense: true,
                          labelText: 'قطر اول mm${item.kind == 'ch' ? ' (اختیاری)' : ''}'),
                    )),
                    if (item.kind == 'follicle') ...[
                      const SizedBox(width: 7),
                      Expanded(
                          child: TextField(
                        controller: item.second,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            const InputDecoration(isDense: true, labelText: 'قطر دوم mm (اختیاری)'),
                      )),
                    ],
                    if (item.kind == 'ch') ...[
                      const SizedBox(width: 7),
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<int>(
                          initialValue: item.chGrade,
                          isExpanded: true,
                          decoration: const InputDecoration(isDense: true, labelText: 'CH'),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('CH1')),
                            DropdownMenuItem(value: 2, child: Text('CH2')),
                            DropdownMenuItem(value: 3, child: Text('CH3')),
                          ],
                          onChanged: (v) => item.chGrade = v ?? 1,
                        ),
                      ),
                    ],
                  ]),
                  if (item.kind == 'follicle')
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: item.dominant,
                      title: const Text('فولیکول غالب', style: TextStyle(fontSize: 11)),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          for (final sibling in entries.where((e) => e.kind == 'follicle')) {
                            sibling.dominant = false;
                          }
                        }
                        item.dominant = v ?? false;
                      }),
                    ),
                ]),
              );
            }),
          ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String>(
          key: ValueKey('$heading:$clStatus'),
          initialValue: clStatus,
          isExpanded: true,
          decoration: const InputDecoration(
              isDense: true, labelText: 'وضعیت بررسی CL (مستقل از تعداد ساختارها)'),
          items: const [
            DropdownMenuItem(value: 'unknown', child: Text('ارزیابی نشده')),
            DropdownMenuItem(value: 'absent', child: Text('بررسی شد؛ مشاهده نشد')),
            DropdownMenuItem(value: 'present', child: Text('مشاهده شد')),
          ],
          onChanged: (v) => update(() {
            final selected = v ?? 'unknown';
            onClStatus(selected);
            if (selected == 'present' && !entries.any((item) => item.kind == 'cl')) {
              final cl = _DraftOvaryItem('cl');
              allocated.add(cl);
              entries.add(cl);
            }
          }),
        ),
        if (entries.any((e) => e.kind == 'follicle'))
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: sameFollicle,
            title: const Text('ادامه همان فولیکولِ سونوی قبلی در این تخمدان',
                style: TextStyle(fontSize: 11)),
            onChanged: (v) => update(() => onSameFollicle(v ?? false)),
          ),
      ]),
    );
  }

  final approved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (outer) => StatefulBuilder(builder: (ctx, update) {
      return AlertDialog(
        title: Text(original == null
            ? 'ثبت سریع سونوگرافی مادیان'
            : 'ویرایش سونوگرافی انتخاب‌شده · ${ReproJalali.stamp(at)}'),
        content: SizedBox(
          width: 830,
          height: MediaQuery.of(ctx).size.height * .69,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text('تاریخ و ساعت: ${ReproJalali.stamp(at)}'),
                onPressed: () async {
                  final picked = await ReproJalali.pickDateTime(ctx, at);
                  if (picked != null) update(() => at = picked);
                },
              ),
              const SizedBox(height: 10),
              LayoutBuilder(builder: (inner, limits) {
                final leftPanel = ovaryPanel(
                  'تخمدان چپ',
                  left,
                  leftClStatus,
                  sameLeft,
                  update,
                  (v) => leftClStatus = v,
                  (v) => sameLeft = v,
                );
                final rightPanel = ovaryPanel(
                  'تخمدان راست',
                  right,
                  rightClStatus,
                  sameRight,
                  update,
                  (v) => rightClStatus = v,
                  (v) => sameRight = v,
                );
                if (limits.maxWidth < 640) {
                  return Column(children: [leftPanel, const SizedBox(height: 8), rightPanel]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: leftPanel),
                  const SizedBox(width: 10),
                  Expanded(child: rightPanel),
                ]);
              }),
              const SizedBox(height: 15),
              const Text('رحم و سرویکس', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Text(
                'UE ۰ تا ۵ = ادم آندومتر. رفتار فحلی ۰ تا ۴ = پاسخ به نریان؛ این دو متفاوت‌اند.',
                style: TextStyle(color: Color(0xFF687C85), fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 9, runSpacing: 9, children: [
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<int>(
                    initialValue: edema,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'ادم رحم UE0–UE5', isDense: true),
                    items: [
                      const DropdownMenuItem(value: -1, child: Text('ارزیابی نشده')),
                      for (var i = 0; i <= 5; i++) DropdownMenuItem(value: i, child: Text('UE$i')),
                    ],
                    onChanged: (v) => update(() => edema = v ?? -1),
                  ),
                ),
                SizedBox(
                  width: 185,
                  child: DropdownButtonFormField<int>(
                    initialValue: behaviour,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'رفتار پذیرش نریان ۰–۴', isDense: true),
                    items: [
                      const DropdownMenuItem(value: -1, child: Text('ارزیابی نشده')),
                      for (var i = 0; i <= 4; i++) DropdownMenuItem(value: i, child: Text('$i')),
                    ],
                    onChanged: (v) => update(() => behaviour = v ?? -1),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: cervix,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'سرویکس', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'not_assessed', child: Text('ارزیابی نشده')),
                      DropdownMenuItem(value: 'open', child: Text('باز')),
                      DropdownMenuItem(value: 'relaxed', child: Text('نرم/شل')),
                      DropdownMenuItem(value: 'closed', child: Text('بسته')),
                    ],
                    onChanged: (v) => update(() => cervix = v ?? 'not_assessed'),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                    initialValue: fluid,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'مایع داخل رحم', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'not_assessed', child: Text('ارزیابی نشده')),
                      DropdownMenuItem(value: 'absent', child: Text('مشاهده نشد')),
                      DropdownMenuItem(value: 'present', child: Text('مشاهده شد')),
                    ],
                    onChanged: (v) => update(() => fluid = v ?? 'not_assessed'),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'یادداشت و یافته‌های غیرطبیعی')),
              OutlinedButton.icon(
                onPressed: () async {
                  final path = await store.selectImage();
                  if (path != null) update(() => imagePath = path);
                },
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(imagePath.isEmpty ? 'تصویر سونو (اختیاری)' : 'تصویر انتخاب شد / قابل تعویض'),
              ),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
              onPressed: () {
                final structures = [...left, ...right];
                if (structures.isEmpty && leftClStatus == 'unknown' && rightClStatus == 'unknown') {
                  update(() => error = 'حداقل یک یافته تخمدانی ثبت کنید.');
                  return;
                }
                for (final item in structures) {
                  final d = reproDouble(item.diameter.text);
                  final d2 = reproDouble(item.second.text);
                  if ((item.kind != 'ch' && d == null) ||
                      (d != null && (d <= 0 || d > 150)) ||
                      (item.second.text.trim().isNotEmpty && (d2 == null || d2 <= 0 || d2 > 150))) {
                    update(() => error = 'برای هر ساختار اندازه معتبر ۱ تا ۱۵۰ میلی‌متر ثبت کنید.');
                    return;
                  }
                }
                if ((leftClStatus == 'absent' && left.any((e) => e.kind == 'cl')) ||
                    (rightClStatus == 'absent' && right.any((e) => e.kind == 'cl'))) {
                  update(() => error = 'CL ثبت شده با گزینه «مشاهده نشد» مغایرت دارد.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(original == null ? 'ذخیره سونو' : 'ثبت ویرایش')),
        ],
      );
    }),
  );

  try {
    if (approved != true) return null;
    List<OvarianStructure> structures(List<_DraftOvaryItem> items) => items
        .map((s) => OvarianStructure(
              id: s.id,
              kind: s.kind,
              diameterMm: reproDouble(s.diameter.text),
              secondDiameterMm: s.kind == 'follicle' ? reproDouble(s.second.text) : null,
              chGrade: s.kind == 'ch' ? s.chGrade : null,
              dominant: s.kind == 'follicle' && s.dominant,
            ))
        .toList();

    final l = structures(left), r = structures(right);

    double? biggest(List<OvarianStructure> items) {
      final sizes = items
          .where((e) => e.kind == 'follicle')
          .map((e) => e.meanDiameterMm)
          .whereType<double>()
          .toList();
      if (sizes.isEmpty) return null;
      sizes.sort();
      return sizes.last;
    }

    double? firstCl(List<OvarianStructure> items) {
      for (final item in items) {
        if (item.kind == 'cl') return item.diameterMm;
      }
      return null;
    }

    int? firstCh(List<OvarianStructure> items) {
      for (final item in items) {
        if (item.kind == 'ch') return item.chGrade;
      }
      return null;
    }

    bool? clFlag(String status, List<OvarianStructure> items) => items.any((e) => e.kind == 'cl')
        ? true
        : status == 'absent'
            ? false
            : null;

    final lc = clFlag(leftClStatus, l), rc = clFlag(rightClStatus, r);
    return BreedingEvent(
      id: original?.id ?? newReproId(),
      at: at,
      type: 'ultrasound',
      leftStructures: l,
      rightStructures: r,
      leftFollicleMm: biggest(l),
      rightFollicleMm: biggest(r),
      leftCl: lc,
      rightCl: rc,
      leftClMm: firstCl(l),
      rightClMm: firstCl(r),
      leftChGrade: firstCh(l),
      rightChGrade: firstCh(r),
      sameLeftFollicle: sameLeft,
      sameRightFollicle: sameRight,
      leftShape: original?.leftShape ?? 'unknown',
      rightShape: original?.rightShape ?? 'unknown',
      corpusLuteum: lc == true || rc == true
          ? 'present'
          : lc == false && rc == false
              ? 'absent'
              : 'not_assessed',
      edemaScore: edema < 0 ? null : edema,
      estrusScore: behaviour < 0 ? null : behaviour,
      cervixStatus: cervix,
      uterineFluid: fluid,
      details: note.text.trim(),
      plannedByVet: original?.plannedByVet ?? false,
      imagePath: imagePath.isEmpty
          ? ''
          : (imagePath == original?.imagePath ? imagePath : await store.importImage(imagePath)),
    );
  } finally {
    for (final item in allocated) {
      item.dispose();
    }
    note.dispose();
  }
}
