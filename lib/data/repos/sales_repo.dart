import 'dart:convert';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/tax.dart';
import '../db.dart';
import '../models.dart';
import 'party_repo.dart';
import 'payment_repo.dart';
import 'product_repo.dart';
import 'settings_repo.dart';

class InsufficientStock implements Exception {
  final String message;
  InsufficientStock(this.message);
  @override
  String toString() => message;
}

/// Sales invoices, estimates, credit notes and delivery challans.
///
/// Every mutation is wrapped in a single SQLite transaction that writes the
/// document, its lines, the stock ledger, the party balance and the counter
/// receipt together — so an interrupted save can never leave a half bill.
class SalesRepo {
  Database get _db => AppDb.instance.db;

  // ------------------------------------------------------------------
  // Reads
  // ------------------------------------------------------------------
  Future<List<SalesDoc>> list({
    String docType = DocType.invoice,
    DateTime? from,
    DateTime? to,
    int? partyId,
    String status = '',
    String query = '',
    int limit = 500,
    int offset = 0,
  }) async {
    final where = <String>['doc_type = ?'];
    final args = <Object?>[docType];
    if (from != null) {
      where.add('doc_date >= ?');
      args.add(_dayStart(from).toIso8601String());
    }
    if (to != null) {
      where.add('doc_date <= ?');
      args.add(_dayEnd(to).toIso8601String());
    }
    if (partyId != null) {
      where.add('party_id = ?');
      args.add(partyId);
    }
    if (status.isNotEmpty) {
      where.add('status = ?');
      args.add(status);
    }
    if (query.trim().isNotEmpty) {
      where.add('(doc_no LIKE ? OR party_name LIKE ? OR party_phone LIKE ? '
          'OR party_gstin LIKE ?)');
      final like = '%${query.trim()}%';
      args.addAll([like, like, like, like]);
    }
    final rows = await _db.query('sales_docs',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'doc_date DESC, id DESC',
        limit: limit,
        offset: offset);
    return rows.map(SalesDoc.fromMap).toList();
  }

