import 'package:flutter/material.dart';

/// Gregorian storage (DateTime) with Persian/Jalali presentation.
/// Local time is used; no backend migration or change to stored timestamps.
class ReproJalali {
  static const months = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
  ];
  static const weekdays = [
    'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه',
  ];
  static const gDays = [31,28,31,30,31,30,31,31,30,31,30,31];
  static const jDays = [31,31,31,31,31,31,30,30,30,30,30,29];

  static List<int> fromGregorian(DateTime date) {
    final gy = date.year - 1600, gm = date.month - 1, gd = date.day - 1;
    var count = 365 * gy + (gy + 3) ~/ 4 - (gy + 99) ~/ 100 + (gy + 399) ~/ 400;
    for (var i = 0; i < gm; i++) { count += gDays[i]; }
    final leap = (gy + 1600) % 4 == 0 &&
        ((gy + 1600) % 100 != 0 || (gy + 1600) % 400 == 0);
    if (gm > 1 && leap) count++;
    count += gd;
    var day = count - 79;
    final cycle33 = day ~/ 12053;
    day %= 12053;
    var year = 979 + 33 * cycle33 + 4 * (day ~/ 1461);
    day %= 1461;
    if (day >= 366) {
      year += (day - 1) ~/ 365;
      day = (day - 1) % 365;
    }
    var month = 0;
    for (; month < 11; month++) {
      if (day < jDays[month]) break;
      day -= jDays[month];
    }
    return [year, month + 1, day + 1];
  }

  static DateTime toGregorian(int year, int month, int day,
      {int hour = 0, int minute = 0}) {
    final jy = year - 979;
    var count = 365 * jy + (jy ~/ 33) * 8 + ((jy % 33) + 3) ~/ 4;
    for (var i = 0; i < month - 1; i++) { count += jDays[i]; }
    count += day - 1 + 79;
    var gy = 1600 + 400 * (count ~/ 146097);
    count %= 146097;
    var leap = true;
    if (count >= 36525) {
      count--;
      gy += 100 * (count ~/ 36524);
      count %= 36524;
      if (count >= 365) count++;
      else leap = false;
    }
    gy += 4 * (count ~/ 1461);
    count %= 1461;
    if (count >= 366) {
      leap = false;
      count--;
      gy += count ~/ 365;
      count %= 365;
    }
    var gm = 0;
    while (gm < 12) {
      var len = gDays[gm];
      if (gm == 1 && leap) len++;
      if (count < len) break;
      count -= len;
      gm++;
    }
    return DateTime(gy, gm + 1, count + 1, hour, minute);
  }

  static String persianDigits(Object input) => input.toString().replaceAllMapped(
      RegExp(r'[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m.group(0)!)]);

  static String date(DateTime d, {bool weekday = false}) {
    final j = fromGregorian(d);
    final label = '${j[0]}/${j[1].toString().padLeft(2, '0')}/${j[2].toString().padLeft(2, '0')}';
    return persianDigits(weekday ? '${weekdays[d.weekday - 1]} $label' : label);
  }

  static String stamp(DateTime d) => '${date(d)}  ${persianDigits('${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}')}';

  static int daysInMonth(int year, int month) {
    if (month <= 6) return 31;
    if (month <= 11) return 30;
    final first = toGregorian(year, 1, 1);
    final next = toGregorian(year + 1, 1, 1);
    return next.difference(first).inDays == 366 ? 30 : 29;
  }

  /// Explicit Jalali picker: display and edit using the Iranian calendar.
  static Future<DateTime?> pickDateTime(BuildContext context, DateTime current) {
    final j = fromGregorian(current);
    int year = j[0], month = j[1], day = j[2];
    var hour = current.hour, minute = current.minute;
    return showDialog<DateTime>(context: context, builder: (ctx) =>
      StatefulBuilder(builder: (ctx, update) {
        final days = daysInMonth(year, month);
        if (day > days) day = days;
        return AlertDialog(
          title: const Text('انتخاب تاریخ و ساعت شمسی'),
          content: SizedBox(width: 350, child: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${persianDigits(day)} ${months[month-1]} ${persianDigits(year)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Wrap(spacing: 12, runSpacing: 10, children: [
                SizedBox(width: 105, child: DropdownButtonFormField<int>(
                  value: year, decoration: const InputDecoration(labelText: 'سال'),
                  items: [for (var x = 1350; x <= 1480; x++)
                    DropdownMenuItem(value: x, child: Text(persianDigits(x)))],
                  onChanged: (v) => update(() => year = v ?? year))),
                SizedBox(width: 140, child: DropdownButtonFormField<int>(
                  value: month, decoration: const InputDecoration(labelText: 'ماه'),
                  items: [for (var x = 1; x <= 12; x++)
                    DropdownMenuItem(value: x, child: Text(months[x-1]))],
                  onChanged: (v) => update(() => month = v ?? month))),
                SizedBox(width: 80, child: DropdownButtonFormField<int>(
                  value: day, decoration: const InputDecoration(labelText: 'روز'),
                  items: [for (var x = 1; x <= days; x++)
                    DropdownMenuItem(value: x, child: Text(persianDigits(x)))],
                  onChanged: (v) => update(() => day = v ?? day))),
                SizedBox(width: 120, child: DropdownButtonFormField<int>(
                  value: hour, decoration: const InputDecoration(labelText: 'ساعت'),
                  items: [for (var x = 0; x < 24; x++)
                    DropdownMenuItem(value: x, child: Text(persianDigits(x.toString().padLeft(2,'0'))))],
                  onChanged: (v) => update(() => hour = v ?? hour))),
                SizedBox(width: 120, child: DropdownButtonFormField<int>(
                  value: minute, decoration: const InputDecoration(labelText: 'دقیقه'),
                  items: [for (var x = 0; x < 60; x++)
                    DropdownMenuItem(value: x, child: Text(persianDigits(x.toString().padLeft(2,'0'))))],
                  onChanged: (v) => update(() => minute = v ?? minute))),
              ]),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
            FilledButton(onPressed: () => Navigator.pop(ctx,
              toGregorian(year, month, day, hour: hour, minute: minute)),
              child: const Text('تأیید تاریخ')),
          ],
        );
      }));
  }
}
