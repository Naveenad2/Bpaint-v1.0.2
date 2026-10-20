import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/tax.dart';
import '../data/models.dart';
import '../data/repos/party_repo.dart';
import '../data/repos/product_repo.dart';
import '../data/repos/sales_repo.dart';
import '../data/repos/settings_repo.dart';
import 'app_state.dart';

/// The live bill being typed at the counter.
///
/// Holds one [SalesDoc] and keeps every total recomputed after each keystroke.
/// Nothing here touches the database until [save] is called.
class BillingState extends ChangeNotifier {
  BillingState(this.app);

  final AppState app;
  final SalesRepo _sales = SalesRepo();
  final ProductRepo _products = ProductRepo();
  final PartyRepo _parties = PartyRepo();
  final SettingsRepo _settings = SettingsRepo();

  SalesDoc doc = SalesDoc();
  Party? customer;
  String nextNo = '';
  int selectedIndex = -1;
  bool busy = false;
  String? error;

  List<SalesItem> get items => doc.items;
  bool get isEmpty => doc.items.isEmpty;
  bool get isEditing => doc.id != null;
  int get lineCount => doc.items.length;
  double get totalQty => doc.items.fold<double>(0.0, (s, e) => s + e.qty);
  double get savings => Fmt.round(doc.itemDiscount + doc.docDiscountAmt);

  /// Cash tendered by the customer; drives the change-due display.
  double tendered = 0;
  double get changeDue => tendered <= 0
      ? 0
      : Fmt.round((tendered - doc.total).clamp(0, 1e9).toDouble());

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------
  Future<void> startNew({String docType = DocType.invoice}) async {
    doc = SalesDoc(
      docType: docType,
      docDate: DateTime.now(),
      priceIncludesTax: app.priceIncludesTax,
      paymentMode: PaymentModes.cash,
      userId: app.user?.id,
      userName: app.user?.name ?? '',
    );
    tendered = 0;
    selectedIndex = -1;
    error = null;
    customer = await _parties.byId(1);
    _applyCustomer(customer);
    nextNo = await _settings.peekDocNo(docType);
    _recompute();
  }

  Future<void> loadForEdit(SalesDoc existing) async {
    doc = existing;
    customer = await _parties.byId(existing.partyId);
    nextNo = existing.docNo;
    tendered = 0;
    selectedIndex = -1;
    error = null;
    _recompute();
  }

  Future<void> setDocType(String type) async {
    doc.docType = type;
    nextNo = await _settings.peekDocNo(type);
    _recompute();
  }

  // ------------------------------------------------------------------
  // Customer
  // ------------------------------------------------------------------
  Future<void> setCustomer(Party? party) async {
    customer = party ?? await _parties.byId(1);
    _applyCustomer(customer);
    // Switching between a dealer and a retail buyer re-prices the whole bill.
    for (final it in doc.items) {
      if (it.productId == null) continue;
      final p = await _products.byId(it.productId);
      if (p != null) it.grossRate = p.priceFor(doc.priceTier);
    }
    _recompute();
  }

  void _applyCustomer(Party? party) {
    if (party == null) return;
    doc.partyId = party.id;
    doc.partyName = party.name;
    doc.partyPhone = party.phone;
    doc.partyGstin = party.gstin;
    doc.partyAddress = party.addressLine;
    doc.priceTier = party.priceTier;
    doc.placeOfSupply =
        party.stateCode.isNotEmpty ? party.stateCode : app.company.stateCode;
    doc.isIgst = TaxEngine.interState(app.company.stateCode, doc.placeOfSupply);
    if (party.creditDays > 0) {
      doc.dueDate = doc.docDate.add(Duration(days: party.creditDays));
    }
  }

  void setPlaceOfSupply(String stateCode) {
    doc.placeOfSupply = stateCode;
    doc.isIgst = TaxEngine.interState(app.company.stateCode, stateCode);
    _recompute();
  }

  // ------------------------------------------------------------------
  // Lines
  // ------------------------------------------------------------------
  /// Adds a product; if the same product+rate is already on the bill the
  /// quantity is merged instead of creating a duplicate line.
  void addProduct(Product product, {double qty = 1}) {
    final existing = doc.items.indexWhere((e) =>
        e.productId == product.id &&
        e.grossRate == product.priceFor(doc.priceTier) &&
        e.discountPct == 0);
    if (existing >= 0) {
      doc.items[existing].qty = Fmt.round(doc.items[existing].qty + qty, 3);
      selectedIndex = existing;
    } else {
      doc.items.add(TaxEngine.lineFromProduct(
        product,
        qty: qty,
        tier: doc.priceTier,
        priceIncludesTax: doc.priceIncludesTax,
        isIgst: doc.isIgst,
      ));
      selectedIndex = doc.items.length - 1;
    }
    _recompute();
  }

  /// Adds a free-text line — tinting charges, labour, or an unlisted item.
  void addCustomLine({
    required String name,
    required double qty,
    required double rate,
    double gstRate = 18,
    String unit = 'NOS',
    String hsn = '',
  }) {
    doc.items.add(SalesItem(
      name: name,
      qty: qty,
      grossRate: rate,
      gstRate: gstRate,
      unit: unit,
      hsn: hsn,
    ));
    selectedIndex = doc.items.length - 1;
    _recompute();
  }

