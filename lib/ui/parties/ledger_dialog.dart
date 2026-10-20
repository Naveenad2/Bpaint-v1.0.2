import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/party_repo.dart';
import '../../print/print_service.dart';
import '../../print/report_pdf.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Running-balance statement for one customer or supplier.
class LedgerDialog extends StatefulWidget {
  const LedgerDialog({super.key, required this.party});
  final Party party;

  static Future<void> show(BuildContext context, Party party) =>
      showDialog<void>(
        context: context,
        builder: (_) => LedgerDialog(party: party),
      );

  @override
  State<LedgerDialog> createState() => _LedgerDialogState();
}

class _LedgerDialogState extends State<LedgerDialog> {
  final _repo = PartyRepo();
  List<LedgerRow> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _repo.ledger(widget.party.id!);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  double get _closing => _rows.isEmpty ? 0 : _rows.last.running;

  Future<void> _print() async {
    final app = context.read<AppState>();
    final bytes = await ReportPdf.statement(
      company: app.company,
      party: widget.party,
      rows: _rows,
    );
    if (!mounted) return;
    await PrintService.previewBytes(
      context,
      title: 'Statement · ${widget.party.name}',
      bytes: bytes,
      fileName: 'statement_${widget.party.code}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCustomer = widget.party.kind == 'CUSTOMER';
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogHeader(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Statement — ${widget.party.name}',
              subtitle: [
                widget.party.code,
                if (widget.party.phone.isNotEmpty) widget.party.phone,
                if (widget.party.gstin.isNotEmpty) widget.party.gstin,
              ].join('  ·  '),
              actions: [
                OutlinedButton.icon(
                  onPressed: _print,
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text('Print statement'),
                ),
                const SizedBox(width: 10),
              ],
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppTheme.subtleOf(context),
              child: Row(
                children: [
                  Text(
                    isCustomer
                        ? (_closing >= 0 ? 'Receivable' : 'Advance held')
                        : (_closing >= 0 ? 'Payable' : 'Advance paid'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 10),
                  Money(_closing.abs(),
                      size: 17,
                      bold: true,
                      color: _closing > 0.5
                          ? (isCustomer ? AppTheme.danger : AppTheme.warning)
                          : AppTheme.success),
                  const Spacer(),
                  if (widget.party.creditLimit > 0)
                    Text(
                      'Credit limit ${Fmt.money(widget.party.creditLimit)}'
                      '${widget.party.creditDays > 0 ? ' · ${widget.party.creditDays} days' : ''}',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemExtent: 42,
                      itemBuilder: (context, i) {
                        final r = _rows[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: i.isEven
                                ? null
                                : AppTheme.subtleOf(context)
                                    .withValues(alpha: 0.5),
                            border: Border(
                                bottom: BorderSide(
                                    color: AppTheme.borderOf(context),
                                    width: 0.4)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                  width: 96,
                                  child: Text(Fmt.date(r.date),
                                      style: const TextStyle(fontSize: 12.5))),
                              SizedBox(
                                  width: 110,
                                  child: Text(r.voucherNo,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600))),
                              Expanded(
                                  child: Text(r.particulars,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5))),
                              SizedBox(
                                width: 104,
                                child: r.debit == 0
                                    ? const SizedBox.shrink()
                                    : Money(r.debit, size: 12.5, symbol: false),
                              ),
                              SizedBox(
                                width: 104,
                                child: r.credit == 0
                                    ? const SizedBox.shrink()
                                    : Money(r.credit,
                                        size: 12.5, symbol: false),
                              ),
                              SizedBox(
                                width: 116,
                                child: Money(r.running,
                                    size: 12.5, bold: true, symbol: false),
                              ),
                            ],
                          ),
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