  Future<SalesDoc?> byId(int id, {bool withItems = true}) async {
    final rows =
        await _db.query('sales_docs', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final doc = SalesDoc.fromMap(rows.first);
    if (withItems) doc.items = await itemsOf(id);
    return doc;
  }

  Future<SalesDoc?> byNo(String docNo, String docType) async {
    final rows = await _db.query('sales_docs',
        where: 'doc_no = ? AND doc_type = ?',
        whereArgs: [docNo, docType],
        limit: 1);
    if (rows.isEmpty) return null;
    final doc = SalesDoc.fromMap(rows.first);
    doc.items = await itemsOf(doc.id!);
    return doc;
  }

  Future<List<SalesItem>> itemsOf(int docId) async {
    final rows = await _db.query('sales_items',
        where: 'doc_id = ?', whereArgs: [docId], orderBy: 'id');
    return rows.map(SalesItem.fromMap).toList();
  }

  Future<String> peekNextNo(String docType) =>
      SettingsRepo().peekDocNo(docType);

  /// Most recent bills for the given customer — powers "repeat last bill".
  Future<List<SalesDoc>> recentForParty(int partyId, {int limit = 10}) =>
      list(partyId: partyId, limit: limit);

  // ------------------------------------------------------------------
  // Write
  // ------------------------------------------------------------------
  /// Creates or updates a document and posts all of its side effects.
  Future<SalesDoc> save(
    SalesDoc doc, {
    AppUser? user,
    bool allowNegativeStock = false,
    bool roundOff = true,
  }) async {
    if (doc.items.isEmpty) {
      throw ArgumentError('Add at least one item before saving.');
    }
    TaxEngine.computeDoc(doc, applyRoundOff: roundOff);
    doc.userId ??= user?.id;
    if (doc.userName.isEmpty) doc.userName = user?.name ?? '';
    doc.createdAt ??= DateTime.now();

    final isNew = doc.id == null;

    return _db.transaction<SalesDoc>((txn) async {
      const partyKind = 'CUSTOMER';

      // --- Reverse the previous version when editing -------------------
      if (doc.id != null) {
        final oldRows =
            await txn.query('sales_docs', where: 'id = ?', whereArgs: [doc.id]);
        if (oldRows.isEmpty) {
          throw StateError('Document no longer exists.');
        }
        final old = SalesDoc.fromMap(oldRows.first);
        if (old.status == DocStatus.cancelled) {
          throw StateError('A cancelled document cannot be edited.');
        }
        old.items = (await txn
                .query('sales_items', where: 'doc_id = ?', whereArgs: [doc.id]))
            .map(SalesItem.fromMap)
            .toList();
        await PaymentRepo.removeAutoForDoc(txn, doc.id!, partyKind);
        await _applyEffects(txn, old, reverse: true);
        await txn
            .delete('sales_items', where: 'doc_id = ?', whereArgs: [doc.id]);
        doc.docNo = old.docNo; // numbers are never re-issued
      } else if (doc.docNo.trim().isEmpty) {
        doc.docNo = await SettingsRepo.nextDocNo(txn, doc.docType);
      }

      // --- Stock guard --------------------------------------------------
      if (doc.affectsAccounts && !doc.isReturn && !allowNegativeStock) {
        for (final it in doc.items) {
          if (it.productId == null) continue;
          final rows = await txn.query('products',
              columns: ['stock', 'is_service', 'name'],
              where: 'id = ?',
              whereArgs: [it.productId]);
          if (rows.isEmpty) continue;
          if (Fmt.toBool(rows.first['is_service'])) continue;
          final available = Fmt.toDouble(rows.first['stock']);
          final needed = it.qty + it.freeQty;
          if (needed > available + 0.0001) {
            throw InsufficientStock(
              'Not enough stock for "${it.name}". '
              'Available ${Fmt.qty(available)} ${it.unit}, '
              'required ${Fmt.qty(needed)} ${it.unit}.',
            );
          }
        }
      }

      // --- Header --------------------------------------------------------
      if (doc.id == null) {
        doc.id = await txn.insert('sales_docs', doc.toMap());
      } else {
        await txn.update('sales_docs', doc.toMap(),
            where: 'id = ?', whereArgs: [doc.id]);
      }

      // --- Lines ----------------------------------------------------------
      for (final it in doc.items) {
        it.docId = doc.id;
        it.id = null;
        it.id = await txn.insert('sales_items', it.toMap());
      }

      // --- Stock + ledger --------------------------------------------------
      await _applyEffects(txn, doc, reverse: false);

      // --- Counter receipt -------------------------------------------------
      if (doc.affectsAccounts && doc.paid > 0.004) {
        await PaymentRepo.record(
          txn,
          PaymentVoucher(
            date: doc.docDate,
            direction: doc.isReturn ? 'OUT' : 'IN',
            partyId: doc.partyId,
            partyName: doc.partyName,
            docId: doc.id,
            docNo: doc.docNo,
            amount: doc.paid,
            mode: doc.paymentMode,
            refNo: 'AUTO-BILL',
            notes: 'Collected with ${doc.docNo}',
            userId: doc.userId,
          ),
          partyKind: partyKind,
          settleDoc: false, // `paid` is already stored on the document
        );
      }

      await txn.insert('audit_log', {
        'at': DateTime.now().toIso8601String(),
        'user_id': user?.id,
        'user_name': user?.name ?? '',
        'action': isNew ? 'CREATE' : 'UPDATE',
        'entity': doc.docType,
        'entity_id': doc.id,
        'detail': '${doc.docNo} · ${Fmt.money(doc.total)}',
      });

      return doc;
    });
  }

  /// Applies (or reverses) stock movement and the customer balance.
  Future<void> _applyEffects(
    DatabaseExecutor txn,
    SalesDoc doc, {
    required bool reverse,
  }) async {
    if (!doc.affectsAccounts || doc.status == DocStatus.cancelled) return;
    final sign = reverse ? -1.0 : 1.0;

    for (final it in doc.items) {
      if (it.productId == null) continue;
      final qty = it.qty + it.freeQty;
      // A sale takes stock out; a credit note brings it back in.
      final delta = sign * (doc.isReturn ? qty : -qty);
      await ProductRepo.moveStock(
        txn,
        productId: it.productId!,
        productName: it.name,
        delta: delta,
        refType: doc.isReturn ? StockRef.salesReturn : StockRef.sale,
        refId: doc.id,
        refNo: doc.docNo,
        rate: it.rate,
        date: doc.docDate,
        notes: reverse ? 'Reversal of ${doc.docNo}' : '',
      );
    }

    await PartyRepo.adjustBalance(
      txn,
      doc.partyId,
      sign * (doc.isReturn ? -doc.total : doc.total),
    );
  }

  /// Cancels a document: reverses stock and ledger, keeps the number.
  Future<void> cancel(int docId, {AppUser? user, String reason = ''}) async {
    await _db.transaction((txn) async {
      final rows =
          await txn.query('sales_docs', where: 'id = ?', whereArgs: [docId]);
      if (rows.isEmpty) return;
      final doc = SalesDoc.fromMap(rows.first);
      if (doc.status == DocStatus.cancelled) return;
      doc.items = (await txn
              .query('sales_items', where: 'doc_id = ?', whereArgs: [docId]))
          .map(SalesItem.fromMap)
          .toList();

      await PaymentRepo.removeAllForDoc(txn, docId, 'CUSTOMER');
      await _applyEffects(txn, doc, reverse: true);

      await txn.update(
        'sales_docs',
        {
          'status': DocStatus.cancelled,
          'paid': 0,
          'balance': 0,
          'notes': reason.isEmpty
              ? doc.notes
              : '${doc.notes}\nCancelled: $reason'.trim(),
        },
        where: 'id = ?',
        whereArgs: [docId],
      );
      await txn.insert('audit_log', {
        'at': DateTime.now().toIso8601String(),
        'user_id': user?.id,
        'user_name': user?.name ?? '',
        'action': 'CANCEL',
        'entity': doc.docType,
        'entity_id': docId,
        'detail': '${doc.docNo} · $reason',
      });
    });
  }

  /// Hard delete — admin only, and only for non-posting documents or when
  /// the operator explicitly accepts the audit gap.
  Future<void> delete(int docId, {AppUser? user}) async {
    await _db.transaction((txn) async {
      final rows =
          await txn.query('sales_docs', where: 'id = ?', whereArgs: [docId]);
      if (rows.isEmpty) return;
      final doc = SalesDoc.fromMap(rows.first);
      doc.items = (await txn
              .query('sales_items', where: 'doc_id = ?', whereArgs: [docId]))
          .map(SalesItem.fromMap)
          .toList();
      if (doc.status != DocStatus.cancelled) {
        await PaymentRepo.removeAllForDoc(txn, docId, 'CUSTOMER');
        await _applyEffects(txn, doc, reverse: true);
      }
      await txn.delete('payments', where: 'doc_id = ?', whereArgs: [docId]);
      await txn.delete('sales_docs', where: 'id = ?', whereArgs: [docId]);
      await txn.insert('audit_log', {
        'at': DateTime.now().toIso8601String(),
        'user_id': user?.id,
        'user_name': user?.name ?? '',
        'action': 'DELETE',
        'entity': doc.docType,
        'entity_id': docId,
        'detail': doc.docNo,
      });
    });
  }

  /// Builds a credit note pre-filled from an existing invoice.
  Future<SalesDoc> creditNoteFrom(SalesDoc invoice) async {
    final cn = SalesDoc(
      docType: DocType.creditNote,
      docDate: DateTime.now(),
      partyId: invoice.partyId,
      partyName: invoice.partyName,
      partyPhone: invoice.partyPhone,
      partyGstin: invoice.partyGstin,
      partyAddress: invoice.partyAddress,
      placeOfSupply: invoice.placeOfSupply,
      isIgst: invoice.isIgst,
      priceIncludesTax: invoice.priceIncludesTax,
      priceTier: invoice.priceTier,
      refDocId: invoice.id,
      refDocNo: invoice.docNo,
      paymentMode: invoice.paymentMode,
    );
    for (final it in invoice.items) {
      cn.items.add(SalesItem.fromMap(it.toMap()
        ..remove('id')
        ..remove('doc_id')));
    }
    return cn;
  }

  /// Converts an estimate into a live invoice.
  Future<SalesDoc> invoiceFromEstimate(SalesDoc est) async {
    final inv = SalesDoc.fromMap(est.toMap()
      ..remove('id')
      ..['doc_type'] = DocType.invoice
      ..['doc_no'] = ''
      ..['doc_date'] = DateTime.now().toIso8601String());
    inv.id = null;
    inv.docNo = '';
    inv.refDocNo = est.docNo;
    inv.refDocId = est.id;
    inv.items = est.items
        .map((e) => SalesItem.fromMap(e.toMap()
          ..remove('id')
          ..remove('doc_id')))
        .toList();
    return inv;
  }

  // ------------------------------------------------------------------
  // Held (parked) bills — F4 in speed billing
  // ------------------------------------------------------------------
  Future<int> hold(SalesDoc doc, String label) async {
    final payload = jsonEncode({
      'doc': doc.toMap()..remove('id'),
      'items': doc.items.map((e) => e.toMap()..remove('id')).toList(),
    });
    return _db.insert('held_bills', {
      'label': label,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<({int id, String label, DateTime at, double total})>>
      heldBills() async {
    final rows = await _db.query('held_bills', orderBy: 'id DESC', limit: 50);
    return rows.map((r) {
      final payload =
          jsonDecode((r['payload'] ?? '{}') as String) as Map<String, dynamic>;
      final doc = (payload['doc'] ?? {}) as Map<String, dynamic>;
      return (
        id: r['id'] as int,
        label: (r['label'] ?? '') as String,
        at: Fmt.parseIso(r['created_at'] as String?) ?? DateTime.now(),
        total: Fmt.toDouble(doc['total']),
      );
    }).toList();
  }

  Future<SalesDoc?> recallHeld(int id) async {
    final rows =
        await _db.query('held_bills', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final payload = jsonDecode((rows.first['payload'] ?? '{}') as String)
        as Map<String, dynamic>;
    final doc =
        SalesDoc.fromMap(Map<String, Object?>.from(payload['doc'] as Map));
    doc.id = null;
    doc.items = ((payload['items'] ?? []) as List)
        .map((e) => SalesItem.fromMap(Map<String, Object?>.from(e as Map)))
        .toList();
    await _db.delete('held_bills', where: 'id = ?', whereArgs: [id]);
    return doc;
  }

  Future<void> dropHeld(int id) =>
      _db.delete('held_bills', where: 'id = ?', whereArgs: [id]);

  // ------------------------------------------------------------------
  // Aggregates
  // ------------------------------------------------------------------
  Future<Map<String, double>> summary({
    required DateTime from,
    required DateTime to,
    String docType = DocType.invoice,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS bills,
             COALESCE(SUM(taxable_amount), 0) AS taxable,
             COALESCE(SUM(cgst + sgst + igst + cess), 0) AS tax,
             COALESCE(SUM(total), 0) AS total,
             COALESCE(SUM(paid), 0) AS paid,
             COALESCE(SUM(balance), 0) AS due,
             COALESCE(SUM(item_discount + doc_discount_amt), 0) AS discount
      FROM sales_docs
      WHERE doc_type = ? AND status <> 'CANCELLED'
        AND doc_date >= ? AND doc_date <= ?
    ''', [
      docType,
      _dayStart(from).toIso8601String(),
      _dayEnd(to).toIso8601String(),
    ]);
    final r = rows.first;
    return {
      'bills': Fmt.toDouble(r['bills']),
      'taxable': Fmt.toDouble(r['taxable']),
      'tax': Fmt.toDouble(r['tax']),
      'total': Fmt.toDouble(r['total']),
      'paid': Fmt.toDouble(r['paid']),
      'due': Fmt.toDouble(r['due']),
      'discount': Fmt.toDouble(r['discount']),
    };
  }

  /// Gross profit for a period, computed from the cost snapshot on each line.
  Future<Map<String, double>> profit({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(SUM(i.taxable), 0) AS revenue,
             COALESCE(SUM(i.cost_price * i.qty), 0) AS cost
      FROM sales_items i
      JOIN sales_docs d ON d.id = i.doc_id
      WHERE d.status <> 'CANCELLED' AND d.doc_type = 'INVOICE'
        AND d.doc_date >= ? AND d.doc_date <= ?
    ''', [_dayStart(from).toIso8601String(), _dayEnd(to).toIso8601String()]);
    final revenue = Fmt.toDouble(rows.first['revenue']);
    final cost = Fmt.toDouble(rows.first['cost']);

    final ret = await _db.rawQuery('''
      SELECT COALESCE(SUM(i.taxable), 0) AS revenue,
             COALESCE(SUM(i.cost_price * i.qty), 0) AS cost
      FROM sales_items i
      JOIN sales_docs d ON d.id = i.doc_id
      WHERE d.status <> 'CANCELLED' AND d.doc_type = 'CREDIT_NOTE'
        AND d.doc_date >= ? AND d.doc_date <= ?
    ''', [_dayStart(from).toIso8601String(), _dayEnd(to).toIso8601String()]);

    final netRevenue = Fmt.round(revenue - Fmt.toDouble(ret.first['revenue']));
    final netCost = Fmt.round(cost - Fmt.toDouble(ret.first['cost']));
    return {
      'revenue': netRevenue,
      'cost': netCost,
      'profit': Fmt.round(netRevenue - netCost),
      'margin': netRevenue == 0
          ? 0
          : Fmt.round((netRevenue - netCost) / netRevenue * 100, 1),
    };
  }

  /// Day-by-day totals for the dashboard sparkline.
  Future<List<({DateTime day, double total, int bills})>> daily({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT substr(doc_date, 1, 10) AS d,
             COALESCE(SUM(total), 0) AS t,
             COUNT(*) AS n
      FROM sales_docs
      WHERE doc_type = 'INVOICE' AND status <> 'CANCELLED'
        AND doc_date >= ? AND doc_date <= ?
      GROUP BY d ORDER BY d
    ''', [_dayStart(from).toIso8601String(), _dayEnd(to).toIso8601String()]);
    return rows
        .map((r) => (
              day: DateTime.parse(r['d'] as String),
              total: Fmt.toDouble(r['t']),
              bills: Fmt.toInt(r['n']),
            ))
        .toList();
  }

  Future<List<Map<String, Object?>>> topProducts({
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) =>
      _db.rawQuery('''
        SELECT i.name AS name,
               SUM(i.qty) AS qty,
               SUM(i.taxable) AS value,
               SUM(i.taxable - i.cost_price * i.qty) AS profit
        FROM sales_items i
        JOIN sales_docs d ON d.id = i.doc_id
        WHERE d.doc_type = 'INVOICE' AND d.status <> 'CANCELLED'
          AND d.doc_date >= ? AND d.doc_date <= ?
        GROUP BY i.name ORDER BY value DESC LIMIT ?
      ''', [
        _dayStart(from).toIso8601String(),
        _dayEnd(to).toIso8601String(),
        limit,
      ]);

  Future<List<Map<String, Object?>>> topCustomers({
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) =>
      _db.rawQuery('''
        SELECT party_name AS name, COUNT(*) AS bills,
               SUM(total) AS value
        FROM sales_docs
        WHERE doc_type = 'INVOICE' AND status <> 'CANCELLED'
          AND doc_date >= ? AND doc_date <= ?
        GROUP BY party_id, party_name ORDER BY value DESC LIMIT ?
      ''', [
        _dayStart(from).toIso8601String(),
        _dayEnd(to).toIso8601String(),
        limit,
      ]);

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}
