import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "$80" for whole amounts, "$79.50" otherwise.
String money(num amount) =>
    NumberFormat.simpleCurrency(name: 'USD', decimalDigits: amount % 1 == 0 ? 0 : 2).format(amount);

/// A spa-local `YYYY-MM-DD` as a calendar date (no time zone maths needed).
DateTime parseDay(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A spa-local `HH:mm` in the phone's 12/24-hour style.
String timeLabel(BuildContext context, String hhmm) {
  final p = hhmm.split(':').map(int.parse).toList();
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay(hour: p[0], minute: p[1]),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

String fullDate(BuildContext context, String ymd) => MaterialLocalizations.of(context).formatFullDate(parseDay(ymd));

/// Zero when the guest asked the system to reduce motion.
Duration motion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: milliseconds);
