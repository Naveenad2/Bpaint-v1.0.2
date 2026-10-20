import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/tax.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/payment_repo.dart';
import '../../data/repos/sales_repo.dart';
import '../../print/print_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Read-only view of a saved document with print, return and cancel actions.
class InvoiceDetail extends StatefulWidget {
  const InvoiceDetail({super.key, required this.docId});
  final int docId;

  static Future<String?> show(BuildContext context, int docId) =>
      showDialog<String>(
        context: context,
        builder: (_) => InvoiceDetail(docId: docId),
      );

  @override
  State<InvoiceDetail> createState() => _InvoiceDetailState();
}

class _InvoiceDetailState extends State<InvoiceDetail> {
  final _repo = SalesRepo();
  final _payments = PaymentRepo();

  SalesDoc? _doc;
  List<PaymentVoucher> _receipts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await _repo.byId(widget.docId);
    final pays = doc == null
        ? <PaymentVoucher>[]
        : await _payments.list(partyId: doc.partyId, limit: 200);
    if (!mounted) return;
    setState(() {
      _doc = doc;
      _receipts = pays
          .where((p) => p.docId == widget.docId || p.docNo == doc?.docNo)
          .toList();
      _loading = false;
    });
  }

  Future<void> _cancel() async {
    final doc = _doc;
    if (doc == null) return;
    final app = context.read<AppState>();
    if (!app.canManage) {
      toast(context, 'Only a manager or admin can cancel a bill.', error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: 'Cancel ${doc.docNo}?',
      message: 'Stock will be returned and the customer balance reversed. '
          'The bill number stays in the books as cancelled, which is what '
          'GST requires.',
      confirmLabel: 'Cancel bill',
      destructive: true,
    );
    if (!ok) return;
    await _repo.cancel(doc.id!, user: app.user, reason: 'Cancelled by user');
    if (!mounted) return;
    Navigator.pop(context, 'changed');
  }

  Future<void> _print({bool preview = false}) async {
    final doc = _doc;
    if (doc == null) return;
    final app = context.read<AppState>();
    if (preview) {
      await PrintService.previewInvoice(context, app, doc);
    } else {
      await PrintService.printInvoice(context, app, doc, forceDialog: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 720),
        child: _loading
            ? const SizedBox(
                height: 240, child: Center(child: CircularProgressIndicator()))
            : doc == null
                ? const SizedBox(
                    height: 240,
                    child: EmptyState(
                        title: 'Document not found',
                        icon: Icons.error_outline_rounded),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DialogHeader(
                        icon: Icons.receipt_long_rounded,
                        title: '${DocType.label[doc.docType]}  ·  ${doc.docNo}',
                        subtitle:
                            '${Fmt.date(doc.docDate)}  ·  ${doc.partyName}'
                            '${doc.userName.isEmpty ? '' : '  ·  billed by ${doc.userName}'}',
                        actions: [
                          StatusPill(doc.status),
                          const SizedBox(width: 10),
                        ],
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _partyStrip(doc),
                              const SizedBox(height: 14),
                              _items(doc),
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 5, child: _taxSummary(doc)),
                                  const SizedBox(width: 14),
                                  Expanded(flex: 4, child: _totals(doc)),
                                ],
                              ),
                              if (_receipts.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _receiptList(),
                              ],
                              if (doc.notes.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                AppCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SectionTitle('Notes',
                                          icon: Icons.sticky_note_2_rounded),
                                      Text(doc.notes,
                                          style:
                                              const TextStyle(fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            if (!doc.isCancelled &&
                                doc.docType == DocType.invoice)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    Navigator.pop(context, 'credit-note'),
                                icon: const Icon(
                                    Icons.assignment_return_rounded,
                                    size: 17),
                                label: const Text('Sales return'),
                              ),
                            const SizedBox(width: 8),
                            if (!doc.isCancelled)
                              OutlinedButton.icon(
                                onPressed: _cancel,
                                icon: const Icon(Icons.block_rounded, size: 17),
                                label: const Text('Cancel bill'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.danger),
                              ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: () => _print(preview: true),
                              icon: const Icon(Icons.visibility_rounded,
                                  size: 17),
                              label: const Text('Preview'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _print(),
                              icon: const Icon(Icons.print_rounded, size: 18),
                              label: const Text('Print'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _partyStrip(SalesDoc doc) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.partyName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  if (doc.partyAddress.isNotEmpty)
                    Text(doc.partyAddress,
                        style: const TextStyle(fontSize: 12)),
                  Text(
                    [
                      if (doc.partyPhone.isNotEmpty) 'Ph ${doc.partyPhone}',
                      if (doc.partyGstin.isNotEmpty) 'GSTIN ${doc.partyGstin}',
                    ].join('  ·  '),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            _fact('Place of supply',
                '${IndianStates.name(doc.placeOfSupply)} (${doc.placeOfSupply})'),
            _fact('Supply', doc.isIgst ? 'Inter-state' : 'Intra-state'),
            _fact('Payment', doc.paymentMode),
          ],
        ),
      );

  Widget _fact(String k, String v) => Container(
        margin: const EdgeInsets.only(left: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(v, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      );

  Widget _items(SalesDoc doc) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ScrollableTable(
        minWidth: 820,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Item')),
            DataColumn(label: Text('HSN')),
            DataColumn(label: Text('Qty'), numeric: true),
            DataColumn(label: Text('Rate'), numeric: true),
            DataColumn(label: Text('Disc'), numeric: true),
            DataColumn(label: Text('Taxable'), numeric: true),
            DataColumn(label: Text('GST'), numeric: true),
            DataColumn(label: Text('Tax'), numeric: true),
            DataColumn(label: Text('Amount'), numeric: true),
          ],
          rows: [
            for (var i = 0; i < doc.items.length; i++)
              DataRow(cells: [
                DataCell(Text('${i + 1}')),
                DataCell(SizedBox(
                  width: 240,
                  child: Text(doc.items[i].name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                )),
                DataCell(Text(doc.items[i].hsn)),
                DataCell(
                    Text('${Fmt.qty(doc.items[i].qty)} ${doc.items[i].unit}')),
                DataCell(Text(Fmt.amount(doc.items[i].grossRate))),
                DataCell(Text(doc.items[i].discountAmt == 0
                    ? '—'
                    : Fmt.amount(doc.items[i].discountAmt))),
                DataCell(Text(Fmt.amount(doc.items[i].taxable))),
                DataCell(Text('${Fmt.qty(doc.items[i].gstRate)}%')),
                DataCell(Text(Fmt.amount(doc.items[i].taxAmount))),
                DataCell(Text(Fmt.amount(doc.items[i].total),
                    style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _taxSummary(SalesDoc doc) {
    final slabs = TaxEngine.slabSummary(doc);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Tax summary', icon: Icons.calculate_rounded),
          for (final s in slabs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                      width: 54,
                      child: Text('${Fmt.qty(s.gstRate)}%',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700))),
                  Expanded(child: Money(s.taxable, size: 12.5, symbol: false)),
                  const SizedBox(width: 10),
                  Expanded(child: Money(s.totalTax, size: 12.5, symbol: false)),
                ],
              ),
            ),
          const Divider(height: 18),
          Text(NumberToWords.rupees(doc.total),
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _totals(SalesDoc doc) => AppCard(
        child: Column(
          children: [
            _row('Taxable value', doc.taxableAmount),
            if (doc.itemDiscount > 0) _row('Item discount', -doc.itemDiscount),
            if (doc.docDiscountAmt > 0)
              _row('Bill discount', -doc.docDiscountAmt),
            if (doc.isIgst)
              _row('IGST', doc.igst)
            else ...[
              _row('CGST', doc.cgst),
              _row('SGST', doc.sgst),
            ],
            if (doc.cess > 0) _row('Cess', doc.cess),
            if (doc.roundOff != 0) _row('Round off', doc.roundOff),
            const Divider(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Money(doc.total, size: 20, bold: true),
              ],
            ),
            const SizedBox(height: 6),
            _row('Paid', doc.paid),
            _row('Balance', doc.balance),
          ],
        ),
      );

  Widget _row(String k, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Money(v, size: 12.5, symbol: false),
          ],
        ),
      );

  Widget _receiptList() => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Payments against this bill',
                icon: Icons.payments_rounded),
            for (final p in _receipts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                        width: 90,
                        child: Text(p.voucherNo,
                            style: const TextStyle(fontSize: 12))),
                    SizedBox(
                        width: 100,
                        child: Text(Fmt.date(p.date),
                            style: const TextStyle(fontSize: 12))),
                    Expanded(
                        child: Text('${p.mode}  ${p.refNo}',
                            style: const TextStyle(fontSize: 12))),
                    Money(p.amount, size: 12.5, bold: true),
                  ],
                ),
              ),
          ],
        ),
      );
}