  void removeAt(int index) {
    if (index < 0 || index >= doc.items.length) return;
    doc.items.removeAt(index);
    if (selectedIndex >= doc.items.length) {
      selectedIndex = doc.items.length - 1;
    }
    _recompute();
  }

  void setQty(int index, double qty) {
    if (index < 0 || index >= doc.items.length) return;
    if (qty <= 0) {
      removeAt(index);
      return;
    }
    doc.items[index].qty = Fmt.round(qty, 3);
    _recompute();
  }

  void bumpQty(int index, double delta) {
    if (index < 0 || index >= doc.items.length) return;
    setQty(index, doc.items[index].qty + delta);
  }

  void setRate(int index, double rate) {
    if (index < 0 || index >= doc.items.length) return;
    doc.items[index].grossRate = Fmt.round(rate, 2);
    _recompute();
  }

  void setDiscountPct(int index, double pct) {
    if (index < 0 || index >= doc.items.length) return;
    doc.items[index].discountPct = pct.clamp(0, 100).toDouble();
    doc.items[index].discountAmt = 0;
    _recompute();
  }

  void setLineDiscountAmount(int index, double amount) {
    if (index < 0 || index >= doc.items.length) return;
    doc.items[index].discountPct = 0;
    doc.items[index].discountAmt = Fmt.round(amount);
    _recompute();
  }

  void setFreeQty(int index, double qty) {
    if (index < 0 || index >= doc.items.length) return;
    doc.items[index].freeQty = Fmt.round(qty, 3);
    _recompute();
  }

  void select(int index) {
    selectedIndex = index.clamp(-1, doc.items.length - 1);
    notifyListeners();
  }

  void moveSelection(int delta) {
    if (doc.items.isEmpty) return;
    final next = (selectedIndex + delta).clamp(0, doc.items.length - 1);
    selectedIndex = next;
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Bill-level fields
  // ------------------------------------------------------------------
  void setBillDiscountPct(double pct) {
    doc.docDiscountPct = pct.clamp(0, 100).toDouble();
    doc.docDiscountAmt = 0;
    _recompute();
  }

  void setBillDiscountAmount(double amount) {
    doc.docDiscountPct = 0;
    doc.docDiscountAmt = Fmt.round(amount);
    _recompute();
  }

  void setFreight(double v) {
    doc.freight = Fmt.round(v);
    _recompute();
  }

  void setOtherCharges(double v) {
    doc.otherCharges = Fmt.round(v);
    _recompute();
  }

  void setPaymentMode(String mode) {
    doc.paymentMode = mode;
    // A credit sale collects nothing at the counter.
    doc.paid = mode == PaymentModes.credit ? 0 : doc.total;
    _recompute();
  }

  void setPaid(double amount) {
    doc.paid = Fmt.round(amount.clamp(0, double.maxFinite).toDouble());
    _recompute();
  }

  void setTendered(double amount) {
    tendered = Fmt.round(amount);
    notifyListeners();
  }

  void payInFull() {
    doc.paid = doc.total;
    _recompute();
  }

  void setPriceIncludesTax(bool value) {
    doc.priceIncludesTax = value;
    _recompute();
  }

  void setDate(DateTime date) {
    doc.docDate = date;
    _recompute();
  }

  void setNotes(String notes) {
    doc.notes = notes;
  }

  void _recompute() {
    TaxEngine.computeDoc(doc, applyRoundOff: app.roundOffEnabled);
    if (doc.paymentMode != PaymentModes.credit &&
        doc.paid > 0 &&
        doc.paid > doc.total) {
      doc.paid = doc.total;
      TaxEngine.computeDoc(doc, applyRoundOff: app.roundOffEnabled);
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Persistence
  // ------------------------------------------------------------------
  /// Saves the bill and returns the stored document, or null on failure
  /// (in which case [error] carries a message fit for a snackbar).
  Future<SalesDoc?> save() async {
    if (doc.items.isEmpty) {
      error = 'Add at least one item before saving.';
      notifyListeners();
      return null;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (doc.paymentMode == PaymentModes.cash && doc.paid == 0) {
        doc.paid = doc.total;
      }
      final saved = await _sales.save(
        doc,
        user: app.user,
        allowNegativeStock: app.allowNegativeStock,
        roundOff: app.roundOffEnabled,
      );
      return saved;
    } on InsufficientStock catch (e) {
      error = e.message;
      return null;
    } catch (e) {
      error = 'Could not save the bill: $e';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<int> hold(String label) => _sales.hold(doc, label);

  Future<void> recall(int heldId) async {
    final d = await _sales.recallHeld(heldId);
    if (d == null) return;
    doc = d;
    customer = await _parties.byId(d.partyId);
    nextNo = await _settings.peekDocNo(d.docType);
    _recompute();
  }

  void clear() {
    doc.items.clear();
    doc.docDiscountAmt = 0;
    doc.docDiscountPct = 0;
    doc.freight = 0;
    doc.otherCharges = 0;
    doc.paid = 0;
    doc.notes = '';
    tendered = 0;
    selectedIndex = -1;
    _recompute();
  }
}
