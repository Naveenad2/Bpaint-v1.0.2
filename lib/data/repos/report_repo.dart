import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/formatters.dart';
import '../db.dart';
import '../models.dart';

/// GST returns, registers and analytics.
///
/// Figures follow the GSTR-1 / GSTR-3B tables so the numbers can be typed
/// straight into the portal or handed to the accountant.
class ReportRepo {
  Database get _db => AppDb.instance.db;

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  List<Object?> _range(DateTime from, DateTime to) =>
      [dayStart(from).toIso8601String(), dayEnd(to).toIso8601String()];

  // ------------------------------------------------------------------
  // GSTR-1
  // ------------------------------------------------------------------
  /// Table 4 — B2B: one row per invoice raised to a GST-registered customer.
  Future<List<B2BRow>> gstr1B2B(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery('''
      SELECT doc_no, doc_date, party_gstin, party_name, place_of_supply,
             is_igst, taxable_amount, cgst, sgst, igst, cess, total, doc_type
      FROM sales_docs
      WHERE doc_type IN ('INVOICE','CREDIT_NOTE') AND status <> 'CANCELLED'
        AND LENGTH(TRIM(party_gstin)) = 15
        AND doc_date >= ? AND doc_date <= ?
      ORDER BY doc_date, doc_no
    ''', _range(from, to));
    return rows.map(B2BRow.fromMap).toList();
  }

  /// Table 7 — B2C (Small): consolidated by place of supply and rate.
  Future<List<B2CRow>> gstr1B2C(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery('''
      SELECT d.place_of_supply AS pos, i.gst_rate AS rate,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.taxable ELSE i.taxable END) AS taxable,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.cgst ELSE i.cgst END) AS cgst,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.sgst ELSE i.sgst END) AS sgst,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.igst ELSE i.igst END) AS igst,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.cess ELSE i.cess END) AS cess
      FROM sales_items i JOIN sales_docs d ON d.id = i.doc_id
      WHERE d.doc_type IN ('INVOICE','CREDIT_NOTE') AND d.status <> 'CANCELLED'
        AND LENGTH(TRIM(d.party_gstin)) <> 15
        AND d.doc_date >= ? AND d.doc_date <= ?
      GROUP BY pos, rate ORDER BY pos, rate
    ''', _range(from, to));
    return rows.map(B2CRow.fromMap).toList();
  }

  /// Table 12 — HSN-wise outward supply summary.
  Future<List<HsnSummaryRow>> hsnSummary(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery('''
      SELECT i.hsn AS hsn, i.unit AS unit, i.gst_rate AS rate,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.qty ELSE i.qty END) AS qty,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.taxable ELSE i.taxable END) AS taxable,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.cgst ELSE i.cgst END) AS cgst,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.sgst ELSE i.sgst END) AS sgst,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.igst ELSE i.igst END) AS igst,
             SUM(CASE WHEN d.doc_type = 'CREDIT_NOTE' THEN -i.cess ELSE i.cess END) AS cess
      FROM sales_items i JOIN sales_docs d ON d.id = i.doc_id
      WHERE d.doc_type IN ('INVOICE','CREDIT_NOTE') AND d.status <> 'CANCELLED'
        AND d.doc_date >= ? AND d.doc_date <= ?
      GROUP BY hsn, unit, rate ORDER BY hsn
    ''', _range(from, to));
    return rows.map(HsnSummaryRow.fromMap).toList();
  }

  /// Table 13 — documents issued, including cancelled numbers.
  Future<Map<String, Map<String, Object?>>> docsIssued(
      DateTime from, DateTime to) async {
    final rows = await _db.rawQuery('''
      SELECT doc_type,
             MIN(doc_no) AS first_no, MAX(doc_no) AS last_no,
             COUNT(*) AS total,
             SUM(CASE WHEN status = 'CANCELLED' THEN 1 ELSE 0 END) AS cancelled
      FROM sales_docs
      WHERE doc_date >= ? AND doc_date <= ?
      GROUP BY doc_type
    ''', _range(from, to));
    return {for (final r in rows) r['doc_type'] as String: r};
  }

