import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../widgets/common.dart';

/// Column widths shared by the cart header and its rows so both stay aligned.
class CartCols {
  static const double sn = 36;
  static const double qty = 92;
  static const double unit = 52;
  static const double rate = 96;
  static const double disc = 74;
  static const double gst = 56;
  static const double tax = 88;
  static const double amount = 104;
  static const double action = 40;

  static double get fixed =>
      sn + qty + unit + rate + disc + gst + tax + amount + action;

  /// Fixed columns plus a usable amount of room for the item description.
  static double get minTableWidth => fixed + 240;
}

/// One editable line of the bill.
///
/// Each numeric cell owns a controller that is only re-synced from the model
/// when the cell is not being typed in — so a recalculation elsewhere can
/// never yank the caret out of the operator's hands.
class CartRow extends StatefulWidget {
  const CartRow({
    super.key,
    required this.index,
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onQty,
    required this.onRate,
    required this.onDiscount,
    required this.onRemove,
    this.showTax = true,
  });

  final int index;
  final SalesItem item;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<double> onQty;
  final ValueChanged<double> onRate;
  final ValueChanged<double> onDiscount;
  final VoidCallback onRemove;
  final bool showTax;

  @override
  State<CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<CartRow> {
  late final TextEditingController _qty;
  late final TextEditingController _rate;
  late final TextEditingController _disc;
  final _qtyFocus = FocusNode();
  final _rateFocus = FocusNode();
  final _discFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: Fmt.qty(widget.item.qty));
    _rate = TextEditingController(text: Fmt.qty(widget.item.grossRate));
    _disc = TextEditingController(
        text: widget.item.discountPct == 0
            ? ''
            : Fmt.qty(widget.item.discountPct));
    _qtyFocus.addListener(_commitOnBlur);
    _rateFocus.addListener(_commitOnBlur);
    _discFocus.addListener(_commitOnBlur);
  }

  @override
  void didUpdateWidget(covariant CartRow old) {
    super.didUpdateWidget(old);
    if (!_qtyFocus.hasFocus) _sync(_qty, Fmt.qty(widget.item.qty));
    if (!_rateFocus.hasFocus) _sync(_rate, Fmt.qty(widget.item.grossRate));
    if (!_discFocus.hasFocus) {
      _sync(_disc,
          widget.item.discountPct == 0 ? '' : Fmt.qty(widget.item.discountPct));
    }
  }

  void _sync(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  void _commitOnBlur() {
    if (!_qtyFocus.hasFocus) {
      widget.onQty(Fmt.toDouble(_qty.text, widget.item.qty));
    }
    if (!_rateFocus.hasFocus) {
      widget.onRate(Fmt.toDouble(_rate.text, widget.item.grossRate));
    }
    if (!_discFocus.hasFocus) widget.onDiscount(Fmt.toDouble(_disc.text));
  }

  @override
  void dispose() {
    _qty.dispose();
    _rate.dispose();
    _disc.dispose();
    _qtyFocus.dispose();
    _rateFocus.dispose();
    _discFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    return InkWell(
      onTap: widget.onSelect,
      child: Container(
        decoration: BoxDecoration(
          color: widget.selected
              ? scheme.primary.withValues(alpha: 0.07)
              : (widget.index.isEven
                  ? null
                  : AppTheme.subtleOf(context).withValues(alpha: 0.55)),
          border: Border(
            left: BorderSide(
              width: 3,
              color: widget.selected ? scheme.primary : Colors.transparent,
            ),
            bottom: BorderSide(color: AppTheme.borderOf(context), width: 0.6),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: CartCols.sn - 3,
              child: Text('${widget.index + 1}',
                  style: TextStyle(fontSize: 12, color: muted)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      if (it.sku.isNotEmpty) it.sku,
                      if (it.hsn.isNotEmpty) 'HSN ${it.hsn}',
                      if (it.mrp > 0) 'MRP ${Fmt.amount(it.mrp)}',
                      if (it.freeQty > 0) '+${Fmt.qty(it.freeQty)} free',
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: muted),
                  ),
                ],
              ),
            ),
            _cell(
                CartCols.qty,
                _num(_qty, _qtyFocus, onDone: () {
                  widget.onQty(Fmt.toDouble(_qty.text, it.qty));
                })),
            SizedBox(
              width: CartCols.unit,
              child: Text(it.unit,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ),
            _cell(
                CartCols.rate,
                _num(_rate, _rateFocus, onDone: () {
                  widget.onRate(Fmt.toDouble(_rate.text, it.grossRate));
                })),
            _cell(
              CartCols.disc,
              _num(_disc, _discFocus, suffixText: '%', onDone: () {
                widget.onDiscount(Fmt.toDouble(_disc.text));
              }),
            ),
            SizedBox(
              width: CartCols.gst,
              child: Text('${Fmt.qty(it.gstRate)}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: muted)),
            ),
            if (widget.showTax)
              SizedBox(
                width: CartCols.tax,
                child: Money(it.taxAmount, size: 12, symbol: false),
              ),
            SizedBox(
              width: CartCols.amount,
              child: Money(it.total, size: 13.5, bold: true, symbol: false),
            ),
            SizedBox(
              width: CartCols.action,
              child: IconButton(
                tooltip: 'Remove line',
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                color: AppTheme.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(double width, Widget child) =>
      SizedBox(width: width, child: child);

  Widget _num(
    TextEditingController controller,
    FocusNode focus, {
    String? suffixText,
    VoidCallback? onDone,
  }) {
    return TextField(
      controller: controller,
      focusNode: focus,
      textAlign: TextAlign.right,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: Field.decimal,
      onSubmitted: (_) => onDone?.call(),
      onEditingComplete: onDone,
      decoration: InputDecoration(
        isDense: true,
        suffixText: suffixText,
        suffixStyle: const TextStyle(fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      ),
    );
  }
}

/// Header strip above the cart rows.
class CartHeader extends StatelessWidget {
  const CartHeader({super.key, this.showTax = true});
  final bool showTax;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    Widget h(double w, String t, [TextAlign a = TextAlign.center]) =>
        SizedBox(width: w, child: Text(t, textAlign: a, style: style));

    return Container(
      color: AppTheme.subtleOf(context),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      child: Row(
        children: [
          h(CartCols.sn - 3, '#', TextAlign.left),
          Expanded(child: Text('ITEM', style: style)),
          h(CartCols.qty, 'QTY', TextAlign.right),
          h(CartCols.unit, 'UNIT'),
          h(CartCols.rate, 'RATE', TextAlign.right),
          h(CartCols.disc, 'DISC %', TextAlign.right),
          h(CartCols.gst, 'GST'),
          if (showTax) h(CartCols.tax, 'TAX', TextAlign.right),
          h(CartCols.amount, 'AMOUNT', TextAlign.right),
          h(CartCols.action, ''),
        ],
      ),
    );
  }
}
