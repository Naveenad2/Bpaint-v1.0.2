import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/payment_repo.dart';
import '../../data/repos/sales_repo.dart';
import '../../state/app_state.dart';
import '../parties/party_picker.dart';
import '../widgets/common.dart';

/// Records a receipt from a customer or a payment to a supplier, optionally
/// settling a specific bill.
class PaymentEditor extends StatefulWidget {
  const PaymentEditor({super.key, this.party, this.direction = 'IN', this.doc});

  final Party? party;
  final String direction;
  final SalesDoc? doc;

  static Future<bool> show(
    BuildContext context, {
    Party? party,
    String direction = 'IN',
    SalesDoc? doc,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) =>
            PaymentEditor(party: party, direction: direction, doc: doc),
      ) ??
      false;

  @override
  State<PaymentEditor> createState() => _PaymentEditorState();
}

class _PaymentEditorState extends State<PaymentEditor> {
  final _repo = PaymentRepo();
  final _sales = SalesRepo();

  final _amount = TextEditingController();
  final _discount = TextEditingController();
  final _ref = TextEditingController();
  final _bank = TextEditingController();
  final _notes = TextEditingController();

  Party? _party;
  String _mode = PaymentModes.cash;
  DateTime _date = DateTime.now();
  SalesDoc? _againstDoc;
  List<SalesDoc> _pending = const [];
  bool _busy = false;

  bool get _isReceipt => widget.direction == 'IN';

  @override
  void initState() {
    super.initState();
    _party = widget.party;
    _againstDoc = widget.doc;
    if (widget.doc != null) {
      _amount.text = Fmt.qty(widget.doc!.balance);
    } else if (_party != null && _party!.balance > 0) {
      _amount.text = Fmt.qty(_party!.balance);
    }
    _loadPending();
  }

  @override
  void dispose() {
    _amount.dispose();
    _discount.dispose();
    _ref.dispose();
    _bank.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadPending() async {
    final p = _party;
    if (p == null || p.kind != 'CUSTOMER') {
      setState(() => _pending = const []);
      return;
    }
    final rows = await _sales.list(partyId: p.id, limit: 100);
    if (!mounted) return;
    setState(() {
      _pending = rows.where((d) => d.balance > 0.5 && !d.isCancelled).toList();
    });
  }

  Future<void> _pickParty() async {
    final p = await PartyPicker.show(context,
        kind: _isReceipt ? 'CUSTOMER' : 'SUPPLIER');
    if (p == null) return;
    setState(() {
      _party = p;
      _againstDoc = null;
      if (p.balance > 0) _amount.text = Fmt.qty(p.balance);
    });
    await _loadPending();
  }

  Future<void> _save() async {
    final party = _party;
    if (party == null) {
      toast(context, 'Choose a party first.', error: true);
      return;
    }
    final amount = Fmt.toDouble(_amount.text);
    if (amount <= 0) {
      toast(context, 'Enter an amount greater than zero.', error: true);
      return;
    }
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final voucher = PaymentVoucher(
      date: _date,
      direction: widget.direction,
      partyId: party.id,
      partyName: party.name,
      docId: _againstDoc?.id,
      docNo: _againstDoc?.docNo ?? '',
      amount: amount,
      discount: Fmt.toDouble(_discount.text),
      mode: _mode,
      refNo: _ref.text.trim(),
      bankName: _bank.text.trim(),
      notes: _notes.text.trim(),
      userId: app.user?.id,
    );
    try {
      await _repo.save(voucher, partyKind: party.kind);
      if (!mounted) return;
      toast(context,
          '${_isReceipt ? 'Receipt' : 'Payment'} of ${Fmt.money(amount)} recorded.',
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
    final party = _party;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: BusyOverlay(
          busy: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                icon: _isReceipt
                    ? Icons.call_received_rounded
                    : Icons.call_made_rounded,
                title: _isReceipt
                    ? 'Receipt from customer'
                    : 'Payment to supplier',
                subtitle: _isReceipt
                    ? 'Money coming in — reduces what the customer owes'
                    : 'Money going out — reduces what you owe the supplier',
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap: _pickParty,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderOf(context)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.person_rounded, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(party?.name ?? 'Select party',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  if (party != null)
                                    Text(
                                      'Outstanding ${Fmt.money(party.balance)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: party.balance > 0.5
                                            ? AppTheme.danger
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_pending.isNotEmpty) ...[
                      Picker<int?>(
                        label: 'Settle against bill (optional)',
                        value: _pending.any((d) => d.id == _againstDoc?.id)
                            ? _againstDoc?.id
                            : null,
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('On account')),
                          ..._pending.map((d) => DropdownMenuItem<int?>(
                                value: d.id,
                                child: Text(
                                    '${d.docNo} · ${Fmt.date(d.docDate)} · due ${Fmt.money(d.balance)}'),
                              )),
                        ],
                        onChanged: (v) => setState(() {
                          _againstDoc = v == null
                              ? null
                              : _pending.firstWhere((d) => d.id == v);
                          if (_againstDoc != null) {
                            _amount.text = Fmt.qty(_againstDoc!.balance);
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FieldRow([
                      Field(
                        label: 'Amount *',
                        controller: _amount,
                        autofocus: true,
                        inputFormatters: Field.decimal,
                        prefix:
                            const Icon(Icons.currency_rupee_rounded, size: 16),
                      ),
                      Field(
                        label: 'Discount allowed',
                        controller: _discount,
                        inputFormatters: Field.decimal,
                        helper: 'Written off along with this receipt',
                      ),
                    ]),
                    FieldRow([
                      Picker<String>(
                        label: 'Mode',
                        value: _mode,
                        items: PaymentModes.all
                            .where((m) => m != PaymentModes.credit)
                            .map((m) =>
                                DropdownMenuItem(value: m, child: Text(m)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _mode = v ?? PaymentModes.cash),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2015),
                            lastDate: DateTime.now(),
                          );
                          if (d != null) setState(() => _date = d);
                        },
                        icon: const Icon(Icons.event_rounded, size: 16),
                        label: Text(Fmt.date(_date)),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16)),
                      ),
                    ]),
                    if (_mode != PaymentModes.cash)
                      FieldRow([
                        Field(
                          label: 'Reference / UTR / cheque no',
                          controller: _ref,
                        ),
                        Field(label: 'Bank', controller: _bank),
                      ]),
                    FieldRow([
                      Field(label: 'Notes', controller: _notes),
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
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                          _isReceipt ? 'Record receipt' : 'Record payment'),
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
