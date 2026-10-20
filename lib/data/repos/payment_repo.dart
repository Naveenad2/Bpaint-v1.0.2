import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/formatters.dart';
import '../db.dart';
import '../models.dart';
import 'party_repo.dart';

/// Receipts from customers and payments to suppliers.
class PaymentRepo {
  Database get _db => AppDb.instance.db;

  Future<List<PaymentVoucher>> list({
    DateTime? from,
    DateTime? to,
    String? direction,
    int? partyId,
    String query = '',
    int limit = 500,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('date >= ?');
      args.add(_dayStart(from).toIso8601String());
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(_dayEnd(to).toIso8601String());
    }
    if (direction != null) {
      where.add('direction = ?');
      args.add(direction);
    }
    if (partyId != null) {
      where.add('party_id = ?');
      args.add(partyId);
    }
    if (query.trim().isNotEmpty) {
      where.add('(party_name LIKE ? OR voucher_no LIKE ? OR ref_no LIKE ? '
          'OR doc_no LIKE ?)');
      final like = '%${query.trim()}%';
      args.addAll([like, like, like, like]);
    }
    final rows = await _db.query('payments',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'date DESC, id DESC',
        limit: limit);
    return rows.map(PaymentVoucher.fromMap).toList();
  }

  /// Signed balance delta a voucher applies to its party.
  ///
  /// A receipt from a customer and a payment to a supplier both *reduce*
  /// the outstanding figure; the opposite direction increases it.
  static double balanceDelta(
      String partyKind, String direction, double amount, double discount) {
    final magnitude = Fmt.round(amount + discount);
    final reduces = (partyKind == 'CUSTOMER' && direction == 'IN') ||
        (partyKind == 'SUPPLIER' && direction == 'OUT');
    return reduces ? -magnitude : magnitude;
  }

  static Future<String> nextVoucherNo(
      DatabaseExecutor txn, String direction) async {
    final prefix = direction == 'IN' ? 'RCP' : 'PMT';
    final n = firstInt(await txn.rawQuery(
      'SELECT COUNT(*) FROM payments WHERE direction = ?',
      [direction],
    ));
    return '$prefix${(n + 1).toString().padLeft(5, '0')}';
  }

  /// Inserts a voucher, moves the party balance and settles the referenced
  /// bill. Runs inside [txn] when the caller already owns a transaction.
  static Future<int> record(
    DatabaseExecutor txn,
    PaymentVoucher v, {
    required String partyKind,
    bool settleDoc = true,
  }) async {
    if (v.voucherNo.isEmpty) {
      v.voucherNo = await nextVoucherNo(txn, v.direction);
    }
    v.createdAt ??= DateTime.now();
    final id = await txn.insert('payments', v.toMap());
    v.id = id;

    await PartyRepo.adjustBalance(
      txn,
      v.partyId,
      balanceDelta(partyKind, v.direction, v.amount, v.discount),
    );

    if (settleDoc && v.docId != null) {
      await _settleSalesDoc(txn, v.docId!, Fmt.round(v.amount + v.discount));
    }
    return id;
  }

  static Future<void> _settleSalesDoc(
      DatabaseExecutor txn, int docId, double delta) async {
    final rows = await txn.query('sales_docs',
        columns: ['total', 'paid', 'status'],
        where: 'id = ?',
        whereArgs: [docId]);
    if (rows.isEmpty) return;
    final total = Fmt.toDouble(rows.first['total']);
    final paid = Fmt.round(Fmt.toDouble(rows.first['paid']) + delta);
    final status = (rows.first['status'] as String?) == 'CANCELLED'
        ? 'CANCELLED'
        : paid <= 0.004
            ? 'UNPAID'
            : (paid >= total - 0.5 ? 'PAID' : 'PARTIAL');
    await txn.update(
      'sales_docs',
      {'paid': paid, 'balance': Fmt.round(total - paid), 'status': status},
      where: 'id = ?',
      whereArgs: [docId],
    );
  }

  Future<int> save(PaymentVoucher v, {required String partyKind}) async {
    return _db.transaction((txn) => record(txn, v, partyKind: partyKind));
  }

  /// Reverses and removes a voucher.
  Future<void> delete(int id) async {
    await _db.transaction((txn) async {
      final rows =
          await txn.query('payments', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final v = PaymentVoucher.fromMap(rows.first);
      var kind = 'CUSTOMER';
      if (v.partyId != null) {
        final pr = await txn.query('parties',
            columns: ['kind'], where: 'id = ?', whereArgs: [v.partyId]);
        if (pr.isNotEmpty) kind = (pr.first['kind'] ?? 'CUSTOMER') as String;
      }
      await PartyRepo.adjustBalance(
        txn,
        v.partyId,
        -balanceDelta(kind, v.direction, v.amount, v.discount),
      );
      if (v.docId != null) {
        await _settleSalesDoc(txn, v.docId!, -Fmt.round(v.amount + v.discount));
      }
      await txn.delete('payments', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Removes the auto-generated receipt written when a bill was paid at the
  /// counter, without touching manually entered vouchers.
  static Future<void> removeAutoForDoc(
          DatabaseExecutor txn, int docId, String partyKind) =>
      _removeForDoc(txn, docId, partyKind, autoOnly: true);

  /// Reverses and removes *every* voucher raised against a document — used
  /// when a bill is cancelled or deleted, so a part-paid bill does not leave
  /// an orphan receipt behind.
  static Future<void> removeAllForDoc(
          DatabaseExecutor txn, int docId, String partyKind) =>
      _removeForDoc(txn, docId, partyKind, autoOnly: false);

  static Future<void> _removeForDoc(
    DatabaseExecutor txn,
    int docId,
    String partyKind, {
    required bool autoOnly,
  }) async {
    final rows = await txn.query(
      'payments',
      where: autoOnly ? "doc_id = ? AND ref_no = 'AUTO-BILL'" : 'doc_id = ?',
      whereArgs: [docId],
    );
    for (final r in rows) {
      final v = PaymentVoucher.fromMap(r);
      await PartyRepo.adjustBalance(
        txn,
        v.partyId,
        -balanceDelta(partyKind, v.direction, v.amount, v.discount),
      );
      await txn.delete('payments', where: 'id = ?', whereArgs: [v.id]);
    }
  }

  /// Cash/UPI/card collection totals for the day-close screen.
  Future<Map<String, double>> collectionByMode(DateTime day) async {
    final rows = await _db.rawQuery('''
      SELECT mode, direction, COALESCE(SUM(amount), 0) AS total
      FROM payments WHERE date >= ? AND date <= ?
      GROUP BY mode, direction
    ''', [_dayStart(day).toIso8601String(), _dayEnd(day).toIso8601String()]);
    final out = <String, double>{};
    for (final r in rows) {
      final key = '${r['mode']}';
      final amt = Fmt.toDouble(r['total']);
      final signed = r['direction'] == 'IN' ? amt : -amt;
      out[key] = Fmt.round((out[key] ?? 0) + signed);
    }
    return out;
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}