  /// GSTR-3B section 3.1 (outward) and 4 (input tax credit).
  Future<Gstr3B> gstr3b(DateTime from, DateTime to) async {
    final out = await _db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN doc_type='CREDIT_NOTE' THEN -taxable_amount ELSE taxable_amount END),0) AS taxable,
             COALESCE(SUM(CASE WHEN doc_type='CREDIT_NOTE' THEN -cgst ELSE cgst END),0) AS cgst,
             COALESCE(SUM(CASE WHEN doc_type='CREDIT_NOTE' THEN -sgst ELSE sgst END),0) AS sgst,
             COALESCE(SUM(CASE WHEN doc_type='CREDIT_NOTE' THEN -igst ELSE igst END),0) AS igst,
             COALESCE(SUM(CASE WHEN doc_type='CREDIT_NOTE' THEN -cess ELSE cess END),0) AS cess
      FROM sales_docs
      WHERE doc_type IN ('INVOICE','CREDIT_NOTE') AND status <> 'CANCELLED'
        AND doc_date >= ? AND doc_date <= ?
    ''', _range(from, to));

    final inp = await _db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN doc_type='PURCHASE_RETURN' THEN -taxable_amount ELSE taxable_amount END),0) AS taxable,
             COALESCE(SUM(CASE WHEN doc_type='PURCHASE_RETURN' THEN -cgst ELSE cgst END),0) AS cgst,
             COALESCE(SUM(CASE WHEN doc_type='PURCHASE_RETURN' THEN -sgst ELSE sgst END),0) AS sgst,
             COALESCE(SUM(CASE WHEN doc_type='PURCHASE_RETURN' THEN -igst ELSE igst END),0) AS igst,
             COALESCE(SUM(CASE WHEN doc_type='PURCHASE_RETURN' THEN -cess ELSE cess END),0) AS cess
      FROM purchase_docs WHERE doc_date >= ? AND doc_date <= ?
    ''', _range(from, to));

    return Gstr3B(
      outwardTaxable: Fmt.toDouble(out.first['taxable']),
      outCgst: Fmt.toDouble(out.first['cgst']),
      outSgst: Fmt.toDouble(out.first['sgst']),
      outIgst: Fmt.toDouble(out.first['igst']),
      outCess: Fmt.toDouble(out.first['cess']),
      inwardTaxable: Fmt.toDouble(inp.first['taxable']),
      itcCgst: Fmt.toDouble(inp.first['cgst']),
      itcSgst: Fmt.toDouble(inp.first['sgst']),
      itcIgst: Fmt.toDouble(inp.first['igst']),
      itcCess: Fmt.toDouble(inp.first['cess']),
    );
  }

  // ------------------------------------------------------------------
  // Registers
  // ------------------------------------------------------------------
  Future<List<Map<String, Object?>>> salesRegister(
          DateTime from, DateTime to) =>
      _db.rawQuery('''
        SELECT doc_date, doc_no, doc_type, party_name, party_gstin,
               place_of_supply, taxable_amount, cgst, sgst, igst, cess,
               round_off, total, paid, balance, status, payment_mode, user_name
        FROM sales_docs
        WHERE doc_type IN ('INVOICE','CREDIT_NOTE')
          AND doc_date >= ? AND doc_date <= ?
        ORDER BY doc_date, doc_no
      ''', _range(from, to));

  Future<List<Map<String, Object?>>> purchaseRegister(
          DateTime from, DateTime to) =>
      _db.rawQuery('''
        SELECT doc_date, doc_no, supplier_bill_no, doc_type, party_name,
               party_gstin, taxable_amount, cgst, sgst, igst, cess, total,
               paid, balance, status
        FROM purchase_docs
        WHERE doc_date >= ? AND doc_date <= ?
        ORDER BY doc_date, doc_no
      ''', _range(from, to));

  Future<List<Map<String, Object?>>> itemWiseSales(
          DateTime from, DateTime to) =>
      _db.rawQuery('''
        SELECT i.sku, i.name, i.hsn, i.unit,
               SUM(i.qty) AS qty, SUM(i.taxable) AS taxable,
               SUM(i.cgst + i.sgst + i.igst + i.cess) AS tax,
               SUM(i.total) AS total,
               SUM(i.cost_price * i.qty) AS cost,
               SUM(i.taxable - i.cost_price * i.qty) AS profit
        FROM sales_items i JOIN sales_docs d ON d.id = i.doc_id
        WHERE d.doc_type = 'INVOICE' AND d.status <> 'CANCELLED'
          AND d.doc_date >= ? AND d.doc_date <= ?
        GROUP BY i.name ORDER BY total DESC
      ''', _range(from, to));

  Future<List<Map<String, Object?>>> stockReport({bool onlyLow = false}) =>
      _db.rawQuery('''
        SELECT sku, name, brand, category, pack_size, unit, rack,
               stock, min_stock, purchase_price, retail_price, mrp,
               ROUND(stock * purchase_price, 2) AS cost_value,
               ROUND(stock * retail_price, 2) AS sale_value
        FROM products
        WHERE active = 1 AND is_service = 0
        ${onlyLow ? 'AND stock <= min_stock' : ''}
        ORDER BY name COLLATE NOCASE
      ''');

  /// Items with no sale in the given number of days — dead stock.
  Future<List<Map<String, Object?>>> deadStock({int days = 90}) {
    final since =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return _db.rawQuery('''
      SELECT p.sku, p.name, p.brand, p.pack_size, p.stock,
             ROUND(p.stock * p.purchase_price, 2) AS cost_value,
             (SELECT MAX(d.doc_date) FROM sales_items i
                JOIN sales_docs d ON d.id = i.doc_id
               WHERE i.product_id = p.id AND d.status <> 'CANCELLED') AS last_sold
      FROM products p
      WHERE p.active = 1 AND p.is_service = 0 AND p.stock > 0
        AND (last_sold IS NULL OR last_sold < ?)
      ORDER BY cost_value DESC
    ''', [since]);
  }

  /// Outstanding receivables bucketed by age.
  Future<List<AgeingRow>> receivablesAgeing({int? partyId}) async {
    final rows = await _db.rawQuery('''
      SELECT d.id, d.doc_no, d.doc_date, d.party_id, d.party_name,
             d.party_phone, d.total, d.paid, d.balance, d.due_date
      FROM sales_docs d
      WHERE d.doc_type = 'INVOICE' AND d.status IN ('UNPAID','PARTIAL')
        AND d.balance > 0.5
        ${partyId != null ? 'AND d.party_id = ?' : ''}
      ORDER BY d.doc_date
    ''', partyId != null ? [partyId] : null);
    final now = DateTime.now();
    return rows.map((r) {
      final date = Fmt.parseIso(r['doc_date'] as String?) ?? now;
      final days = now.difference(date).inDays;
      return AgeingRow(
        docId: Fmt.toInt(r['id']),
        docNo: (r['doc_no'] ?? '') as String,
        date: date,
        partyId: r['party_id'] as int?,
        partyName: (r['party_name'] ?? '') as String,
        partyPhone: (r['party_phone'] ?? '') as String,
        total: Fmt.toDouble(r['total']),
        balance: Fmt.toDouble(r['balance']),
        days: days,
      );
    }).toList();
  }

  /// Cash book for the day-close screen.
  Future<DaySummary> dayBook(DateTime day) async {
    final range = _range(day, day);
    final sales = await _db.rawQuery('''
      SELECT COUNT(*) AS bills, COALESCE(SUM(total),0) AS total,
             COALESCE(SUM(paid),0) AS paid, COALESCE(SUM(balance),0) AS credit
      FROM sales_docs
      WHERE doc_type='INVOICE' AND status <> 'CANCELLED'
        AND doc_date >= ? AND doc_date <= ?
    ''', range);
    final returns = await _db.rawQuery('''
      SELECT COALESCE(SUM(total),0) AS total FROM sales_docs
      WHERE doc_type='CREDIT_NOTE' AND status <> 'CANCELLED'
        AND doc_date >= ? AND doc_date <= ?
    ''', range);
    final receipts = await _db.rawQuery('''
      SELECT mode, direction, COALESCE(SUM(amount),0) AS amt
      FROM payments WHERE date >= ? AND date <= ?
      GROUP BY mode, direction
    ''', range);
    final expenses = await _db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) AS amt FROM expenses
      WHERE date >= ? AND date <= ?
    ''', range);

    final byMode = <String, double>{};
    for (final r in receipts) {
      final mode = (r['mode'] ?? 'CASH') as String;
      final amt = Fmt.toDouble(r['amt']);
      byMode[mode] = Fmt.round(
          (byMode[mode] ?? 0) + (r['direction'] == 'IN' ? amt : -amt));
    }

    return DaySummary(
      day: day,
      bills: Fmt.toInt(sales.first['bills']),
      salesTotal: Fmt.toDouble(sales.first['total']),
      collected: Fmt.toDouble(sales.first['paid']),
      creditGiven: Fmt.toDouble(sales.first['credit']),
      returns: Fmt.toDouble(returns.first['total']),
      expenses: Fmt.toDouble(expenses.first['amt']),
      collectionByMode: byMode,
    );
  }

  // ------------------------------------------------------------------
  // Expenses
  // ------------------------------------------------------------------
  Future<List<Expense>> expenses(DateTime from, DateTime to) async {
    final rows = await _db.query('expenses',
        where: 'date >= ? AND date <= ?',
        whereArgs: _range(from, to),
        orderBy: 'date DESC, id DESC');
    return rows.map(Expense.fromMap).toList();
  }

  Future<int> saveExpense(Expense e) async {
    if (e.id == null) return _db.insert('expenses', e.toMap());
    await _db.update('expenses', e.toMap(), where: 'id = ?', whereArgs: [e.id]);
    return e.id!;
  }

  Future<void> deleteExpense(int id) =>
      _db.delete('expenses', where: 'id = ?', whereArgs: [id]);

  Future<double> expenseTotal(DateTime from, DateTime to) async {
    final rows = await _db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS t FROM expenses WHERE date >= ? AND date <= ?',
        _range(from, to));
    return Fmt.toDouble(rows.first['t']);
  }
}

// ---------------------------------------------------------------------------
// Report row types
// ---------------------------------------------------------------------------
class B2BRow {
  final String docNo;
  final DateTime date;
  final String gstin;
  final String name;
  final String pos;
  final bool isIgst;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;
  final double cess;
  final double total;
  final String docType;

  B2BRow({
    required this.docNo,
    required this.date,
    required this.gstin,
    required this.name,
    required this.pos,
    required this.isIgst,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.cess,
    required this.total,
    required this.docType,
  });

  factory B2BRow.fromMap(Map<String, Object?> m) {
    final credit = m['doc_type'] == 'CREDIT_NOTE';
    final sign = credit ? -1.0 : 1.0;
    return B2BRow(
      docNo: (m['doc_no'] ?? '') as String,
      date: Fmt.parseIso(m['doc_date'] as String?) ?? DateTime.now(),
      gstin: (m['party_gstin'] ?? '') as String,
      name: (m['party_name'] ?? '') as String,
      pos: (m['place_of_supply'] ?? '') as String,
      isIgst: Fmt.toBool(m['is_igst']),
      taxable: sign * Fmt.toDouble(m['taxable_amount']),
      cgst: sign * Fmt.toDouble(m['cgst']),
      sgst: sign * Fmt.toDouble(m['sgst']),
      igst: sign * Fmt.toDouble(m['igst']),
      cess: sign * Fmt.toDouble(m['cess']),
      total: sign * Fmt.toDouble(m['total']),
      docType: (m['doc_type'] ?? '') as String,
    );
  }
}

class B2CRow {
  final String pos;
  final double rate;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;
  final double cess;

  B2CRow({
    required this.pos,
    required this.rate,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.cess,
  });

  factory B2CRow.fromMap(Map<String, Object?> m) => B2CRow(
        pos: (m['pos'] ?? '') as String,
        rate: Fmt.toDouble(m['rate']),
        taxable: Fmt.toDouble(m['taxable']),
        cgst: Fmt.toDouble(m['cgst']),
        sgst: Fmt.toDouble(m['sgst']),
        igst: Fmt.toDouble(m['igst']),
        cess: Fmt.toDouble(m['cess']),
      );

  double get total => taxable + cgst + sgst + igst + cess;
}

class HsnSummaryRow {
  final String hsn;
  final String unit;
  final double rate;
  final double qty;
  final double taxable;
  final double cgst;
  final double sgst;
  final double igst;
  final double cess;

  HsnSummaryRow({
    required this.hsn,
    required this.unit,
    required this.rate,
    required this.qty,
    required this.taxable,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.cess,
  });

  factory HsnSummaryRow.fromMap(Map<String, Object?> m) => HsnSummaryRow(
        hsn: ((m['hsn'] ?? '') as String).isEmpty ? '-' : m['hsn'] as String,
        unit: (m['unit'] ?? '') as String,
        rate: Fmt.toDouble(m['rate']),
        qty: Fmt.toDouble(m['qty']),
        taxable: Fmt.toDouble(m['taxable']),
        cgst: Fmt.toDouble(m['cgst']),
        sgst: Fmt.toDouble(m['sgst']),
        igst: Fmt.toDouble(m['igst']),
        cess: Fmt.toDouble(m['cess']),
      );

  double get total => taxable + cgst + sgst + igst + cess;
}

class Gstr3B {
  final double outwardTaxable;
  final double outCgst;
  final double outSgst;
  final double outIgst;
  final double outCess;
  final double inwardTaxable;
  final double itcCgst;
  final double itcSgst;
  final double itcIgst;
  final double itcCess;

  Gstr3B({
    required this.outwardTaxable,
    required this.outCgst,
    required this.outSgst,
    required this.outIgst,
    required this.outCess,
    required this.inwardTaxable,
    required this.itcCgst,
    required this.itcSgst,
    required this.itcIgst,
    required this.itcCess,
  });

  double get outputTax => outCgst + outSgst + outIgst + outCess;
  double get inputTax => itcCgst + itcSgst + itcIgst + itcCess;
  double get netPayable => Fmt.round(outputTax - inputTax);
}

class AgeingRow {
  final int docId;
  final String docNo;
  final DateTime date;
  final int? partyId;
  final String partyName;
  final String partyPhone;
  final double total;
  final double balance;
  final int days;

  AgeingRow({
    required this.docId,
    required this.docNo,
    required this.date,
    required this.partyId,
    required this.partyName,
    required this.partyPhone,
    required this.total,
    required this.balance,
    required this.days,
  });

  String get bucket {
    if (days <= 15) return '0-15 days';
    if (days <= 30) return '16-30 days';
    if (days <= 60) return '31-60 days';
    if (days <= 90) return '61-90 days';
    return 'Over 90 days';
  }
}

class DaySummary {
  final DateTime day;
  final int bills;
  final double salesTotal;
  final double collected;
  final double creditGiven;
  final double returns;
  final double expenses;
  final Map<String, double> collectionByMode;

  DaySummary({
    required this.day,
    required this.bills,
    required this.salesTotal,
    required this.collected,
    required this.creditGiven,
    required this.returns,
    required this.expenses,
    required this.collectionByMode,
  });

  double get cashInHand =>
      Fmt.round((collectionByMode['CASH'] ?? 0) - expenses);
  double get netSales => Fmt.round(salesTotal - returns);
}
