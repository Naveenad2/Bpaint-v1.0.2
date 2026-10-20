import 'package:flutter_test/flutter_test.dart';
import 'package:paint_billing/core/formatters.dart';
import 'package:paint_billing/core/tax.dart';
import 'package:paint_billing/core/validators.dart';
import 'package:paint_billing/data/models.dart';

SalesItem line({
  double qty = 1,
  double rate = 100,
  double gst = 18,
  double discPct = 0,
  double discAmt = 0,
  String hsn = '3209',
}) =>
    SalesItem(
      name: 'Test',
      hsn: hsn,
      qty: qty,
      grossRate: rate,
      gstRate: gst,
      discountPct: discPct,
      discountAmt: discAmt,
    );

void main() {
  group('Line level GST', () {
    test('intra-state splits the slab into equal CGST and SGST', () {
      final it = TaxEngine.computeLine(line(qty: 2, rate: 500),
          isIgst: false, priceIncludesTax: false);
      expect(it.taxable, 1000);
      expect(it.cgst, 90);
      expect(it.sgst, 90);
      expect(it.igst, 0);
      expect(it.total, 1180);
    });

    test('inter-state charges the full slab as IGST', () {
      final it = TaxEngine.computeLine(line(qty: 2, rate: 500),
          isIgst: true, priceIncludesTax: false);
      expect(it.igst, 180);
      expect(it.cgst, 0);
      expect(it.sgst, 0);
      expect(it.total, 1180);
    });

    test('tax-inclusive rates are backed out of the price', () {
      final it = TaxEngine.computeLine(line(qty: 1, rate: 1180),
          isIgst: false, priceIncludesTax: true);
      expect(it.taxable, 1000);
      expect(it.cgst + it.sgst, 180);
      expect(it.total, 1180);
    });

    test('a percentage discount reduces the taxable value', () {
      final it = TaxEngine.computeLine(line(qty: 1, rate: 1000, discPct: 10),
          isIgst: false, priceIncludesTax: false);
      expect(it.discountAmt, 100);
      expect(it.taxable, 900);
      expect(it.total, 1062);
    });

    test('a flat discount larger than the line is clamped', () {
      final it = TaxEngine.computeLine(line(qty: 1, rate: 100, discAmt: 500),
          isIgst: false, priceIncludesTax: false);
      expect(it.taxable, 0);
      expect(it.total, 0);
    });
  });

  group('Document totals', () {
    test('sums lines, rounds once and reports the round-off', () {
      final doc = SalesDoc(items: [
        line(qty: 3, rate: 333.33),
        line(qty: 1, rate: 99.99, gst: 12),
      ]);
      TaxEngine.computeDoc(doc);
      expect(doc.total, doc.total.roundToDouble());
      final recomputed = Fmt.round(
          doc.taxableAmount + doc.cgst + doc.sgst + doc.igst + doc.roundOff);
      expect(recomputed, doc.total);
      expect(doc.roundOff.abs() <= 0.5, isTrue);
    });

    test('a bill discount is spread across lines before tax', () {
      final doc = SalesDoc(
        docDiscountPct: 10,
        items: [line(qty: 1, rate: 600), line(qty: 1, rate: 400)],
      );
      TaxEngine.computeDoc(doc, applyRoundOff: false);
      expect(doc.docDiscountAmt, 100);
      expect(doc.taxableAmount, 900);
      expect(doc.cgst + doc.sgst, Fmt.round(900 * 0.18));
    });

    test('the discount allocation never loses a paisa', () {
      final doc = SalesDoc(
        docDiscountAmt: 100,
        items: [
          line(qty: 1, rate: 333.33),
          line(qty: 1, rate: 333.33),
          line(qty: 1, rate: 333.34),
        ],
      );
      TaxEngine.computeDoc(doc, applyRoundOff: false);
      expect(doc.taxableAmount, 900);
    });

    test('mixed slabs are summarised rate-wise', () {
      final doc = SalesDoc(items: [
        line(qty: 1, rate: 1000),
        line(qty: 1, rate: 1000, gst: 12),
        line(qty: 1, rate: 500),
      ]);
      TaxEngine.computeDoc(doc);
      final slabs = TaxEngine.slabSummary(doc);
      expect(slabs.length, 2);
      expect(slabs.first.gstRate, 12);
      expect(slabs.last.gstRate, 18);
      expect(slabs.last.taxable, 1500);
    });

    test('HSN summary groups by code, rate and unit', () {
      final doc = SalesDoc(items: [
        line(qty: 2, rate: 100),
        line(qty: 3, rate: 100),
        line(qty: 1, rate: 100, hsn: '3214'),
      ]);
      TaxEngine.computeDoc(doc);
      final hsn = TaxEngine.hsnSummary(doc);
      expect(hsn.length, 2);
      expect(hsn.firstWhere((e) => e.hsn == '3209').qty, 5);
    });
  });

  group('Place of supply', () {
    test('same state is intra-state', () {
      expect(TaxEngine.interState('29', '29'), isFalse);
    });
    test('different state is inter-state', () {
      expect(TaxEngine.interState('29', '27'), isTrue);
    });
    test('a missing place of supply falls back to intra-state', () {
      expect(TaxEngine.interState('29', ''), isFalse);
    });
  });

  group('Formatting', () {
    test('rupees in words uses the Indian system', () {
      expect(NumberToWords.rupees(125430.50),
          'Rupees One Lakh Twenty Five Thousand Four Hundred Thirty and Paise Fifty Only');
      expect(NumberToWords.rupees(0), 'Rupees Zero Only');
      expect(NumberToWords.rupees(10000000), 'Rupees One Crore Only');
    });

    test('round is free of binary drift', () {
      expect(Fmt.round(0.1 + 0.2), 0.3);
      expect(Fmt.round(1234.5678), 1234.57);
      expect(Fmt.round(2.5, 0), 3);
    });

    test('round-off returns the whole rupee and the delta', () {
      final (total, delta) = Fmt.roundOff(1179.60);
      expect(total, 1180);
      expect(delta, 0.4);
    });
  });

  group('Validators', () {
    test('accepts a well-formed GSTIN', () {
      expect(V.gstin('29AAACR5055K1Z3'), isNull);
    });
    test('rejects a bad checksum', () {
      expect(V.gstin('29AAACR5055K1Z9'), isNotNull);
    });
    test('treats a blank GSTIN as valid B2C', () {
      expect(V.gstin(''), isNull);
    });
    test('checks mobile numbers', () {
      expect(V.phone('9876543210'), isNull);
      expect(V.phone('1234567890'), isNotNull);
    });
  });
}
