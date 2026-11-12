import 'dart:io';
import 'package:flutter/material.dart';
import 'repro_local_store.dart';

class ProstateSizePage extends StatefulWidget {
  const ProstateSizePage({super.key});
  @override
  State<ProstateSizePage> createState() => _ProstateSizePageState();
}

class _ProstateSizePageState extends State<ProstateSizePage> {
  static const ink = Color(0xFF13374A);
  static const teal = Color(0xFF008D83);
  final _store = ReproLocalStore();
  final _dog = TextEditingController();
  final _id = TextEditingController();
  final _weight = TextEditingController();
  final _age = TextEditingController();
  final _direct = TextEditingController();
  final _length = TextEditingController();
  final _width = TextEditingController();
  final _height = TextEditingController();
  final _notes = TextEditingController();
  List<ProstateObservation> _history = [];
  bool _loading = true, _saving = false, _directMode = true, _millimetres = false;
  String _neuter = 'intact';
  String _referenceMode = 'weight';
  String _image = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _store.loadProstates();
      if (mounted) setState(() { _history = data; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _message('خواندن سوابق ممکن نشد: $e', error: true);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_dog, _id, _weight, _age, _direct, _length, _width,
      _height, _notes]) { c.dispose(); }
    super.dispose();
  }

  double? _num(TextEditingController value) =>
      double.tryParse(value.text.trim().replaceAll(',', '.'));
  double? get _weightValue => _num(_weight);
  double? get _ageValue => _num(_age);
  double? get _measured {
    if (_directMode) {
      final d = _num(_direct);
      return d != null && d > 0 ? d : null;
    }
    final l = _num(_length), w = _num(_width), h = _num(_height);
    if (l == null || w == null || h == null ||
        l <= 0 || w <= 0 || h <= 0) return null;
    final factor = _millimetres ? 0.1 : 1.0;
    return 0.523 * (l * factor) * (w * factor) * (h * factor);
  }
  double? get _estimateWeight {
    final w = _weightValue;
    return w == null || w <= 0 ? null : 0.33 * w + 3.28;
  }
  double? get _estimateAgeWeight {
    final w = _weightValue, a = _ageValue;
    if (w == null || a == null || w <= 0 || a < 0) return null;
    return 0.867 * w + 1.885 * a + 15.188;
  }

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? const Color(0xFFB44737) : teal,
      content: Text(message),
    ));
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _store.selectImage();
      if (picked != null && mounted) setState(() => _image = picked);
    } catch (e) {
      if (mounted) _message('انتخاب تصویر ناموفق بود: $e', error: true);
    }
  }

  Future<void> _save() async {
    final measured = _measured;
    final weight = _weightValue;
    final age = _ageValue ?? 0;
    if (_dog.text.trim().isEmpty || measured == null ||
        weight == null || weight <= 0 || age < 0 ||
        (_age.text.trim().isNotEmpty && _ageValue == null)) {
      _message('نام بیمار، وزن و حجم معتبر را وارد کنید.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final imagePath = _image.isEmpty ? '' : await _store.importImage(_image);
      final item = ProstateObservation(
        id: newReproId(), at: DateTime.now(),
        dogName: _dog.text.trim(), reference: _id.text.trim(),
        weightKg: weight, ageYears: age,
        neuterStatus: _neuter, measuredCm3: measured,
        lengthCm: _directMode ? null : (_num(_length) == null ? null : _num(_length)! * (_millimetres ? 0.1 : 1)),
        widthCm: _directMode ? null : (_num(_width) == null ? null : _num(_width)! * (_millimetres ? 0.1 : 1)),
        heightCm: _directMode ? null : (_num(_height) == null ? null : _num(_height)! * (_millimetres ? 0.1 : 1)),
        method: _directMode ? 'manual' : 'ellipsoid_0.523',
        imagePath: imagePath, notes: _notes.text.trim(),
      );
      final values = [item, ..._history];
      await _store.saveProstates(values);
      if (mounted) {
        setState(() { _history = values; _image = ''; _saving = false; });
        _message('اندازه‌گیری و تصویر همراه آن روی این کامپیوتر ذخیره شد.');
      }
    } catch (e) {
      if (mounted) { setState(() => _saving = false); _message('ذخیره ناموفق بود: $e', error: true); }
    }
  }

  Future<void> _viewSaved(ProstateObservation item) async {
    final hasDimensions = item.lengthCm != null && item.widthCm != null && item.heightCm != null;
    final action = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text('پرونده پروستات · ${item.dogName}'),
      content: SizedBox(width: 490, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Text('تاریخ ثبت: ${_date(item.at)}'),
          Text('شناسه: ${item.reference.isEmpty ? 'ثبت نشده' : item.reference}'),
          Text('وزن: ${item.weightKg.toStringAsFixed(1)} kg · سن: ${item.ageYears.toStringAsFixed(1)} سال'),
          Text('وضعیت عقیم‌سازی: ${item.neuterStatus}'),
          const SizedBox(height: 9),
          Text('حجم ثبت‌شده: ${item.measuredCm3.toStringAsFixed(2)} cm³',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: teal)),
          Text(hasDimensions
            ? 'ابعاد ثبت‌شده: طول ${item.lengthCm!.toStringAsFixed(1)} × عرض ${item.widthCm!.toStringAsFixed(1)} × ارتفاع ${item.heightCm!.toStringAsFixed(1)} cm'
            : 'ابعاد طول/عرض/ارتفاع در این ثبت قدیمی ذخیره نشده‌اند؛ حجم ثبت‌شده همچنان موجود است.'),
          Text('روش محاسبه: ${item.method}'),
          if (item.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8), Text('یادداشت: ${item.notes}'),
          ],
          if (item.imagePath.isNotEmpty) ...[
            const SizedBox(height: 12),
            Image.file(File(item.imagePath), height: 180, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('فایل تصویر در مسیر قبلی پیدا نشد')),
          ],
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: const Text('بستن')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'load'),
          child: const Text('بارگذاری در فرم برای اندازه‌گیری جدید')),
      ],
    ));
    if (action != 'load' || !mounted) return;
    setState(() {
      _dog.text = item.dogName;
      _id.text = item.reference;
      _weight.text = item.weightKg.toString();
      _age.text = item.ageYears.toString();
      _neuter = item.neuterStatus;
      _notes.text = item.notes;
      _image = item.imagePath;
      _directMode = !hasDimensions;
      _millimetres = false;
      _direct.text = item.measuredCm3.toStringAsFixed(2);
      _length.text = item.lengthCm?.toStringAsFixed(1) ?? '';
      _width.text = item.widthCm?.toStringAsFixed(1) ?? '';
      _height.text = item.heightCm?.toStringAsFixed(1) ?? '';
    });
    _message('مشخصات پرونده در فرم قرار گرفت؛ ثبت بعدی رکورد جدید می‌سازد و سابقه قبلی را تغییر نمی‌دهد.');
  }

  Future<void> _delete(ProstateObservation item) async {
    final yes = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف اندازه‌گیری؟'),
        content: const Text('این ردیف از تاریخچه حذف می‌شود. تصویر در پوشهٔ محلی باقی می‌ماند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ));
    if (yes != true) return;
    final copy = _history.where((e) => e.id != item.id).toList();
    try {
      await _store.saveProstates(copy);
      if (mounted) setState(() => _history = copy);
    } catch (e) {
      if (mounted) _message('حذف انجام نشد: $e', error: true);
    }
  }

  String _date(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Widget _panel({required String title, required Widget child, IconData? icon}) =>
      Container(
        padding: const EdgeInsets.all(23),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDDE9EB)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, color: teal), const SizedBox(width: 9)],
            Expanded(child: Text(title, style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: ink))),
          ]),
          const SizedBox(height: 18), child,
        ]),
      );

  Widget _field(String label, TextEditingController controller,
      {bool number = false, String? hint}) => TextField(
        controller: controller,
        onChanged: (_) => setState(() {}),
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );

  String _formatCm3(double? volume) =>
      volume == null ? '—' : '${volume.toStringAsFixed(2)} cm³';

  Widget _comparisonHighlight(double? measured, double? expected) {
    final deviation = measured == null || expected == null || expected <= 0
        ? null : (measured - expected) * 100 / expected;
    // This ±10% visual band is a user-interface display choice, NOT a
    // clinical normal range or a diagnostic cutoff for canine disease.
    final state = deviation == null ? 0 : deviation > 10 ? 1 :
        deviation < -10 ? -1 : 0;
    final color = state > 0 ? const Color(0xFFB73E46) : state < 0
        ? const Color(0xFF08764C) : const Color(0xFF516B77);
    final bg = state > 0 ? const Color(0xFFFFEDEF) : state < 0
        ? const Color(0xFFE8F8EE) : const Color(0xFFF1F5F7);
    final status = deviation == null ? 'در انتظار اندازه‌گیری' : state > 0
        ? 'بالاتر از حجم برآوردی' : state < 0
        ? 'کمتر از حجم برآوردی' : 'نزدیک به حجم برآوردی';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .33), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.straighten_outlined, color: color, size: 22),
          const SizedBox(width: 9),
          Expanded(child: Text('MEASURED / حجم اندازه‌گیری‌شده',
            style: TextStyle(color: color, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 10),
        Text(measured == null ? '—' : '${measured.toStringAsFixed(2)} cm³',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
            color: color)),
        const SizedBox(height: 8),
        Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        if (deviation != null) ...[
          const SizedBox(height: 5),
          Text('${deviation >= 0 ? '+' : ''}${deviation.toStringAsFixed(1)}٪ نسبت به مدل انتخابی',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  Widget _metric(String label, double? value, {String? caption}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F9F8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12,
              color: Color(0xFF54737A), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value == null ? '—' : '${value.toStringAsFixed(2)} cm³',
              style: const TextStyle(fontSize: 22, color: ink,
                  fontWeight: FontWeight.w900)),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(caption, style: const TextStyle(fontSize: 11,
                color: Color(0xFF678088))),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final measured = _measured;
    final expected = _estimateWeight;
    final expected2 = _estimateAgeWeight;
    final referenceExpected = _referenceMode == 'age_weight' ? expected2 : expected;
    final sameDog = _history.where((v) =>
        (_id.text.trim().isNotEmpty && v.reference == _id.text.trim()) ||
        (_id.text.trim().isEmpty && _dog.text.trim().isNotEmpty &&
            v.dogName.toLowerCase() == _dog.text.trim().toLowerCase())).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF2F7F8),
      appBar: AppBar(
        backgroundColor: Colors.white, foregroundColor: ink,
        title: const Text('Canine Prostate · Size Tracker',
            style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(tooltip: 'Open local records / Backup',
            onPressed: () async {
              try { await _store.openDataFolder(); }
              catch (e) { if (mounted) _message('$e', error: true); }
            }, icon: const Icon(Icons.folder_open_outlined)),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF083D50), Color(0xFF117D80)]),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(children: [
                      Icon(Icons.monitor_heart_outlined, size: 44, color: Colors.white),
                      SizedBox(width: 20),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('PROSTATE ULTRASOUND',
                            style: TextStyle(color: Color(0xFFACF0DD), letterSpacing: 1.4)),
                        SizedBox(height: 6),
                        Text('Prostate Volume & Trend',
                            style: TextStyle(color: Colors.white,
                                fontSize: 26, fontWeight: FontWeight.w900)),
                        SizedBox(height: 5),
                        Text('اندازه‌گیری، مقایسهٔ عددی و ثبت مراجعات — نه تشخیص خودکار بیماری',
                            style: TextStyle(color: Color(0xFFDBECEE))),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(borderRadius: BorderRadius.circular(18),
                    child: SizedBox(height: 158, width: double.infinity,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.asset('assets/canine_prostate_ultrasound_illustration_v33.jpg',
                          fit: BoxFit.cover, alignment: Alignment.center,
                          errorBuilder: (ctx, error, stack) =>
                            const ColoredBox(color: Color(0xFF102F38))),
                        Positioned(left: 16, bottom: 12,
                          child: Container(padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(color: const Color(0xE6193845),
                              borderRadius: BorderRadius.circular(8)),
                            child: const Text('Canine Prostate Ultrasonography · illustrative image, not patient data',
                              style: TextStyle(color: Colors.white, fontSize: 12)))),
                      ]))),
                  const SizedBox(height: 18),
                  LayoutBuilder(builder: (context, bounds) {
                    final narrow = bounds.maxWidth < 860;
                    final entry = _panel(title: 'Patient & ultrasound',
                      icon: Icons.edit_note_rounded,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Wrap(spacing: 12, runSpacing: 12, children: [
                          SizedBox(width: 250, child: _field('نام سگ *', _dog)),
                          SizedBox(width: 190, child: _field('کد پرونده', _id)),
                          SizedBox(width: 160, child: _field('وزن (kg) *', _weight, number: true)),
                          SizedBox(width: 150, child: _field('سن (سال)', _age, number: true)),
                          SizedBox(width: 200, child: DropdownButtonFormField<String>(
                            initialValue: _neuter,
                            decoration: const InputDecoration(labelText: 'وضعیت عقیم‌سازی'),
                            items: const [
                              DropdownMenuItem(value: 'intact', child: Text('Intact')),
                              DropdownMenuItem(value: 'neutered', child: Text('Neutered')),
                              DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                            ],
                            onChanged: (v) => setState(() => _neuter = v ?? 'unknown'),
                          )),
                        ]),
                        const SizedBox(height: 22),
                        const Text('روش ورود حجم', style: TextStyle(fontWeight: FontWeight.w800, color: ink)),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(segments: const [
                          ButtonSegment(value: true, label: Text('ورود مستقیم حجم')),
                          ButtonSegment(value: false, label: Text('اندازه‌های سونو')),
                        ], selected: {_directMode},
                          onSelectionChanged: (values) => setState(() => _directMode = values.first)),
                        const SizedBox(height: 16),
                        if (_directMode)
                          SizedBox(width: 260, child: _field('حجم اندازه‌گیری‌شده (cm³)', _direct, number: true))
                        else ...[
                          Wrap(spacing: 12, runSpacing: 12, children: [
                            SizedBox(width: 150, child: _field('طول', _length, number: true)),
                            SizedBox(width: 150, child: _field('عرض', _width, number: true)),
                            SizedBox(width: 150, child: _field('ارتفاع', _height, number: true)),
                          ]),
                          const SizedBox(height: 12),
                          SwitchListTile.adaptive(
                            title: const Text('ورودی بر حسب میلی‌متر (mm)'),
                            subtitle: const Text('در حالت خاموش، ابعاد بر حسب سانتی‌متر است.'),
                            value: _millimetres,
                            onChanged: (v) => setState(() => _millimetres = v),
                          ),
                          const Text('V = 0.523 × طول × عرض × ارتفاع (cm³)',
                              style: TextStyle(color: teal, fontWeight: FontWeight.w700)),
                        ],
                        const SizedBox(height: 14),
                        TextField(controller: _notes, maxLines: 2,
                          decoration: const InputDecoration(labelText: 'یادداشت سونوگرافی / دامپزشک')),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(onPressed: _pickImage,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(_image.isEmpty ? 'انتخاب تصویر سونو' : 'تغییر تصویر')),
                        if (_image.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ClipRRect(borderRadius: BorderRadius.circular(14),
                            child: Image.file(File(_image), height: 125, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Text('تصویر قابل نمایش نیست'))),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'در حال ذخیره…' : 'Save measurement'),
                          style: FilledButton.styleFrom(backgroundColor: teal,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 19)),
                        ),
                      ]));
                    final result = _panel(title: 'Prostate volume · مقایسهٔ حجم',
                      icon: Icons.analytics_outlined,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('انتخاب مدل حجم مورد انتظار',
                          style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'weight', label: Text('بر اساس وزن')),
                            ButtonSegment(value: 'age_weight', label: Text('وزن و سن')),
                          ],
                          selected: {_referenceMode},
                          onSelectionChanged: (values) =>
                              setState(() => _referenceMode = values.first),
                        ),
                        const SizedBox(height: 12),
                        _metric('EXPECTED / حجم برآوردی', referenceExpected,
                          caption: _referenceMode == 'weight'
                            ? 'مدل وزنی: 0.33 × kg + 3.28'
                            : 'مدل وزن و سن: 0.867 × kg + 1.885 × years + 15.188'),
                        const SizedBox(height: 8),
                        Text(_referenceMode == 'weight'
                          ? 'مدل دیگر (وزن و سن): ${_formatCm3(expected2)}'
                          : 'مدل دیگر (وزن): ${_formatCm3(expected)}',
                          style: const TextStyle(color: Color(0xFF678088), fontSize: 12)),
                        const SizedBox(height: 20),
                        _comparisonHighlight(measured, referenceExpected),
                        const SizedBox(height: 14),
                        const Text('قرمز = بالاتر از برآورد، سبز = پایین‌تر و خاکستری = نزدیک به برآورد. بازهٔ ±۱۰٪ صرفاً برای نمایش بصری است و محدودهٔ طبیعی پزشکی محسوب نمی‌شود.',
                          style: TextStyle(height: 1.5, fontSize: 12,
                            color: Color(0xFF627E85))),
                        const SizedBox(height: 10),
                        const Text('این مقایسه به‌تنهایی بزرگی پروستات را تشخیص یا رد نمی‌کند؛ وضعیت عقیم‌سازی، معاینه و شکل و بافت سونوگرافی باید تفسیر شوند.',
                          style: TextStyle(height: 1.55,
                            color: Color(0xFF6D7F86))),
                      ]));
                    if (narrow) return Column(children: [entry,
                      const SizedBox(height: 14), result]);
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 6, child: entry),
                      const SizedBox(width: 16),
                      Expanded(flex: 4, child: result),
                    ]);
                  }),
                  const SizedBox(height: 18),
                  _panel(title: 'Patient trend & saved examinations',
                    icon: Icons.history_rounded,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(sameDog.isNotEmpty
                          ? 'پروندهٔ انتخاب‌شده: ${sameDog.length} اندازه‌گیری'
                          : 'با وارد کردن نام یا کد یک بیمار، سوابق مرتبط نمایش داده می‌شوند.',
                          style: const TextStyle(color: Color(0xFF668088))),
                      const SizedBox(height: 12),
                      if (sameDog.length >= 2)
                        SizedBox(height: 86, child: _ProstateTrend(
                          values: sameDog.reversed.map((e) => e.measuredCm3).toList())),
                      if (_history.isEmpty)
                        Padding(padding: const EdgeInsets.all(18),
                          child: Column(children: [
                            const Text('در پوشه ذخیره‌سازی فعلی سابقه پروستات یافت نشد. اگر قبلاً ذخیره کرده‌اید، پوشه داده‌ها و فایل prostate_history.json یا نسخه پشتیبان آن را بررسی کنید.'),
                            OutlinedButton.icon(onPressed: _store.openDataFolder,
                              icon: const Icon(Icons.folder_open_outlined),
                              label: const Text('باز کردن پوشه سوابق')),
                          ]))
                      else for (final entry in _history.take(50)) ...[
                        const Divider(color: Color(0xFFE7EEEE)),
                        Row(children: [
                          const CircleAvatar(backgroundColor: Color(0xFFE4F5F2),
                              child: Icon(Icons.pets_outlined, color: teal)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${entry.dogName} · ${entry.measuredCm3.toStringAsFixed(2)} cm³',
                              style: const TextStyle(color: ink, fontWeight: FontWeight.w800)),
                            Text('${_date(entry.at)}  ·  ${entry.method}  ·  ${entry.reference}',
                              style: const TextStyle(color: Color(0xFF779096), fontSize: 12)),
                          ])),
                          TextButton.icon(
                            onPressed: () => _viewSaved(entry),
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('مشاهده پرونده')),
                          if (entry.imagePath.isNotEmpty)
                            IconButton(tooltip: 'View ultrasound',
                              icon: const Icon(Icons.image_outlined, color: teal),
                              onPressed: () => showDialog<void>(context: context,
                                builder: (ctx) => Dialog(child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Image.file(File(entry.imagePath),
                                    errorBuilder: (_, __, ___) => const Text('تصویر یافت نشد.')),
                                )))),
                          IconButton(tooltip: 'Delete record',
                            onPressed: () => _delete(entry),
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFB25250))),
                        ]),
                      ],
                    ])),
                ])),
              )),
    );
  }
}

class _ProstateTrend extends StatelessWidget {
  final List<double> values;
  const _ProstateTrend({required this.values});
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _ProstateTrendPainter(values), child: const SizedBox.expand());
}

class _ProstateTrendPainter extends CustomPainter {
  final List<double> values;
  _ProstateTrendPainter(this.values);
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce((a, b) => a < b ? a : b);
    final hi = values.reduce((a, b) => a > b ? a : b);
    final range = (hi - lo).abs() < 0.01 ? 1.0 : hi - lo;
    final line = Paint()..color = const Color(0xFF078F88)
      ..strokeWidth = 3..style = PaintingStyle.stroke;
    final dots = Paint()..color = const Color(0xFF078F88);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final dx = 12 + i * (size.width - 24) / (values.length - 1);
      final dy = size.height - 12 - (values[i] - lo) / range * (size.height - 24);
      if (i == 0) { path.moveTo(dx, dy); } else { path.lineTo(dx, dy); }
      canvas.drawCircle(Offset(dx, dy), 4, dots);
    }
    canvas.drawPath(path, line);
  }
  @override
  bool shouldRepaint(covariant _ProstateTrendPainter old) =>
      old.values.length != values.length ||
      old.values.join(',') != values.join(',');
}
