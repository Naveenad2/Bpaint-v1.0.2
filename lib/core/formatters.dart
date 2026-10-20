import 'dart:math' as math;

import 'package:intl/intl.dart';

/// Money / date / number helpers tuned for Indian retail invoices.
class Fmt {
  static final NumberFormat _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  static final NumberFormat _inrPlain = NumberFormat('##,##,##0.00', 'en_IN');
  static final NumberFormat _compact = NumberFormat('##,##,##0', 'en_IN');
  static final NumberFormat _qty = NumberFormat('0.###', 'en_IN');

  static final DateFormat _date = DateFormat('dd-MM-yyyy');
  static final DateFormat _dateTime = DateFormat('dd-MM-yyyy hh:mm a');
  static final DateFormat _time = DateFormat('hh:mm a');
  static final DateFormat _monthYear = DateFormat('MMM yyyy');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd');
  static final DateFormat _isoStamp = DateFormat('yyyyMMdd_HHmmss');

  static String money(num? v) => _inr.format(v ?? 0);
  static String amount(num? v) => _inrPlain.format(v ?? 0);
  static String compact(num? v) => _compact.format(v ?? 0);
  static String qty(num? v) => _qty.format(v ?? 0);
  static String pct(num? v) => '${_qty.format(v ?? 0)}%';

  static String date(DateTime? d) => d == null ? '' : _date.format(d);
  static String dateTime(DateTime? d) => d == null ? '' : _dateTime.format(d);
  static String time(DateTime? d) => d == null ? '' : _time.format(d);
  static String monthYear(DateTime? d) => d == null ? '' : _monthYear.format(d);
  static String iso(DateTime? d) => d == null ? '' : _iso.format(d);
  static String stamp(DateTime? d) => _isoStamp.format(d ?? DateTime.now());

  static DateTime? parseIso(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  /// Rounds to [places] decimals using half-up, avoiding binary FP drift.
  static double round(num value, [int places = 2]) {
    if (value.isNaN || value.isInfinite) return 0;
    final f = math.pow(10, places).toDouble();
    return (value * f).roundToDouble() / f;
  }

  /// Splits a rupee value into (roundedTotal, roundOffDelta).
  static (double, double) roundOff(double total) {
    final rounded = total.roundToDouble();
    return (rounded, round(rounded - total));
  }

  static double toDouble(Object? v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '').trim();
    if (s.isEmpty) return fallback;
    return double.tryParse(s) ?? fallback;
  }

  static int toInt(Object? v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim()) ?? fallback;
  }

  static bool toBool(Object? v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase().trim();
    return s == '1' || s == 'true' || s == 'yes' || s == 'y';
  }
}

/// Converts a rupee amount to Indian-format words for the invoice footer.
/// e.g. 125430.50 -> "Rupees One Lakh Twenty Five Thousand Four Hundred
/// Thirty and Paise Fifty Only"
class NumberToWords {
  static const List<String> _ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  static const List<String> _tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];

  static String _twoDigit(int n) {
    if (n < 20) return _ones[n];
    final t = _tens[n ~/ 10];
    final o = _ones[n % 10];
    return o.isEmpty ? t : '$t $o';
  }

  static String _threeDigit(int n) {
    final h = n ~/ 100;
    final r = n % 100;
    final parts = <String>[];
    if (h > 0) parts.add('${_ones[h]} Hundred');
    if (r > 0) parts.add(_twoDigit(r));
    return parts.join(' ');
  }

  static String _indian(int n) {
    if (n == 0) return 'Zero';
    final parts = <String>[];
    final crore = n ~/ 10000000;
    n %= 10000000;
    final lakh = n ~/ 100000;
    n %= 100000;
    final thousand = n ~/ 1000;
    n %= 1000;
    final rest = n;

    if (crore > 0) parts.add('${_indian(crore)} Crore');
    if (lakh > 0) parts.add('${_twoDigit(lakh)} Lakh');
    if (thousand > 0) parts.add('${_twoDigit(thousand)} Thousand');
    if (rest > 0) parts.add(_threeDigit(rest));
    return parts.join(' ');
  }

  static String rupees(double value) {
    final negative = value < 0;
    final abs = value.abs();
    final whole = abs.floor();
    final paise = ((abs - whole) * 100).round();

    final buf = StringBuffer();
    if (negative) buf.write('Minus ');
    buf.write('Rupees ');
    buf.write(_indian(whole));
    if (paise > 0) {
      buf.write(' and Paise ');
      buf.write(_twoDigit(paise));
    }
    buf.write(' Only');
    return buf.toString();
  }
}
