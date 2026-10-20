import '../data/models.dart';
import 'formatters.dart';

/// GST computation engine.
///
/// Rules implemented (CGST Act / Rule 46):
///  * Tax is computed **line by line**, then summed — never on the bill total.
///  * Intra-state supply (supplier state == place of supply) splits into
///    CGST + SGST at half the slab each. Inter-state uses IGST at the full slab.
///  * A bill-level discount is spread across lines *before* tax, because a
///    discount shown on the face of the invoice reduces the taxable value
///    (Sec. 15(3)(a)).
///  * MRP-inclusive billing back-calculates the taxable value as
///    `inclusive / (1 + rate/100)`.
///  * Freight and other charges are added after tax and are shown separately.
///  * The final round-off is applied once, to the bill total.
class TaxEngine {
  /// Recomputes a single line in place and returns it.
  static SalesItem computeLine(
    SalesItem it, {
    required bool isIgst,
    required bool priceIncludesTax,
  }) {
    final qty = it.qty <= 0 ? 0.0 : it.qty;
    final gross = Fmt.round(qty * it.grossRate);

    // Percentage discount first, then any flat amount typed by the operator.
    final pctPart = Fmt.round(gross * (it.discountPct / 100));
    final flatPart = it.discountPct > 0 ? 0.0 : it.discountAmt;
    final discount = Fmt.round(
      (pctPart + flatPart).clamp(0, gross).toDouble(),
    );
    it.discountAmt = it.discountPct > 0 ? pctPart : discount;

    final netAmount = Fmt.round(gross - it.discountAmt);
    final rateSum = it.gstRate + it.cessRate;

    final double taxable;
    if (priceIncludesTax && rateSum > 0) {
      taxable = Fmt.round(netAmount / (1 + rateSum / 100));
    } else {
      taxable = netAmount;
    }

    it.taxable = taxable;
    it.rate = qty > 0 ? Fmt.round(taxable / qty, 4) : 0;

    if (isIgst) {
      it.igst = Fmt.round(taxable * it.gstRate / 100);
      it.cgst = 0;
      it.sgst = 0;
    } else {
      final half = Fmt.round(taxable * it.gstRate / 200);
      it.cgst = half;
      it.sgst = half;
      it.igst = 0;
    }
    it.cess = Fmt.round(taxable * it.cessRate / 100);
    it.total = Fmt.round(taxable + it.cgst + it.sgst + it.igst + it.cess);
    return it;
  }

  /// Recomputes every line and all document totals in place.
  static SalesDoc computeDoc(SalesDoc doc, {bool applyRoundOff = true}) {
    // 1. Line-level values at the typed rates.
    var gross = 0.0;
    var itemDiscount = 0.0;
    for (final it in doc.items) {
      computeLine(it,
          isIgst: doc.isIgst, priceIncludesTax: doc.priceIncludesTax);
      gross += Fmt.round(it.qty * it.grossRate);
      itemDiscount += it.discountAmt;
    }
    gross = Fmt.round(gross);
    itemDiscount = Fmt.round(itemDiscount);

    // 2. Bill-level discount, spread proportionally over the line taxables.
    final baseTaxable =
        Fmt.round(doc.items.fold<double>(0.0, (s, e) => s + e.taxable));
    var docDiscount = 0.0;
    if (doc.docDiscountPct > 0) {
      docDiscount = Fmt.round(baseTaxable * doc.docDiscountPct / 100);
    } else if (doc.docDiscountAmt > 0) {
      docDiscount = Fmt.round(doc.docDiscountAmt);
    }
    if (docDiscount > baseTaxable) docDiscount = baseTaxable;
    doc.docDiscountAmt = docDiscount;

    if (docDiscount > 0 && baseTaxable > 0) {
      var allocated = 0.0;
      for (var i = 0; i < doc.items.length; i++) {
        final it = doc.items[i];
        final share = (i == doc.items.length - 1)
            ? Fmt.round(docDiscount - allocated)
            : Fmt.round(docDiscount * (it.taxable / baseTaxable));
        allocated = Fmt.round(allocated + share);

        it.taxable = Fmt.round(it.taxable - share);
        it.rate = it.qty > 0 ? Fmt.round(it.taxable / it.qty, 4) : 0;
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
        it.cess = Fmt.round(it.taxable * it.cessRate / 100);
        it.total =
            Fmt.round(it.taxable + it.cgst + it.sgst + it.igst + it.cess);
      }
    }

    // 3. Roll the lines up.
    var taxable = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0, cess = 0.0;
    for (final it in doc.items) {
      taxable += it.taxable;
      cgst += it.cgst;
      sgst += it.sgst;
      igst += it.igst;
      cess += it.cess;
    }

    doc.grossAmount = gross;
    doc.itemDiscount = itemDiscount;
    doc.taxableAmount = Fmt.round(taxable);
    doc.cgst = Fmt.round(cgst);
    doc.sgst = Fmt.round(sgst);
    doc.igst = Fmt.round(igst);
    doc.cess = Fmt.round(cess);

    final beforeRound = Fmt.round(doc.taxableAmount +
        doc.cgst +
        doc.sgst +
        doc.igst +
        doc.cess +
        doc.freight +
        doc.otherCharges);

    if (applyRoundOff) {
      final (rounded, delta) = Fmt.roundOff(beforeRound);
      doc.roundOff = delta;
      doc.total = rounded;
    } else {
      doc.roundOff = 0;
      doc.total = beforeRound;
    }

    doc.balance = Fmt.round(doc.total - doc.paid);
    doc.status = statusFor(doc.total, doc.paid, current: doc.status);
    return doc;
  }

