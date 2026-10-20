import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/tax.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/product_repo.dart';
import '../../data/repos/purchase_repo.dart';
import '../../state/app_state.dart';
import '../parties/party_picker.dart';
import '../products/product_editor.dart';
import '../widgets/common.dart';

/// Enter a supplier bill: brings stock in, updates cost prices and posts to
/// the supplier ledger.
class PurchaseEditor extends StatefulWidget {
  const PurchaseEditor({super.key, this.existing, this.isReturn = false});

  final PurchaseDoc? existing;
  final bool isReturn;

  static Future<bool> show(BuildContext context,
          {PurchaseDoc? existing, bool isReturn = false}) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PurchaseEditor(existing: existing, isReturn: isReturn),
      ) ??
      false;

  @override
  State<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<PurchaseEditor> {
  final _repo = PurchaseRepo();
  final _products = ProductRepo();

  final _billNo = TextEditingController();
  final _notes = TextEditingController();
  final _paid = TextEditingController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  late PurchaseDoc _doc;
  List<Product> _results = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _doc = widget.existing ??
        PurchaseDoc(
          docType: widget.isReturn ? 'PURCHASE_RETURN' : 'PURCHASE',
          docDate: DateTime.now(),
          billDate: DateTime.now(),
        );
    _billNo.text = _doc.supplierBillNo;
    _notes.text = _doc.notes;
    _paid.text = _doc.paid == 0 ? '' : Fmt.qty(_doc.paid);
  }

  @override
  void dispose() {
    _billNo.dispose();
    _notes.dispose();
    _paid.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _pickSupplier() async {
    final p = await PartyPicker.show(context, kind: 'SUPPLIER');
    if (p == null) return;
    setState(() {
      _doc.partyId = p.id;
      _doc.partyName = p.name;
      _doc.partyGstin = p.gstin;
      _doc.placeOfSupply = p.stateCode;
      _doc.isIgst = TaxEngine.interState(
          context.read<AppState>().company.stateCode, p.stateCode);
    });
    _recalc();
  }

  Future<void> _search1(String value) async {
    if (value.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final rows = await _products.all(query: value, limit: 20);
    if (!mounted) return;
    setState(() => _results = rows);
  }

  void _addProduct(Product p) {
    setState(() {
      _doc.items.add(PurchaseItem(
        productId: p.id,
        name: p.fullName,
        hsn: p.hsn,
        packSize: p.packSize,
        unit: p.unit,
        qty: 1,
        rate: p.purchasePrice,
        mrp: p.mrp,
        salePrice: p.retailPrice,
        gstRate: p.gstRate,
      ));
      _results = const [];
      _search.clear();
    });
    _recalc();
    _searchFocus.requestFocus();
  }

  void _recalc() {
    var taxable = 0.0, cgst = 0.0, sgst = 0.0, igst = 0.0;
    for (final it in _doc.items) {
      final gross = Fmt.round(it.qty * it.rate);
      final disc = it.discountPct > 0
          ? Fmt.round(gross * it.discountPct / 100)
          : it.discountAmt;
      it.discountAmt = disc;
      it.taxable = Fmt.round(gross - disc);
      if (_doc.isIgst) {
        it.igst = Fmt.round(it.taxable * it.gstRate / 100);
        it.cgst = it.sgst = 0;
      } else {
        final half = Fmt.round(it.taxable * it.gstRate / 200);
        it.cgst = half;
        it.sgst = half;
        it.igst = 0;
      }
      it.total = Fmt.round(it.taxable + it.cgst + it.sgst + it.igst);
      taxable += it.taxable;
      cgst += it.cgst;
      sgst += it.sgst;
      igst += it.igst;
    }
    _doc.taxableAmount = Fmt.round(taxable);
    _doc.cgst = Fmt.round(cgst);
    _doc.sgst = Fmt.round(sgst);
    _doc.igst = Fmt.round(igst);
    final before = Fmt.round(
        _doc.taxableAmount + _doc.cgst + _doc.sgst + _doc.igst + _doc.freight);
    final (rounded, delta) = Fmt.roundOff(before);
    _doc.roundOff = delta;
    _doc.total = rounded;
    setState(() {});
  }

  Future<void> _save() async {
    if (_doc.partyId == null) {
      toast(context, 'Choose the supplier first.', error: true);
      return;
    }
    if (_doc.items.isEmpty) {
      toast(context, 'Add at least one item.', error: true);
      return;
    }
    setState(() => _busy = true);
    _doc.supplierBillNo = _billNo.text.trim();
    _doc.notes = _notes.text.trim();
    _doc.paid = Fmt.toDouble(_paid.text);
    try {
      final saved = await _repo.save(_doc, user: context.read<AppState>().user);
      if (!mounted) return;
      toast(context, 'Purchase ${saved.docNo} saved. Stock updated.',
          success: true);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'Could not save: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 720),
        child: BusyOverlay(
          busy: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                icon: Icons.local_shipping_rounded,
                title: widget.isReturn
                    ? 'Purchase return (debit note)'
                    : 'Purchase bill entry',
                subtitle:
                    'Stock comes in and the supplier ledger is updated on save',
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _pickSupplier,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppTheme.borderOf(context)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.store_rounded, size: 17),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        _doc.partyName.isEmpty
                                            ? 'Select supplier *'
                                            : _doc.partyName,
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                      _doc.partyGstin.isEmpty
                                          ? 'Unregistered / not set'
                                          : '${_doc.partyGstin}  ·  '
                                              '${_doc.isIgst ? 'IGST' : 'CGST+SGST'}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child:
                          Field(label: 'Supplier bill no', controller: _billNo),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: context,
                          initialDate: _doc.docDate,
                          firstDate: DateTime(2015),
                          lastDate: DateTime.now(),
                        );
                        if (d != null) setState(() => _doc.docDate = d);
                      },
                      icon: const Icon(Icons.event_rounded, size: 16),
                      label: Text(Fmt.date(_doc.docDate)),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Field(
                        label: 'Add item — search by name or code',
                        controller: _search,
                        focusNode: _searchFocus,
                        prefix: const Icon(Icons.search_rounded, size: 18),
                        onChanged: _search1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final p = await ProductEditor.show(context);
                        if (p != null) _addProduct(p);
                      },
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('New item'),
                    ),
                  ],
                ),
              ),
              if (_results.isNotEmpty)
                Container(
                  height: 140,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.borderOf(context)),
                  ),
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemExtent: 40,
                    itemBuilder: (context, i) {
                      final p = _results[i];
                      return ListTile(
                        dense: true,
                        title: Text(p.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                        trailing: Text(
                            'Stock ${Fmt.qty(p.stock)} · Cost ${Fmt.amount(p.purchasePrice)}',
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => _addProduct(p),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              Expanded(
                child: _doc.items.isEmpty
                    ? const EmptyState(
                        title: 'No items on this bill yet',
                        message: 'Search above to add what the supplier sent.',
                        icon: Icons.inventory_2_rounded,
                      )
                    : ListView.builder(
                        itemCount: _doc.items.length,
                        itemBuilder: (context, i) => _PurchaseItemRow(
                          key: ObjectKey(_doc.items[i]),
                          index: i,
                          item: _doc.items[i],
                          onChanged: _recalc,
                          onRemove: () {
                            setState(() => _doc.items.removeAt(i));
                            _recalc();
                          },
                        ),
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Field(label: 'Notes', controller: _notes),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 150,
                      child: Field(
                        label: 'Amount paid now',
                        controller: _paid,
                        inputFormatters: Field.decimal,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _sum('Taxable', _doc.taxableAmount),
                        if (_doc.isIgst)
                          _sum('IGST', _doc.igst)
                        else ...[
                          _sum('CGST', _doc.cgst),
                          _sum('SGST', _doc.sgst),
                        ],
                        if (_doc.roundOff != 0)
                          _sum('Round off', _doc.roundOff),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('TOTAL  ',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800)),
                            Money(_doc.total, size: 20, bold: true),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 18),
                    Column(
                      children: [
                        SizedBox(
                          width: 150,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Save bill'),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: 150,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sum(String k, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 84,
              child: Text(k,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 100, child: Money(v, size: 12.5, symbol: false)),
          ],
        ),
      );
}

/// One editable purchase line. Controllers live with the row so a
/// recalculation never rebuilds the field out from under the typist.
class _PurchaseItemRow extends StatefulWidget {
  const _PurchaseItemRow({
    super.key,
    required this.index,
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final PurchaseItem item;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_PurchaseItemRow> createState() => _PurchaseItemRowState();
}

class _PurchaseItemRowState extends State<_PurchaseItemRow> {
  late final Map<String, TextEditingController> _c = {
    'qty': TextEditingController(text: Fmt.qty(widget.item.qty)),
    'free': TextEditingController(
        text: widget.item.freeQty == 0 ? '' : Fmt.qty(widget.item.freeQty)),
    'rate': TextEditingController(
        text: widget.item.rate == 0 ? '' : Fmt.qty(widget.item.rate)),
    'disc': TextEditingController(
        text: widget.item.discountPct == 0
            ? ''
            : Fmt.qty(widget.item.discountPct)),
    'mrp': TextEditingController(
        text: widget.item.mrp == 0 ? '' : Fmt.qty(widget.item.mrp)),
    'sale': TextEditingController(
        text: widget.item.salePrice == 0 ? '' : Fmt.qty(widget.item.salePrice)),
  };

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return Container(
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: AppTheme.borderOf(context), width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 26, child: Text('${widget.index + 1}')),
          Expanded(
            child: Text(it.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          _num('Qty', _c['qty']!, (v) => it.qty = v),
          _num('Free', _c['free']!, (v) => it.freeQty = v),
          _num('Rate', _c['rate']!, (v) => it.rate = v),
          _num('Disc %', _c['disc']!, (v) {
            it.discountPct = v;
            it.discountAmt = 0;
          }),
          _num('MRP', _c['mrp']!, (v) => it.mrp = v),
          _num('Sale', _c['sale']!, (v) => it.salePrice = v),
          SizedBox(
            width: 62,
            child: Text('${Fmt.qty(it.gstRate)}%',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12)),
          ),
          SizedBox(width: 96, child: Money(it.total, size: 13, bold: true)),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppTheme.danger,
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
  }

  Widget _num(String label, TextEditingController controller,
      ValueChanged<double> apply) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: SizedBox(
        width: 78,
        child: TextField(
          controller: controller,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 12.5),
          inputFormatters: Field.decimal,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(fontSize: 10),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          ),
          onChanged: (v) {
            apply(Fmt.toDouble(v));
            widget.onChanged();
          },
        ),
      ),
    );
  }
}
