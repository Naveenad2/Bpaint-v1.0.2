import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/tax.dart';
import '../../data/models.dart';
import '../../data/repos/sales_repo.dart';
import '../../print/print_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Raises a credit note against an existing invoice. The operator sets the
/// quantity coming back on each line; everything else is copied from the
/// original bill so the tax matches exactly.
class SalesReturnDialog extends StatefulWidget {
  const SalesReturnDialog({super.key, required this.invoice});
  final SalesDoc invoice;

  static Future<bool> show(BuildContext context, SalesDoc invoice) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => SalesReturnDialog(invoice: invoice),
      ) ??
      false;

  @override
  State<SalesReturnDialog> createState() => _SalesReturnDialogState();
}

class _SalesReturnDialogState extends State<SalesReturnDialog> {
  final _repo = SalesRepo();
  late final List<TextEditingController> _qty;
  late SalesDoc _cn;
  final _reason = TextEditingController();
  bool _refundCash = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _qty = widget.invoice.items
        .map((e) => TextEditingController(text: Fmt.qty(e.qty)))
        .toList();
    _cn = SalesDoc(
      docType: DocType.creditNote,
      partyId: widget.invoice.partyId,
      partyName: widget.invoice.partyName,
      partyPhone: widget.invoice.partyPhone,
      partyGstin: widget.invoice.partyGstin,
      partyAddress: widget.invoice.partyAddress,
      placeOfSupply: widget.invoice.placeOfSupply,
      isIgst: widget.invoice.isIgst,
      priceIncludesTax: widget.invoice.priceIncludesTax,
      priceTier: widget.invoice.priceTier,
      refDocId: widget.invoice.id,
      refDocNo: widget.invoice.docNo,
      paymentMode: widget.invoice.paymentMode,
    );
    _rebuild();
  }

  @override
  void dispose() {
    for (final c in _qty) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  void _rebuild() {
    _cn.items = [];
    for (var i = 0; i < widget.invoice.items.length; i++) {
      final q = Fmt.toDouble(_qty[i].text);
      if (q <= 0) continue;
      final src = widget.invoice.items[i];
      final capped = q > src.qty ? src.qty : q;
      final item = SalesItem.fromMap(src.toMap()
        ..remove('id')
        ..remove('doc_id'));
      item.qty = capped;
      _cn.items.add(item);
    }
    TaxEngine.computeDoc(_cn,
        applyRoundOff: context.read<AppState>().roundOffEnabled);
    setState(() {});
  }

  Future<void> _save() async {
    if (_cn.items.isEmpty) {
      toast(context, 'Set a return quantity on at least one line.',
          error: true);
      return;
    }
    setState(() => _busy = true);
    final app = context.read<AppState>();
    _cn.notes = _reason.text.trim();
    _cn.paid = _refundCash ? _cn.total : 0;
    _cn.paymentMode = _refundCash ? PaymentModes.cash : PaymentModes.credit;
    try {
      final saved =
          await _repo.save(_cn, user: app.user, roundOff: app.roundOffEnabled);
      if (!mounted) return;
      toast(context, 'Credit note ${saved.docNo} created.', success: true);
      await PrintService.printInvoice(context, app, saved);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'Could not save the return: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 660),
        child: BusyOverlay(
          busy: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                icon: Icons.assignment_return_rounded,
                title: 'Sales return against ${widget.invoice.docNo}',
                subtitle:
                    '${widget.invoice.partyName}  ·  ${Fmt.date(widget.invoice.docDate)}',
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (var i = 0; i < widget.invoice.items.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(widget.invoice.items[i].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    'Sold ${Fmt.qty(widget.invoice.items[i].qty)} '
                                    '${widget.invoice.items[i].unit} @ '
                                    '${Fmt.amount(widget.invoice.items[i].grossRate)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: Field(
                                label: 'Return qty',
                                controller: _qty[i],
                                inputFormatters: Field.decimal,
                                onChanged: (_) => _rebuild(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 70,
                              child: TextButton(
                                onPressed: () {
                                  _qty[i].text = '0';
                                  _rebuild();
                                },
                                child: const Text('None'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 24),
                    Field(
                      label: 'Reason for return',
                      controller: _reason,
                      hint: 'Wrong shade, damaged tin, excess quantity…',
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      value: _refundCash,
                      onChanged: (v) => setState(() => _refundCash = v),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Refund in cash now',
                          style: TextStyle(fontSize: 13.5)),
                      subtitle: const Text(
                          'Turn off to keep it as credit on the customer account',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Credit note value',
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        Money(_cn.total, size: 20, bold: true),
                      ],
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Create credit note'),
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