  static String statusFor(double total, double paid,
      {String current = 'UNPAID'}) {
    if (current == 'CANCELLED') return current;
    if (paid <= 0.004) return 'UNPAID';
    if (paid >= total - 0.5) return 'PAID';
    return 'PARTIAL';
  }

  /// True when the transaction is inter-state and must carry IGST.
  static bool interState(String? supplierStateCode, String? placeOfSupply) {
    final a = (supplierStateCode ?? '').trim();
    final b = (placeOfSupply ?? '').trim();
    if (a.isEmpty || b.isEmpty) return false;
    return a != b;
  }

  /// Rate-wise tax summary printed on the invoice footer.
  static List<TaxSlabRow> slabSummary(SalesDoc doc) {
    final map = <String, TaxSlabRow>{};
    for (final it in doc.items) {
      final key = '${it.gstRate}|${it.cessRate}';
      final row = map.putIfAbsent(
        key,
        () => TaxSlabRow(gstRate: it.gstRate, cessRate: it.cessRate),
      );
      row.taxable += it.taxable;
      row.cgst += it.cgst;
      row.sgst += it.sgst;
      row.igst += it.igst;
      row.cess += it.cess;
    }
    final rows = map.values.toList()
      ..sort((a, b) => a.gstRate.compareTo(b.gstRate));
    for (final r in rows) {
      r.taxable = Fmt.round(r.taxable);
      r.cgst = Fmt.round(r.cgst);
      r.sgst = Fmt.round(r.sgst);
      r.igst = Fmt.round(r.igst);
      r.cess = Fmt.round(r.cess);
    }
    return rows;
  }

  /// HSN-wise summary — mandatory on B2B invoices and in GSTR-1 Table 12.
  static List<HsnRow> hsnSummary(SalesDoc doc) {
    final map = <String, HsnRow>{};
    for (final it in doc.items) {
      final key = '${it.hsn}|${it.gstRate}|${it.unit}';
      final row = map.putIfAbsent(
        key,
        () => HsnRow(
          hsn: it.hsn.isEmpty ? '-' : it.hsn,
          unit: it.unit,
          gstRate: it.gstRate,
        ),
      );
      row.qty += it.qty;
      row.taxable += it.taxable;
      row.cgst += it.cgst;
      row.sgst += it.sgst;
      row.igst += it.igst;
      row.cess += it.cess;
    }
    final rows = map.values.toList()..sort((a, b) => a.hsn.compareTo(b.hsn));
    for (final r in rows) {
      r.qty = Fmt.round(r.qty, 3);
      r.taxable = Fmt.round(r.taxable);
      r.cgst = Fmt.round(r.cgst);
      r.sgst = Fmt.round(r.sgst);
      r.igst = Fmt.round(r.igst);
      r.cess = Fmt.round(r.cess);
    }
    return rows;
  }

  /// Builds a line from a product using the customer's price tier.
  static SalesItem lineFromProduct(
    Product p, {
    double qty = 1,
    String tier = 'RETAIL',
    bool priceIncludesTax = false,
    bool isIgst = false,
  }) {
    final it = SalesItem(
      productId: p.id,
      sku: p.sku,
      name: p.fullName,
      hsn: p.hsn,
      shade: p.shadeName.isNotEmpty ? p.shadeName : p.shadeCode,
      packSize: p.packSize,
      unit: p.unit,
      qty: qty,
      mrp: p.mrp,
      grossRate: p.priceFor(tier),
      gstRate: p.gstRate,
      cessRate: p.cessRate,
      costPrice: p.purchasePrice,
    );
    return computeLine(it, isIgst: isIgst, priceIncludesTax: priceIncludesTax);
  }
}

class TaxSlabRow {
  final double gstRate;
  final double cessRate;
  double taxable;
  double cgst;
  double sgst;
  double igst;
  double cess;

  TaxSlabRow({
    required this.gstRate,
    this.cessRate = 0,
    this.taxable = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cess = 0,
  });

  double get totalTax => cgst + sgst + igst + cess;
}

class HsnRow {
  final String hsn;
  final String unit;
  final double gstRate;
  double qty;
  double taxable;
  double cgst;
  double sgst;
  double igst;
  double cess;

  HsnRow({
    required this.hsn,
    this.unit = '',
    this.gstRate = 0,
    this.qty = 0,
    this.taxable = 0,
    this.cgst = 0,
    this.sgst = 0,
    this.igst = 0,
    this.cess = 0,
  });

  double get total => taxable + cgst + sgst + igst + cess;
}
