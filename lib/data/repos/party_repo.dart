import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/formatters.dart';
import '../db.dart';
import '../models.dart';

/// Customers and suppliers.
class PartyRepo {
  Database get _db => AppDb.instance.db;

  Future<List<Party>> all({
    String kind = 'CUSTOMER',
    String query = '',
    bool onlyActive = true,
    bool onlyOutstanding = false,
    int limit = 500,
  }) async {
    final where = <String>['kind = ?'];
    final args = <Object?>[kind];
    if (onlyActive) where.add('active = 1');
    if (onlyOutstanding) where.add('ABS(balance) > 0.5');
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('(name LIKE ? OR phone LIKE ? OR code LIKE ? OR gstin LIKE ?)');
      final like = '%$q%';
      args.addAll([like, like, like, like]);
    }
    final rows = await _db.query('parties',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'name COLLATE NOCASE',
        limit: limit);
    return rows.map(Party.fromMap).toList();
  }

  Future<Party?> byId(int? id) async {
    if (id == null) return null;
    final rows = await _db.query('parties', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Party.fromMap(rows.first);
  }

  Future<Party?> byPhone(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return null;
    final rows = await _db.query('parties',
        where: 'phone = ? AND kind = ?', whereArgs: [p, 'CUSTOMER'], limit: 1);
    return rows.isEmpty ? null : Party.fromMap(rows.first);
  }

  Future<int> save(Party p) async {
    p.createdAt ??= DateTime.now();
    if (p.id == null) {
      if (p.code.trim().isEmpty) {
        p.code = await _nextCode(p.kind);
      }
      p.balance = p.openingBalance;
      return _db.insert('parties', p.toMap());
    }
    await _db.update('parties', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
    return p.id!;
  }

  Future<String> _nextCode(String kind) async {
    final prefix = kind == 'SUPPLIER' ? 'SUP' : 'CUS';
    final n = firstInt(await _db.rawQuery(
      'SELECT COUNT(*) FROM parties WHERE kind = ?',
      [kind],
    ));
    return '$prefix${(n + 1).toString().padLeft(4, '0')}';
  }

  /// Deletes only when the party has no transactions; otherwise deactivates.
  Future<String> deleteOrDeactivate(int id) async {
    if (id == 1) return 'The walk-in customer cannot be removed.';
    final docs = firstInt(await _db
        .rawQuery('SELECT COUNT(*) FROM sales_docs WHERE party_id = ?', [id]));
    final purch = firstInt(await _db.rawQuery(
        'SELECT COUNT(*) FROM purchase_docs WHERE party_id = ?', [id]));
    if (docs + purch > 0) {
      await _db.update('parties', {'active': 0},
          where: 'id = ?', whereArgs: [id]);
      return 'Party has transactions — marked inactive instead of deleted.';
    }
    await _db.delete('parties', where: 'id = ?', whereArgs: [id]);
    return 'Deleted.';
  }

  /// Applies a signed delta to the running balance (+ = receivable).
  static Future<void> adjustBalance(
      DatabaseExecutor txn, int? partyId, double delta) async {
    if (partyId == null || delta == 0) return;
    await txn.rawUpdate(
      'UPDATE parties SET balance = ROUND(COALESCE(balance,0) + ?, 2) WHERE id = ?',
      [delta, partyId],
    );
  }

  Future<double> outstandingTotal(String kind) async {
    final rows = await _db.rawQuery(
        'SELECT COALESCE(SUM(balance),0) AS t FROM parties WHERE kind = ?',
        [kind]);
    return Fmt.toDouble(rows.first['t']);
  }

  /// Full running-balance ledger for one party.
  Future<List<LedgerRow>> ledger(
    int partyId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final party = await byId(partyId);
    if (party == null) return [];
    final isCustomer = party.kind == 'CUSTOMER';

    final rows = <LedgerRow>[];
    // A positive opening balance means "owed in the party's natural
    // direction": receivable for a customer, payable for a supplier.
    rows.add(LedgerRow(
      date: party.createdAt ?? DateTime(2000),
      particulars: 'Opening Balance',
      voucherType: 'OPENING',
      voucherNo: '',
      debit: isCustomer
          ? (party.openingBalance > 0 ? party.openingBalance : 0)
          : (party.openingBalance < 0 ? -party.openingBalance : 0),
      credit: isCustomer
          ? (party.openingBalance < 0 ? -party.openingBalance : 0)
          : (party.openingBalance > 0 ? party.openingBalance : 0),
    ));

    if (isCustomer) {
      final docs = await _db.query('sales_docs',
          where: "party_id = ? AND status <> 'CANCELLED' "
              "AND doc_type IN ('INVOICE','CREDIT_NOTE')",
          whereArgs: [partyId],
          orderBy: 'doc_date');
      for (final r in docs) {
        final d = SalesDoc.fromMap(r);
        rows.add(LedgerRow(
          date: d.docDate,
          particulars: d.isReturn ? 'Sales Return' : 'Sales Invoice',
          voucherType: d.docType,
          voucherNo: d.docNo,
          debit: d.isReturn ? 0 : d.total,
          credit: d.isReturn ? d.total : 0,
        ));
      }
    } else {
      final docs = await _db.query('purchase_docs',
          where: 'party_id = ?', whereArgs: [partyId], orderBy: 'doc_date');
      for (final r in docs) {
        final d = PurchaseDoc.fromMap(r);
        final isRet = d.docType == 'PURCHASE_RETURN';
        rows.add(LedgerRow(
          date: d.docDate,
          particulars: isRet ? 'Purchase Return' : 'Purchase Bill',
          voucherType: d.docType,
          voucherNo: d.docNo,
          debit: isRet ? d.total : 0,
          credit: isRet ? 0 : d.total,
        ));
      }
    }

    final pays = await _db.query('payments',
        where: 'party_id = ?', whereArgs: [partyId], orderBy: 'date');
    for (final r in pays) {
      final v = PaymentVoucher.fromMap(r);
      final isReceipt = v.direction == 'IN';
      rows.add(LedgerRow(
        date: v.date,
        particulars: '${isReceipt ? 'Receipt' : 'Payment'} (${v.mode})'
            '${v.docNo.isNotEmpty ? ' against ${v.docNo}' : ''}',
        voucherType: isReceipt ? 'RECEIPT' : 'PAYMENT',
        voucherNo: v.voucherNo,
        debit: isReceipt ? 0 : v.amount,
        credit: isReceipt ? v.amount : 0,
      ));
      if (v.discount > 0) {
        rows.add(LedgerRow(
          date: v.date,
          particulars: 'Discount allowed',
          voucherType: 'DISCOUNT',
          voucherNo: v.voucherNo,
          credit: v.discount,
        ));
      }
    }

    rows.sort((a, b) => a.date.compareTo(b.date));
    // Customers are debit-natured (they owe us); suppliers credit-natured
    // (we owe them). Both are reported as a positive outstanding figure.
    var running = 0.0;
    for (final r in rows) {
      running = Fmt.round(
        isCustomer
            ? running + r.debit - r.credit
            : running + r.credit - r.debit,
      );
      r.running = running;
    }
    if (from == null && to == null) return rows;
    return rows
        .where((r) =>
            (from == null || !r.date.isBefore(from)) &&
            (to == null || !r.date.isAfter(to)))
        .toList();
  }

  /// Recomputes every party balance from source documents (repair tool).
  Future<int> recalculateBalances() async {
    final parties = await _db.query('parties');
    var fixed = 0;
    for (final row in parties) {
      final p = Party.fromMap(row);
      final ledgerRows = await ledger(p.id!);
      final bal = ledgerRows.isEmpty ? 0.0 : ledgerRows.last.running;
      if ((bal - p.balance).abs() > 0.05) {
        await _db.update('parties', {'balance': bal},
            where: 'id = ?', whereArgs: [p.id]);
        fixed++;
      }
    }
    return fixed;
  }
}
