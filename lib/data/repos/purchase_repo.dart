import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../db.dart';
import '../models.dart';
import 'party_repo.dart';
import 'payment_repo.dart';
import 'product_repo.dart';
import 'settings_repo.dart';

/// Purchase bills (GRN) and purchase returns.
class PurchaseRepo {
  Database get _db => AppDb.instance.db;

  Future<List<PurchaseDoc>> list({
    DateTime? from,
    DateTime? to,
    int? partyId,
    String docType = 'PURCHASE',
    String query = '',
    int limit = 500,
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
    if (query.trim().isNotEmpty) {
      where.add(
          '(doc_no LIKE ? OR supplier_bill_no LIKE ? OR party_name LIKE ?)');
      final like = '%${query.trim()}%';
      args.addAll([like, like, like]);
    }
    final rows = await _db.query('purchase_docs',
        where: where.join(' AND '),
        whereArgs: args,
        orderBy: 'doc_date DESC, id DESC',
        limit: limit);
    return rows.map(PurchaseDoc.fromMap).toList();
  }

  Future<PurchaseDoc?> byId(int id) async {
    final rows =
        await _db.query('purchase_docs', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final doc = PurchaseDoc.fromMap(rows.first);
    doc.items = (await _db.query('purchase_items',
            where: 'doc_id = ?', whereArgs: [id], orderBy: 'id'))
        .map(PurchaseItem.fromMap)
        .toList();
    return doc;
  }

  /// Saves a purchase, brings stock in and updates the supplier balance.
  /// Purchase rates also refresh the product cost and (optionally) MRP.
  Future<PurchaseDoc> save(
    PurchaseDoc doc, {
    AppUser? user,
    bool updateCostPrices = true,
  }) async {
    if (doc.items.isEmpty) {
      throw ArgumentError('Add at least one item before saving.');
    }
    _computeTotals(doc);
    doc.userId ??= user?.id;
    doc.createdAt ??= DateTime.now();
    final isNew = doc.id == null;

    return _db.transaction<PurchaseDoc>((txn) async {
      if (doc.id != null) {
        final oldRows = await txn
            .query('purchase_docs', where: 'id = ?', whereArgs: [doc.id]);
        if (oldRows.isEmpty) throw StateError('Purchase no longer exists.');
        final old = PurchaseDoc.fromMap(oldRows.first);
        old.items = (await txn.query('purchase_items',
                where: 'doc_id = ?', whereArgs: [doc.id]))
            .map(PurchaseItem.fromMap)
            .toList();
        await _applyEffects(txn, old, reverse: true);
        await txn
            .delete('purchase_items', where: 'doc_id = ?', whereArgs: [doc.id]);
        doc.docNo = old.docNo;
      } else if (doc.docNo.trim().isEmpty) {
        doc.docNo = await SettingsRepo.nextDocNo(txn, 'PURCHASE');
      }

      if (doc.id == null) {
        doc.id = await txn.insert('purchase_docs', doc.toMap());
      } else {
        await txn.update('purchase_docs', doc.toMap(),
            where: 'id = ?', whereArgs: [doc.id]);
      }

      for (final it in doc.items) {
        it.docId = doc.id;
        it.id = null;
        it.id = await txn.insert('purchase_items', it.toMap());
      }

      await _applyEffects(txn, doc, reverse: false);

      if (updateCostPrices && doc.docType == 'PURCHASE') {
        for (final it in doc.items) {
          if (it.productId == null || it.qty <= 0) continue;
          // Landed cost per unit, net of the supplier's line discount.
          final unitCost = Fmt.round(it.taxable / it.qty);
          final updates = <String, Object?>{
            'purchase_price': unitCost,
            'updated_at': DateTime.now().toIso8601String(),
          };
          if (it.mrp > 0) updates['mrp'] = it.mrp;
          if (it.salePrice > 0) updates['retail_price'] = it.salePrice;
          await txn.update('products', updates,
              where: 'id = ?', whereArgs: [it.productId]);
        }
      }

      if (doc.paid > 0.004) {
        await PaymentRepo.record(
          txn,
          PaymentVoucher(
            date: doc.docDate,
            direction: doc.docType == 'PURCHASE' ? 'OUT' : 'IN',
            partyId: doc.partyId,
            partyName: doc.partyName,
            docNo: doc.docNo,
            amount: doc.paid,
            mode: doc.paymentMode,
            refNo: 'AUTO-BILL',
            notes: 'Paid with ${doc.docNo}',
            userId: doc.userId,
          ),
          partyKind: 'SUPPLIER',
          settleDoc: false,
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

  Future<void> _applyEffects(
    DatabaseExecutor txn,
    PurchaseDoc doc, {
    required bool reverse,
  }) async {
    final sign = reverse ? -1.0 : 1.0;
    final isReturn = doc.docType == 'PURCHASE_RETURN';

    for (final it in doc.items) {
      if (it.productId == null) continue;
      final qty = it.qty + it.freeQty;
      final delta = sign * (isReturn ? -qty : qty);
      await ProductRepo.moveStock(
        txn,
        productId: it.productId!,
        productName: it.name,
        delta: delta,
        refType: isReturn ? StockRef.purchaseReturn : StockRef.purchase,
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
      sign * (isReturn ? -doc.total : doc.total),
    );
  }

  Future<void> delete(int id, {AppUser? user}) async {
    await _db.transaction((txn) async {
      final rows =
          await txn.query('purchase_docs', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final doc = PurchaseDoc.fromMap(rows.first);
      doc.items = (await txn
              .query('purchase_items', where: 'doc_id = ?', whereArgs: [id]))
          .map(PurchaseItem.fromMap)
          .toList();
      await _applyEffects(txn, doc, reverse: true);
      await txn.delete('purchase_docs', where: 'id = ?', whereArgs: [id]);
      await txn.insert('audit_log', {
        'at': DateTime.now().toIso8601String(),
        'user_id': user?.id,
        'user_name': user?.name ?? '',
        'action': 'DELETE',
        'entity': doc.docType,
        'entity_id': id,
        'detail': doc.docNo,
      });
    });
  }

  /// Line-by-line GST maths for an inward supply.
  static void _computeTotals(PurchaseDoc doc) {
    var taxable = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0, cess = 0.0;
    for (final it in doc.items) {
      final gross = Fmt.round(it.qty * it.rate);
      final disc = it.discountPct > 0
          ? Fmt.round(gross * it.discountPct / 100)
          : it.discountAmt;
      it.discountAmt = disc;
      it.taxable = Fmt.round(gross - disc);
      if (doc.isIgst) {
        it.igst = Fmt.round(it.taxable * it.gstRate / 100);
        it.cgst = 0;
        it.sgst = 0;
      } else {
        final half = Fmt.round(it.taxable * it.gstRate / 200);
        it.cgst = half;
        it.sgst = half;
        it.igst = 0;
      }
      it.total = Fmt.round(it.taxable + it.cgst + it.sgst + it.igst + it.cess);
      taxable += it.taxable;
      cgst += it.cgst;
      sgst += it.sgst;
      igst += it.igst;
      cess += it.cess;
    }
    doc.taxableAmount = Fmt.round(taxable);
    doc.cgst = Fmt.round(cgst);
    doc.sgst = Fmt.round(sgst);
    doc.igst = Fmt.round(igst);
    doc.cess = Fmt.round(cess);

    final before = Fmt.round(doc.taxableAmount +
        doc.cgst +
        doc.sgst +
        doc.igst +
        doc.cess +
        doc.freight +
        doc.otherCharges);
    final (rounded, delta) = Fmt.roundOff(before);
    doc.roundOff = delta;
    doc.total = rounded;
    doc.balance = Fmt.round(doc.total - doc.paid);
    doc.status = doc.paid <= 0.004
        ? 'UNPAID'
        : (doc.paid >= doc.total - 0.5 ? 'PAID' : 'PARTIAL');
  }

  Future<Map<String, double>> summary({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS bills,
             COALESCE(SUM(taxable_amount), 0) AS taxable,
             COALESCE(SUM(cgst + sgst + igst + cess), 0) AS tax,
             COALESCE(SUM(total), 0) AS total,
             COALESCE(SUM(balance), 0) AS due
      FROM purchase_docs
      WHERE doc_type = 'PURCHASE' AND doc_date >= ? AND doc_date <= ?
    ''', [_dayStart(from).toIso8601String(), _dayEnd(to).toIso8601String()]);
    final r = rows.first;
    return {
      'bills': Fmt.toDouble(r['bills']),
      'taxable': Fmt.toDouble(r['taxable']),
      'tax': Fmt.toDouble(r['tax']),
      'total': Fmt.toDouble(r['total']),
      'due': Fmt.toDouble(r['due']),
    };
  }

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
}
