import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../db.dart';
import '../models.dart';

/// Key/value application settings plus the company profile.
class SettingsRepo {
  Database get _db => AppDb.instance.db;

  final Map<String, String> _cache = {};

  Future<void> load() async {
    final rows = await _db.query('settings');
    _cache
      ..clear()
      ..addEntries(rows.map(
          (r) => MapEntry(r['key'] as String, (r['value'] ?? '') as String)));
  }

  String get(String key, [String fallback = '']) => _cache[key] ?? fallback;

  int getInt(String key, [int fallback = 0]) =>
      Fmt.toInt(_cache[key], fallback);

  double getDouble(String key, [double fallback = 0]) =>
      Fmt.toDouble(_cache[key], fallback);

  bool getBool(String key, [bool fallback = false]) =>
      _cache.containsKey(key) ? Fmt.toBool(_cache[key], fallback) : fallback;

  Future<void> set(String key, Object? value) async {
    final v = value == null ? '' : value.toString();
    _cache[key] = v;
    await _db.insert(
      'settings',
      {'key': key, 'value': v},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setAll(Map<String, Object?> values) async {
    final batch = _db.batch();
    for (final e in values.entries) {
      final v = e.value == null ? '' : e.value.toString();
      _cache[e.key] = v;
      batch.insert('settings', {'key': e.key, 'value': v},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------------
  // Company profile
  // ------------------------------------------------------------------
  Future<Company> company() async {
    final rows = await _db.query('company', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return Company();
    return Company.fromMap(rows.first);
  }

  Future<void> saveCompany(Company c) async {
    c.id = 1;
    await _db.insert('company', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ------------------------------------------------------------------
  // Document numbering
  // ------------------------------------------------------------------
  static const Map<String, (String, String)> _counterKeys = {
    DocType.invoice: (SKeys.invoicePrefix, SKeys.invoiceNext),
    DocType.estimate: (SKeys.estimatePrefix, SKeys.estimateNext),
    DocType.creditNote: (SKeys.creditPrefix, SKeys.creditNext),
    DocType.challan: (SKeys.estimatePrefix, SKeys.estimateNext),
    'PURCHASE': (SKeys.purchasePrefix, SKeys.purchaseNext),
  };

  /// Peeks at the next number without consuming it (for the billing header).
  Future<String> peekDocNo(String docType) async {
    final keys = _counterKeys[docType] ?? _counterKeys[DocType.invoice]!;
    final rows = await _db.query('settings',
        where: 'key IN (?, ?)', whereArgs: [keys.$1, keys.$2]);
    var prefix = '';
    var next = 1;
    for (final r in rows) {
      if (r['key'] == keys.$1) prefix = (r['value'] ?? '') as String;
      if (r['key'] == keys.$2) next = Fmt.toInt(r['value'], 1);
    }
    return format(prefix, next);
  }

  /// Consumes and returns the next number. Must run inside the caller's
  /// transaction so two tills can never mint the same bill number.
  static Future<String> nextDocNo(DatabaseExecutor txn, String docType) async {
    final keys = _counterKeys[docType] ?? _counterKeys[DocType.invoice]!;
    final rows = await txn.query('settings',
        where: 'key IN (?, ?)', whereArgs: [keys.$1, keys.$2]);
    var prefix = '';
    var next = 1;
    for (final r in rows) {
      if (r['key'] == keys.$1) prefix = (r['value'] ?? '') as String;
      if (r['key'] == keys.$2) next = Fmt.toInt(r['value'], 1);
    }
    final no = format(prefix, next);
    await txn.insert('settings', {'key': keys.$2, 'value': '${next + 1}'},
        conflictAlgorithm: ConflictAlgorithm.replace);
    return no;
  }

  /// `INV-` + 4-digit sequence. `{FY}` in the prefix expands to `25-26`.
  static String format(String prefix, int number) {
    final fy = financialYearLabel(DateTime.now());
    final resolved = prefix
        .replaceAll('{FY}', fy)
        .replaceAll('{YYYY}', DateTime.now().year.toString())
        .replaceAll('{YY}', DateTime.now().year.toString().substring(2));
    return '$resolved${number.toString().padLeft(4, '0')}';
  }

  /// Indian financial year runs 1 April - 31 March.
  static String financialYearLabel(DateTime d) {
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    final a = startYear.toString().substring(2);
    final b = (startYear + 1).toString().substring(2);
    return '$a-$b';
  }

  static DateTime financialYearStart(DateTime d) {
    final y = d.month >= 4 ? d.year : d.year - 1;
    return DateTime(y, 4, 1);
  }

  static DateTime financialYearEnd(DateTime d) {
    final y = d.month >= 4 ? d.year : d.year - 1;
    return DateTime(y + 1, 3, 31, 23, 59, 59);
  }
}
