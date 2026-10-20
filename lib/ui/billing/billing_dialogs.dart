import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repos/sales_repo.dart';
import '../../state/billing_state.dart';
import '../widgets/common.dart';

/// F7 — add a line that is not in the catalogue (tinting, labour, delivery).
class CustomLineDialog extends StatefulWidget {
  const CustomLineDialog({super.key, this.defaultGst = 18});
  final double defaultGst;

  static Future<void> show(BuildContext context, BillingState bill,
      {double defaultGst = 18}) async {
    final result = await showDialog<Map<String, Object>>(
      context: context,
      builder: (_) => CustomLineDialog(defaultGst: defaultGst),
    );
    if (result == null) return;
    bill.addCustomLine(
      name: result['name'] as String,
      qty: result['qty'] as double,
      rate: result['rate'] as double,
      gstRate: result['gst'] as double,
      unit: result['unit'] as String,
      hsn: result['hsn'] as String,
    );
  }

  @override
  State<CustomLineDialog> createState() => _CustomLineDialogState();
}

class _CustomLineDialogState extends State<CustomLineDialog> {
  final _name = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _rate = TextEditingController();
  final _hsn = TextEditingController();
  late double _gst = widget.defaultGst;
  String _unit = 'NOS';

  static const _presets = [
    ('Tinting / Colour mixing charge', '9954', 18.0, 'NOS'),
    ('Painting labour charge', '9954', 18.0, 'SQF'),
    ('Delivery / freight charge', '9965', 18.0, 'NOS'),
    ('Machine hire charge', '9973', 18.0, 'NOS'),
  ];

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _rate.dispose();
    _hsn.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final rate = Fmt.toDouble(_rate.text);
    if (name.isEmpty || rate <= 0) {
      toast(context, 'Enter a description and a rate.', error: true);
      return;
    }
    Navigator.pop(context, <String, Object>{
      'name': name,
      'qty': Fmt.toDouble(_qty.text, 1),
      'rate': rate,
      'gst': _gst,
      'unit': _unit,
      'hsn': _hsn.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): _submit,
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DialogHeader(
                icon: Icons.playlist_add_rounded,
                title: 'Add charge or custom item',
                subtitle: 'Anything that is not in the item master',
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in _presets)
                          ActionChip(
                            label: Text(p.$1,
                                style: const TextStyle(fontSize: 11.5)),
                            onPressed: () => setState(() {
                              _name.text = p.$1;
                              _hsn.text = p.$2;
                              _gst = p.$3;
                              _unit = p.$4;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Field(
                      label: 'Description *',
                      controller: _name,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    FieldRow([
                      Field(
                        label: 'Quantity',
                        controller: _qty,
                        inputFormatters: Field.decimal,
                      ),
                      Picker<String>(
                        label: 'Unit',
                        value: _unit,
                        items: Units.all
                            .map((u) =>
                                DropdownMenuItem(value: u, child: Text(u)))
                            .toList(),
                        onChanged: (v) => setState(() => _unit = v ?? 'NOS'),
                      ),
                      Field(
                        label: 'Rate *',
                        controller: _rate,
                        inputFormatters: Field.decimal,
                      ),
                    ]),
                    FieldRow([
                      Field(label: 'HSN / SAC', controller: _hsn),
                      Picker<double>(
                        label: 'GST rate',
                        value: _gst,
                        items: TaxRates.slabs
                            .map((r) => DropdownMenuItem(
                                value: r, child: Text('${Fmt.qty(r)} %')))
                            .toList(),
                        onChanged: (v) => setState(() => _gst = v ?? 18),
                      ),
                    ], bottom: 0),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add to bill'),
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
}

/// F6 — bill-level discount, entered either as a percentage or a flat amount.
class BillDiscountDialog extends StatefulWidget {
  const BillDiscountDialog({super.key, required this.bill});
  final BillingState bill;

  static Future<void> show(BuildContext context, BillingState bill) =>
      showDialog<void>(
        context: context,
        builder: (_) => BillDiscountDialog(bill: bill),
      );

  @override
  State<BillDiscountDialog> createState() => _BillDiscountDialogState();
}

class _BillDiscountDialogState extends State<BillDiscountDialog> {
  late final TextEditingController _pct = TextEditingController(
      text: widget.bill.doc.docDiscountPct == 0
          ? ''
          : Fmt.qty(widget.bill.doc.docDiscountPct));
  late final TextEditingController _amt = TextEditingController(
      text: widget.bill.doc.docDiscountAmt == 0
          ? ''
          : Fmt.qty(widget.bill.doc.docDiscountAmt));

  @override
  void dispose() {
    _pct.dispose();
    _amt.dispose();
    super.dispose();
  }

  void _apply({required bool percent}) {
    if (percent) {
      widget.bill.setBillDiscountPct(Fmt.toDouble(_pct.text));
    } else {
      widget.bill.setBillDiscountAmount(Fmt.toDouble(_amt.text));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.bill.doc;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DialogHeader(
              icon: Icons.percent_rounded,
              title: 'Bill discount',
              subtitle:
                  'Spread across every line before tax, as GST law requires',
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Field(
                          label: 'Discount %',
                          controller: _pct,
                          autofocus: true,
                          inputFormatters: Field.decimal,
                          onSubmitted: (_) => _apply(percent: true),
                          onChanged: (_) => _amt.clear(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('or', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Field(
                          label: 'Flat amount',
                          controller: _amt,
                          inputFormatters: Field.decimal,
                          onSubmitted: (_) => _apply(percent: false),
                          onChanged: (_) => _pct.clear(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in [2, 5, 10, 15])
                        OutlinedButton(
                          onPressed: () {
                            _pct.text = '$p';
                            _amt.clear();
                            _apply(percent: true);
                          },
                          child: Text('$p%'),
                        ),
                      OutlinedButton(
                        onPressed: () {
                          widget.bill.setBillDiscountAmount(0);
                          Navigator.pop(context);
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Current bill value ${Fmt.money(doc.total)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () =>
                        _apply(percent: _pct.text.trim().isNotEmpty),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// F8 — settle the bill: mode, amount received, change to return.
class PaymentDialog extends StatefulWidget {
  const PaymentDialog({super.key, required this.bill});
  final BillingState bill;

  static Future<bool> show(BuildContext context, BillingState bill) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => PaymentDialog(bill: bill),
      ) ??
      false;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  late final TextEditingController _received =
      TextEditingController(text: Fmt.qty(widget.bill.doc.total));
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Deferred: setPaid notifies the billing model, and the counter screen
    // listening to it is still being built at this point.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.bill.setPaid(widget.bill.doc.total);
    });
  }

  @override
  void dispose() {
    _received.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setMode(String mode) {
    widget.bill.setPaymentMode(mode);
    _received.text =
        mode == PaymentModes.credit ? '0' : Fmt.qty(widget.bill.doc.total);
    setState(() {});
  }

  void _done() => Navigator.pop(context, true);

  @override
  Widget build(BuildContext context) {
    final doc = widget.bill.doc;
    final received = Fmt.toDouble(_received.text);
    final change = received > doc.total ? Fmt.round(received - doc.total) : 0.0;
    final due = received < doc.total ? Fmt.round(doc.total - received) : 0.0;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f9): _done,
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DialogHeader(
                icon: Icons.payments_rounded,
                title: 'Payment',
                subtitle: 'F9 to confirm',
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Bill total',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          Money(doc.total, size: 24, bold: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in PaymentModes.all)
                          ChoiceChip(
                            selected: doc.paymentMode == m,
                            onSelected: (_) => _setMode(m),
                            avatar: Icon(_icon(m), size: 15),
                            label: Text(m),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Field(
                      label: 'Amount received',
                      controller: _received,
                      focusNode: _focus,
                      autofocus: true,
                      inputFormatters: Field.decimal,
                      prefix:
                          const Icon(Icons.currency_rupee_rounded, size: 16),
                      onChanged: (v) {
                        widget.bill.setPaid(Fmt.toDouble(v));
                        setState(() {});
                      },
                      onSubmitted: (_) => _done(),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final n in _cashSuggestions(doc.total))
                          OutlinedButton(
                            onPressed: () {
                              _received.text = Fmt.qty(n);
                              widget.bill.setPaid(n.toDouble());
                              setState(() {});
                            },
                            child: Text(Fmt.compact(n)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _figure(
                              'Change to return', change, AppTheme.success),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child:
                              _figure('Balance (credit)', due, AppTheme.danger),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _done,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Confirm  (F9)'),
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

  Widget _figure(String label, double value, Color color) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: color.withValues(alpha: value > 0 ? 0.10 : 0.04),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
            const SizedBox(height: 2),
            Money(value, size: 18, bold: true, color: color),
          ],
        ),
      );

  static IconData _icon(String mode) => switch (mode) {
        PaymentModes.cash => Icons.payments_rounded,
        PaymentModes.upi => Icons.qr_code_rounded,
        PaymentModes.card => Icons.credit_card_rounded,
        PaymentModes.bank => Icons.account_balance_rounded,
        PaymentModes.cheque => Icons.receipt_rounded,
        _ => Icons.schedule_rounded,
      };

  /// Note-friendly amounts a customer is likely to hand over.
  static List<num> _cashSuggestions(double total) {
    final out = <num>{total.ceilToDouble()};
    for (final step in [50, 100, 500, 1000]) {
      final v = (total / step).ceil() * step;
      if (v >= total) out.add(v);
    }
    final list = out.toList()..sort();
    return list.take(4).toList();
  }
}

/// F4 / F5 — park a bill and bring it back later.
class HeldBillsDialog extends StatefulWidget {
  const HeldBillsDialog({super.key});

  static Future<int?> show(BuildContext context) => showDialog<int>(
        context: context,
        builder: (_) => const HeldBillsDialog(),
      );

  @override
  State<HeldBillsDialog> createState() => _HeldBillsDialogState();
}

class _HeldBillsDialogState extends State<HeldBillsDialog> {
  final _repo = SalesRepo();
  List<({int id, String label, DateTime at, double total})> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _repo.heldBills();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DialogHeader(
              icon: Icons.pause_circle_outline_rounded,
              title: 'Parked bills',
              subtitle: 'Pick one to bring it back to the counter',
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? const EmptyState(
                          title: 'Nothing parked',
                          message: 'Press F4 while billing to park a bill.',
                          icon: Icons.inbox_rounded,
                        )
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = _rows[i];
                            return ListTile(
                              leading: const Icon(Icons.receipt_long_rounded,
                                  size: 20),
                              title: Text(
                                  r.label.isEmpty ? 'Bill ${r.id}' : r.label,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(Fmt.dateTime(r.at),
                                  style: const TextStyle(fontSize: 11.5)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Money(r.total, size: 13, bold: true),
                                  IconButton(
                                    tooltip: 'Discard',
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18),
                                    onPressed: () async {
                                      await _repo.dropHeld(r.id);
                                      await _load();
                                    },
                                  ),
                                ],
                              ),
                              onTap: () => Navigator.pop(context, r.id),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
