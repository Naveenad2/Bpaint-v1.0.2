import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paint_billing/core/constants.dart';
import 'package:paint_billing/core/formatters.dart';
import 'package:paint_billing/core/tax.dart';
import 'package:paint_billing/data/db.dart';
import 'package:paint_billing/data/models.dart';
import 'package:paint_billing/data/repos/party_repo.dart';
import 'package:paint_billing/data/repos/payment_repo.dart';
import 'package:paint_billing/data/repos/product_repo.dart';
import 'package:paint_billing/data/repos/purchase_repo.dart';
import 'package:paint_billing/data/repos/report_repo.dart';
import 'package:paint_billing/data/repos/sales_repo.dart';
import 'package:paint_billing/data/repos/settings_repo.dart';

/// End-to-end checks against a real SQLite file: a bill must move stock, the
/// customer balance, the receipt book and the GST reports together, and every
/// reversal must put all four back.
void main() {
  late Directory tmp;
  final products = ProductRepo();
  final parties = PartyRepo();
  final sales = SalesRepo();
  final purchases = PurchaseRepo();
  final payments = PaymentRepo();
  final reports = ReportRepo();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('paintpro_test_');
    await AppDb.instance.init(overrideDir: tmp.path);
  });

  tearDown(() async {
    await AppDb.instance.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<Product> makeProduct({double stock = 50, double rate = 1000}) async {
    final id = await products.save(Product(
      name: 'Premium Emulsion',
      brand: 'Test',
      packSize: '4 LTR',
      unit: 'LTR',
      hsn: '3209',
      purchasePrice: rate * 0.7,
      retailPrice: rate,
      mrp: rate * 1.1,
      gstRate: 18,
      openingStock: stock,
      minStock: 5,
    ));
    return (await products.byId(id))!;
  }

  Future<Party> makeCustomer({String state = '29'}) async {
    final id = await parties.save(Party(
      kind: 'CUSTOMER',
      name: 'Test Customer',
      phone: '9876543210',
      stateCode: state,
    ));
    return (await parties.byId(id))!;
  }

  SalesDoc billFor(Product p, Party c, {double qty = 2, double paid = 0}) {
    final doc = SalesDoc(
      docType: DocType.invoice,
      partyId: c.id,
      partyName: c.name,
      partyPhone: c.phone,
      placeOfSupply: c.stateCode,
      isIgst: false,
      paymentMode: paid > 0 ? PaymentModes.cash : PaymentModes.credit,
      paid: paid,
      items: [TaxEngine.lineFromProduct(p, qty: qty)],
    );
    return doc;
  }

  test('first run seeds the schema, admin user and walk-in customer', () async {
    final settings = SettingsRepo();
    await settings.load();
    expect(settings.get(SKeys.invoicePrefix), 'INV-');
    expect(settings.get(SKeys.printFormat), PrintFormat.a5Landscape);
    final walkIn = await parties.byId(1);
    expect(walkIn, isNotNull);
    expect(walkIn!.isWalkIn, isTrue);
  });

  test('a cash bill moves stock, settles itself and writes a receipt',
      () async {
    final p = await makeProduct(stock: 50, rate: 1000);
    final c = await makeCustomer();

    final saved = await sales.save(billFor(p, c, qty: 2, paid: 2360));

    expect(saved.docNo, 'INV-0001');
    expect(saved.taxableAmount, 2000);
    expect(saved.cgst, 180);
    expect(saved.sgst, 180);
    expect(saved.igst, 0);
    expect(saved.total, 2360);
    expect(saved.status, DocStatus.paid);

    // Stock went down by exactly the billed quantity.
    expect(await products.stockOf(p.id!), 48);

    // Paid in full, so the customer owes nothing.
    final after = await parties.byId(c.id);
    expect(after!.balance, 0);

    // The counter receipt exists and is linked to the bill.
    final vouchers = await payments.list(partyId: c.id);
    expect(vouchers.length, 1);
    expect(vouchers.first.amount, 2360);
    expect(vouchers.first.docNo, 'INV-0001');

    // The stock ledger records the movement against the bill.
    final moves = await products.moves(p.id!);
    expect(moves.first.refNo, 'INV-0001');
    expect(moves.first.qtyOut, 2);
    expect(moves.first.balanceAfter, 48);
  });

  test('a credit sale leaves the balance outstanding', () async {
    final p = await makeProduct();
    final c = await makeCustomer();
    final saved = await sales.save(billFor(p, c, qty: 1, paid: 0));

    expect(saved.status, DocStatus.unpaid);
    expect(saved.balance, saved.total);
    expect((await parties.byId(c.id))!.balance, saved.total);

    // Collecting it later clears both the bill and the ledger.
    await payments.save(
      PaymentVoucher(
        partyId: c.id,
        partyName: c.name,
        docId: saved.id,
        docNo: saved.docNo,
        amount: saved.total,
        mode: PaymentModes.cash,
      ),
      partyKind: 'CUSTOMER',
    );
    expect((await parties.byId(c.id))!.balance, 0);
    expect((await sales.byId(saved.id!))!.status, DocStatus.paid);
  });

  test('bill numbers are sequential and never reused', () async {
    final p = await makeProduct(stock: 100);
    final c = await makeCustomer();
    final a = await sales.save(billFor(p, c, qty: 1, paid: 1180));
    final b = await sales.save(billFor(p, c, qty: 1, paid: 1180));
    expect(a.docNo, 'INV-0001');
    expect(b.docNo, 'INV-0002');

    // Cancelling keeps the number in the books.
    await sales.cancel(a.id!);
    final c3 = await sales.save(billFor(p, c, qty: 1, paid: 1180));
    expect(c3.docNo, 'INV-0003');
    expect((await sales.byId(a.id!))!.status, DocStatus.cancelled);
  });

  test('cancelling a bill returns stock and reverses the ledger', () async {
    final p = await makeProduct(stock: 50);
    final c = await makeCustomer();
    final saved = await sales.save(billFor(p, c, qty: 5, paid: 0));

    expect(await products.stockOf(p.id!), 45);
    expect((await parties.byId(c.id))!.balance, saved.total);

    await sales.cancel(saved.id!, reason: 'wrong shade');

    expect(await products.stockOf(p.id!), 50);
    expect((await parties.byId(c.id))!.balance, 0);
  });

  test('editing a bill reverses the old version exactly once', () async {
    final p = await makeProduct(stock: 50);
    final c = await makeCustomer();
    final saved = await sales.save(billFor(p, c, qty: 5, paid: 0));
    expect(await products.stockOf(p.id!), 45);

    saved.items.first.qty = 2;
    final again = await sales.save(saved);

    expect(again.docNo, 'INV-0001', reason: 'number must not change');
    expect(await products.stockOf(p.id!), 48);
    expect((await parties.byId(c.id))!.balance, again.total);
  });

  test('a credit note brings stock back and credits the customer', () async {
    final p = await makeProduct(stock: 50);
    final c = await makeCustomer();
    final inv = await sales.save(billFor(p, c, qty: 4, paid: 0));
    expect(await products.stockOf(p.id!), 46);

    final cn = await sales.creditNoteFrom(inv);
    cn.items.first.qty = 1;
    final saved = await sales.save(cn);

    expect(saved.docNo, 'CN-0001');
    expect(await products.stockOf(p.id!), 47);
    expect((await parties.byId(c.id))!.balance,
        Fmt.round(inv.total - saved.total));
  });

  test('stock cannot go negative unless explicitly allowed', () async {
    final p = await makeProduct(stock: 2);
    final c = await makeCustomer();

    expect(
      () => sales.save(billFor(p, c, qty: 5)),
      throwsA(isA<InsufficientStock>()),
    );
    expect(await products.stockOf(p.id!), 2, reason: 'nothing was committed');

    final forced =
        await sales.save(billFor(p, c, qty: 5), allowNegativeStock: true);
    expect(forced.docNo, 'INV-0001');
    expect(await products.stockOf(p.id!), -3);
  });

  test('an out-of-state customer is billed IGST', () async {
    final p = await makeProduct();
    final c = await makeCustomer(state: '27');
    final doc = billFor(p, c, qty: 1);
    doc.isIgst = TaxEngine.interState('29', c.stateCode);
    final saved = await sales.save(doc);

    expect(saved.isIgst, isTrue);
    expect(saved.igst, 180);
    expect(saved.cgst, 0);
    expect(saved.sgst, 0);
  });

  test('a purchase brings stock in and updates the cost price', () async {
    final p = await makeProduct(stock: 10, rate: 1000);
    final sid = await parties.save(Party(
      kind: 'SUPPLIER',
      name: 'Test Depot',
      stateCode: '29',
    ));

    final doc = PurchaseDoc(
      partyId: sid,
      partyName: 'Test Depot',
      supplierBillNo: 'SB/1',
      items: [
        PurchaseItem(
          productId: p.id,
          name: p.fullName,
          qty: 20,
          rate: 800,
          mrp: 1200,
          salePrice: 1100,
          gstRate: 18,
        ),
      ],
    );
    final saved = await purchases.save(doc);

    expect(saved.docNo, 'PUR-0001');
    expect(saved.taxableAmount, 16000);
    expect(saved.total, 18880);
    expect(await products.stockOf(p.id!), 30);

    final updated = await products.byId(p.id);
    expect(updated!.purchasePrice, 800);
    expect(updated.retailPrice, 1100);
    expect(updated.mrp, 1200);

    // We owe the supplier the full amount.
    expect((await parties.byId(sid))!.balance, 18880);
  });

  test('GST reports pick up B2B, B2C and HSN rows', () async {
    final p = await makeProduct(stock: 100);
    final b2c = await makeCustomer();
    final b2bId = await parties.save(Party(
      kind: 'CUSTOMER',
      name: 'Registered Dealer',
      gstin: '29AAACR5055K1Z3',
      stateCode: '29',
    ));
    final b2b = (await parties.byId(b2bId))!;

    await sales.save(billFor(p, b2c, qty: 1, paid: 1180));
    final b2bDoc = billFor(p, b2b, qty: 2, paid: 2360);
    b2bDoc.partyGstin = b2b.gstin;
    await sales.save(b2bDoc);

    final now = DateTime.now();
    final b2bRows = await reports.gstr1B2B(now, now);
    expect(b2bRows.length, 1);
    expect(b2bRows.first.gstin, '29AAACR5055K1Z3');
    expect(b2bRows.first.taxable, 2000);

    final b2cRows = await reports.gstr1B2C(now, now);
    expect(b2cRows.length, 1);
    expect(b2cRows.first.taxable, 1000);

    final hsn = await reports.hsnSummary(now, now);
    expect(hsn.length, 1);
    expect(hsn.first.hsn, '3209');
    expect(hsn.first.qty, 3);

    final gstr3b = await reports.gstr3b(now, now);
    expect(gstr3b.outwardTaxable, 3000);
    expect(gstr3b.outputTax, 540);
  });

  test('the day book totals the counter correctly', () async {
    final p = await makeProduct(stock: 100);
    final c = await makeCustomer();
    await sales.save(billFor(p, c, qty: 1, paid: 1180));
    await sales.save(billFor(p, c, qty: 1, paid: 0));

    final day = await reports.dayBook(DateTime.now());
    expect(day.bills, 2);
    expect(day.salesTotal, 2360);
    expect(day.collected, 1180);
    expect(day.creditGiven, 1180);
    expect(day.collectionByMode['CASH'], 1180);
  });

  test('recalculating balances agrees with the vouchers', () async {
    final p = await makeProduct(stock: 100);
    final c = await makeCustomer();
    await sales.save(billFor(p, c, qty: 3, paid: 1000));

    final before = (await parties.byId(c.id))!.balance;
    final fixedCount = await parties.recalculateBalances();
    final after = (await parties.byId(c.id))!.balance;

    expect(fixedCount, 0, reason: 'running balances were already correct');
    expect(after, before);
  });

  test('a parked bill survives a round trip', () async {
    final p = await makeProduct();
    final c = await makeCustomer();
    final doc = billFor(p, c, qty: 3);
    TaxEngine.computeDoc(doc);

    final heldId = await sales.hold(doc, 'Counter 1');
    final list = await sales.heldBills();
    expect(list.length, 1);
    expect(list.first.total, doc.total);

    final recalled = await sales.recallHeld(heldId);
    expect(recalled, isNotNull);
    expect(recalled!.id, isNull, reason: 'must save as a new bill');
    expect(recalled.items.length, 1);
    expect(recalled.items.first.qty, 3);
    expect((await sales.heldBills()).isEmpty, isTrue);
  });
}
