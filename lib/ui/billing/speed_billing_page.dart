import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/product_repo.dart';
import '../../print/print_service.dart';
import '../../state/app_state.dart';
import '../../state/billing_state.dart';
import '../parties/party_picker.dart';
import '../products/product_editor.dart';
import '../widgets/common.dart';
import 'billing_dialogs.dart';
import 'cart_row.dart';

/// The counter screen. Everything here is reachable without the mouse.
///
/// Search box → type / scan → Enter adds the line. Qty, rate and discount are
/// editable inline. F9 saves and prints. The whole flow is one hand on the
/// keyboard, which is what makes it fast.
class SpeedBillingPage extends StatefulWidget {
  const SpeedBillingPage({super.key});

  @override
  State<SpeedBillingPage> createState() => _SpeedBillingPageState();
}

class _SpeedBillingPageState extends State<SpeedBillingPage> {
  final _products = ProductRepo();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _cartScroll = ScrollController();

  Timer? _debounce;
  List<Product> _results = const [];
  int _highlight = 0;
  bool _searching = false;
  bool _started = false;

  BillingState get _bill => context.read<BillingState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_started) return;
    _started = true;
    await _bill.startNew();
    if (!mounted) return;
    _focusSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _cartScroll.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocus.requestFocus();
    _search.selection =
        TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  // ------------------------------------------------------------------
  // Search
  // ------------------------------------------------------------------
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _highlight = 0;
      });
      return;
    }
    // 120 ms is below the threshold where typing feels laggy, and it keeps a
    // 10 000-item catalogue from being queried on every keystroke.
    _debounce =
        Timer(const Duration(milliseconds: 120), () => _runSearch(value));
  }

  Future<void> _runSearch(String value) async {
    final (_, term) = _splitQty(value);
    if (term.isEmpty) return;
    setState(() => _searching = true);
    final rows = await _products.all(query: term, limit: 40);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _highlight = 0;
      _searching = false;
    });
  }

  /// Accepts `3*8901234`, `3x1 ltr emulsion` or a plain search term.
  (double, String) _splitQty(String raw) {
    final text = raw.trim();
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*[*xX]\s*(.+)$').firstMatch(text);
    if (m != null) {
      return (double.tryParse(m.group(1)!) ?? 1, m.group(2)!.trim());
    }
    return (1, text);
  }

  Future<void> _submitSearch() async {
    final raw = _search.text;
    if (raw.trim().isEmpty) return;
    final (qty, term) = _splitQty(raw);

    // A barcode scanner types the code then presses Enter — match it exactly
    // first so scanning never depends on the debounce having finished.
    final exact = await _products.byCode(term);
    if (exact != null) {
      _add(exact, qty);
      return;
    }
    if (_results.isNotEmpty) {
      _add(_results[_highlight], qty);
      return;
    }
    final rows = await _products.all(query: term, limit: 40);
    if (!mounted) return;
    if (rows.length == 1) {
      _add(rows.first, qty);
    } else if (rows.isEmpty) {
      _offerToCreate(term);
    } else {
      setState(() {
        _results = rows;
        _highlight = 0;
      });
    }
  }

  void _add(Product p, double qty) {
    if (!p.isService &&
        p.stock <= 0 &&
        !context.read<AppState>().allowNegativeStock) {
      toast(context, '${p.fullName} is out of stock.', error: true);
      return;
    }
    _bill.addProduct(p, qty: qty);
    _search.clear();
    setState(() {
      _results = const [];
      _highlight = 0;
    });
    _focusSearch();
    _scrollCartToEnd();
  }

  void _scrollCartToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_cartScroll.hasClients) return;
      _cartScroll.animateTo(
        _cartScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _offerToCreate(String term) async {
    final ok = await confirm(
      context,
      title: 'Item not found',
      message: '"$term" is not in your catalogue. Add it now?',
      confirmLabel: 'Add item',
    );
    if (!ok || !mounted) return;
    final created = await ProductEditor.show(context, seedName: term);
    if (created != null && mounted) _add(created, 1);
  }

  void _moveHighlight(int delta) {
    if (_results.isEmpty) return;
    setState(
        () => _highlight = (_highlight + delta).clamp(0, _results.length - 1));
  }

  // ------------------------------------------------------------------
  // Commands
  // ------------------------------------------------------------------
  Future<void> _pickCustomer() async {
    final p = await PartyPicker.show(context);
    if (p != null) await _bill.setCustomer(p);
    if (mounted) _focusSearch();
  }

  Future<void> _hold() async {
    if (_bill.isEmpty) return;
    final label = _bill.customer?.name ?? 'Counter';
    await _bill.hold('$label · ${Fmt.time(DateTime.now())}');
    await _bill.startNew();
    if (!mounted) return;
    toast(context, 'Bill parked. Press F5 to bring it back.', success: true);
    _focusSearch();
  }

  Future<void> _recall() async {
    final id = await HeldBillsDialog.show(context);
    if (id == null) return;
    await _bill.recall(id);
    if (mounted) _focusSearch();
  }

  Future<void> _clear() async {
    if (_bill.isEmpty) return;
    final ok = await confirm(
      context,
      title: 'Clear this bill?',
      message: 'All ${_bill.lineCount} lines will be removed.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (ok) {
      _bill.clear();
      if (mounted) _focusSearch();
    }
  }

  Future<void> _save({required bool print}) async {
    final bill = _bill;
    if (bill.isEmpty) {
      toast(context, 'Add at least one item first.', error: true);
      return;
    }
    final app = context.read<AppState>();

    // Credit sales need a real customer to bill it to.
    if (bill.doc.paymentMode == PaymentModes.credit &&
        (bill.doc.partyId == null || bill.doc.partyId == 1)) {
      toast(context, 'Select a customer before making a credit sale.',
          error: true);
      await _pickCustomer();
      return;
    }

    final saved = await bill.save();
    if (!mounted) return;
    if (saved == null) {
      toast(context, bill.error ?? 'Could not save the bill.', error: true);
      return;
    }

    toast(context, '${saved.docNo} saved · ${Fmt.money(saved.total)}',
        success: true);
    await app.refreshAlerts();

    if (print && mounted) {
      await PrintService.printInvoice(context, app, saved);
    }
    if (!mounted) return;
    await bill.startNew();
    if (mounted) _focusSearch();
  }

  Future<void> _preview() async {
    if (_bill.isEmpty) return;
    final app = context.read<AppState>();
    // Preview a copy: writing the peeked number onto the live bill would
    // make SalesRepo treat it as already numbered and never advance the
    // counter, so every later bill would reuse it.
    final preview = SalesDoc.fromMap(_bill.doc.toMap())
      ..items = _bill.doc.items;
    if (preview.docNo.isEmpty) preview.docNo = _bill.nextNo;
    await PrintService.previewInvoice(context, app, preview);
    if (mounted) _focusSearch();
  }

  Future<void> _payment() async {
    if (_bill.isEmpty) return;
    final confirmed = await PaymentDialog.show(context, _bill);
    if (confirmed && mounted) await _save(print: true);
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final bill = context.watch<BillingState>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.f3): _pickCustomer,
        const SingleActivator(LogicalKeyboardKey.f4): _hold,
        const SingleActivator(LogicalKeyboardKey.f5): _recall,
        const SingleActivator(LogicalKeyboardKey.f6): () =>
            BillDiscountDialog.show(context, bill),
        const SingleActivator(LogicalKeyboardKey.f7): () =>
            CustomLineDialog.show(context, bill,
                defaultGst: context.read<AppState>().defaultGst),
        const SingleActivator(LogicalKeyboardKey.f8): _payment,
        const SingleActivator(LogicalKeyboardKey.f9): () => _save(print: true),
        const SingleActivator(LogicalKeyboardKey.f10): () =>
            _save(print: false),
        const SingleActivator(LogicalKeyboardKey.f12): _preview,
        const SingleActivator(LogicalKeyboardKey.escape): _clear,
        const SingleActivator(LogicalKeyboardKey.delete, control: true): () =>
            bill.removeAt(bill.selectedIndex),
      },
      child: Focus(
        child: BusyOverlay(
          busy: bill.busy,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _left(bill)),
              Container(width: 1, color: AppTheme.borderOf(context)),
              SizedBox(
                  width: 330,
                  child: _TotalsPanel(
                    bill: bill,
                    onPayment: _payment,
                    onSavePrint: () => _save(print: true),
                    onSave: () => _save(print: false),
                    onPreview: _preview,
                    onDiscount: () => BillDiscountDialog.show(context, bill),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _left(BillingState bill) {
    return Column(
      children: [
        _customerBar(bill),
        const Divider(height: 1),
        _searchBar(),
        if (_results.isNotEmpty) _resultsList(),
        const Divider(height: 1),
        Expanded(
          child: bill.isEmpty
              ? const EmptyState(
                  title: 'Start scanning or type an item name',
                  message:
                      'Tip: type 3*4LTR to add three units at once, or scan a '
                      'barcode. F3 picks the customer, F9 saves and prints.',
                  icon: Icons.qr_code_scanner_rounded,
                )
              : MinWidthScroller(
                  minWidth: CartCols.minTableWidth,
                  child: Column(
                    children: [
                      CartHeader(showTax: !bill.doc.priceIncludesTax),
                      const Divider(height: 1),
                      Expanded(
                        child: Scrollbar(
                          controller: _cartScroll,
                          child: ListView.builder(
                            controller: _cartScroll,
                            itemCount: bill.items.length,
                            itemBuilder: (context, i) {
                              final item = bill.items[i];
                              return CartRow(
                                key: ObjectKey(item),
                                index: i,
                                item: item,
                                selected: bill.selectedIndex == i,
                                showTax: !bill.doc.priceIncludesTax,
                                onSelect: () => bill.select(i),
                                onQty: (v) => bill.setQty(i, v),
                                onRate: (v) => bill.setRate(i, v),
                                onDiscount: (v) => bill.setDiscountPct(i, v),
                                onRemove: () => bill.removeAt(i),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const Divider(height: 1),
        _shortcutBar(bill),
      ],
    );
  }

  // ---- Customer / document strip -------------------------------------
  Widget _customerBar(BillingState bill) {
    final app = context.watch<AppState>();
    final c = bill.customer;
    final doc = bill.doc;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 330,
            child: InkWell(
              onTap: _pickCustomer,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderOf(context)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_rounded,
                        size: 17, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c?.name ?? 'Cash / Walk-in Customer',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            [
                              if ((c?.phone ?? '').isNotEmpty) c!.phone,
                              if ((c?.gstin ?? '').isNotEmpty) c!.gstin,
                              if ((c?.balance ?? 0).abs() > 0.5)
                                'Due ${Fmt.money(c!.balance)}',
                            ].join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const KeyHint('F3'),
                  ],
                ),
              ),
            ),
          ),
          _chipInfo('Bill No', bill.nextNo.isEmpty ? '—' : bill.nextNo,
              Icons.tag_rounded),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: doc.docDate,
                firstDate: DateTime(2015),
                lastDate: DateTime.now().add(const Duration(days: 1)),
              );
              if (picked != null) bill.setDate(picked);
            },
            borderRadius: BorderRadius.circular(8),
            child:
                _chipInfo('Date', Fmt.date(doc.docDate), Icons.event_rounded),
          ),
          _chipInfo(
            doc.isIgst ? 'IGST' : 'CGST+SGST',
            '${IndianStates.name(doc.placeOfSupply).split(' ').first} '
            '(${doc.placeOfSupply.isEmpty ? '--' : doc.placeOfSupply})',
            Icons.account_balance_rounded,
            tint: doc.isIgst ? AppTheme.warning : null,
          ),
          Tooltip(
            message: doc.priceIncludesTax
                ? 'Rates you type include GST (MRP billing)'
                : 'Rates you type are before GST',
            child: FilterChip(
              selected: doc.priceIncludesTax,
              onSelected: bill.setPriceIncludesTax,
              avatar: const Icon(Icons.percent_rounded, size: 14),
              label: const Text('Incl. tax'),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Document type',
            initialValue: doc.docType,
            onSelected: bill.setDocType,
            itemBuilder: (_) => [
              for (final t in const [
                DocType.invoice,
                DocType.estimate,
                DocType.challan,
              ])
                PopupMenuItem(value: t, child: Text(DocType.label[t]!)),
            ],
            child: _chipInfo(
                'Type',
                DocType.label[doc.docType]!.split(' ').first,
                Icons.description_rounded),
          ),
          if (app.lowStockCount > 0)
            StatusPill('${app.lowStockCount} low',
                color: AppTheme.warning, icon: Icons.warning_amber_rounded),
        ],
      ),
    );
  }

  Widget _chipInfo(String label, String value, IconData icon, {Color? tint}) {
    final color = tint ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Search --------------------------------------------------------
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _moveHighlight(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _moveHighlight(-1),
              },
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                autofocus: true,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText:
                      'Scan barcode or type item name / code / shade   —   3*code adds three',
                  hintStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.normal),
                  prefixIcon:
                      const Icon(Icons.qr_code_scanner_rounded, size: 20),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (_search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() => _results = const []);
                                _focusSearch();
                              },
                            )),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _submitSearch(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () => CustomLineDialog.show(context, _bill,
                defaultGst: context.read<AppState>().defaultGst),
            icon: const Icon(Icons.playlist_add_rounded, size: 17),
            label: const Text('Charge  F7'),
          ),
        ],
      ),
    );
  }

  Widget _resultsList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1B2027)
            : Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.borderOf(context)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _results.length,
        itemExtent: 46,
        itemBuilder: (context, i) {
          final p = _results[i];
          final selected = i == _highlight;
          final out = !p.isService && p.stock <= 0;
          return InkWell(
            onTap: () => _add(p, _splitQty(_search.text).$1),
            child: Container(
              color: selected
                  ? Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.10)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 26,
                    decoration: BoxDecoration(
                      color: out
                          ? AppTheme.danger
                          : (p.lowStock ? AppTheme.warning : AppTheme.success),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(
                          [
                            p.sku,
                            if (p.shadeCode.isNotEmpty) p.shadeCode,
                            if (p.rack.isNotEmpty) 'Rack ${p.rack}',
                            'HSN ${p.hsn}',
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      out
                          ? 'Out of stock'
                          : '${Fmt.qty(p.stock)} ${p.unit} left',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: out
                            ? AppTheme.danger
                            : (p.lowStock ? AppTheme.warning : null),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 92,
                    child: Money(
                      p.priceFor(_bill.doc.priceTier),
                      size: 13.5,
                      bold: true,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- Footer --------------------------------------------------------
  Widget _shortcutBar(BillingState bill) {
    return Container(
      height: 38,
      color: AppTheme.subtleOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Text('${bill.lineCount} items  ·  ${Fmt.qty(bill.totalQty)} qty',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (bill.savings > 0) ...[
            const SizedBox(width: 14),
            Text('Saved ${Fmt.money(bill.savings)}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success)),
          ],
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(children: [
                for (final s in const [
                  ('F3', 'Customer'),
                  ('F4', 'Park'),
                  ('F5', 'Recall'),
                  ('F6', 'Discount'),
                  ('F7', 'Charge'),
                  ('F8', 'Payment'),
                  ('F9', 'Save+Print'),
                  ('F12', 'Preview'),
                  ('Esc', 'Clear'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KeyHint(s.$1),
                        const SizedBox(width: 4),
                        Text(s.$2,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            )),
                      ],
                    ),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Right-hand totals panel
// ---------------------------------------------------------------------------
class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({
    required this.bill,
    required this.onPayment,
    required this.onSavePrint,
    required this.onSave,
    required this.onPreview,
    required this.onDiscount,
  });

  final BillingState bill;
  final VoidCallback onPayment;
  final VoidCallback onSavePrint;
  final VoidCallback onSave;
  final VoidCallback onPreview;
  final VoidCallback onDiscount;

  @override
  Widget build(BuildContext context) {
    final doc = bill.doc;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1B2027)
          : Colors.white,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _line(context, 'Gross value', doc.grossAmount),
                  if (doc.itemDiscount > 0)
                    _line(context, 'Item discount', -doc.itemDiscount,
                        color: AppTheme.success),
                  if (doc.docDiscountAmt > 0)
                    _line(context, 'Bill discount', -doc.docDiscountAmt,
                        color: AppTheme.success),
                  const Divider(height: 18),
                  _line(context, 'Taxable value', doc.taxableAmount),
                  if (doc.isIgst)
                    _line(context, 'IGST', doc.igst)
                  else ...[
                    _line(context, 'CGST', doc.cgst),
                    _line(context, 'SGST', doc.sgst),
                  ],
                  if (doc.cess > 0) _line(context, 'Cess', doc.cess),
                  if (doc.freight > 0) _line(context, 'Freight', doc.freight),
                  if (doc.otherCharges > 0)
                    _line(context, 'Other charges', doc.otherCharges),
                  if (doc.roundOff != 0)
                    _line(context, 'Round off', doc.roundOff),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GRAND TOTAL',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                              color: scheme.onPrimary.withValues(alpha: 0.8),
                            )),
                        const SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            Fmt.money(doc.total),
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: scheme.onPrimary,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          NumberToWords.rupees(doc.total),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onPrimary.withValues(alpha: 0.85),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onDiscount,
                          icon: const Icon(Icons.percent_rounded, size: 16),
                          label: const Text('Discount'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPreview,
                          icon: const Icon(Icons.visibility_rounded, size: 16),
                          label: const Text('Preview'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('PAYMENT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: scheme.onSurfaceVariant,
                      )),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in PaymentModes.all)
                        ChoiceChip(
                          selected: doc.paymentMode == m,
                          onSelected: (_) => bill.setPaymentMode(m),
                          label: Text(m, style: const TextStyle(fontSize: 11)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 0),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _miniStat(
                            context, 'Paid', doc.paid, AppTheme.success),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _miniStat(
                            context,
                            'Balance',
                            doc.balance,
                            doc.balance > 0.5
                                ? AppTheme.danger
                                : scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                SizedBox(
                  height: 50,
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: bill.isEmpty ? null : onSavePrint,
                    icon: const Icon(Icons.print_rounded, size: 20),
                    label: const Text('SAVE & PRINT   F9',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: bill.isEmpty ? null : onPayment,
                        icon: const Icon(Icons.payments_rounded, size: 16),
                        label: const Text('Payment  F8'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: bill.isEmpty ? null : onSave,
                        icon: const Icon(Icons.save_rounded, size: 16),
                        label: const Text('Save  F10'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, double value,
      {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 12.5,
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              )),
          Money(value, size: 13, color: color, symbol: false),
        ],
      ),
    );
  }

  Widget _miniStat(
      BuildContext context, String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
          Money(value, size: 14, bold: true, color: color, symbol: false),
        ],
      ),
    );
  }
}
