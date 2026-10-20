import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/payment_repo.dart';
import '../widgets/common.dart';
import 'payment_editor.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  final _repo = PaymentRepo();
  final _search = TextEditingController();

  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String _direction = '';
  List<PaymentVoucher> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.list(
      from: _from,
      to: _to,
      direction: _direction.isEmpty ? null : _direction,
      query: _search.text,
      limit: 800,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  double get _in => _rows
      .where((e) => e.direction == 'IN')
      .fold<double>(0.0, (s, e) => s + e.amount);
  double get _out => _rows
      .where((e) => e.direction == 'OUT')
      .fold<double>(0.0, (s, e) => s + e.amount);

  Future<void> _add(String direction) async {
    final done = await PaymentEditor.show(context, direction: direction);
    if (done) await _load();
  }

  Future<void> _delete(PaymentVoucher v) async {
    final ok = await confirm(
      context,
      title: 'Delete ${v.voucherNo}?',
      message:
          'The party balance and any bill it settled will be adjusted back.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _repo.delete(v.id!);
    await _load();
    if (mounted) toast(context, 'Voucher removed.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Toolbar(
          leading: [
            DateRangeBar(
              from: _from,
              to: _to,
              onChanged: (f, t) {
                setState(() {
                  _from = f;
                  _to = t;
                });
                _load();
              },
            ),
            SizedBox(
              width: 150,
              child: Picker<String>(
                label: 'Direction',
                value: _direction,
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'IN', child: Text('Receipts')),
                  DropdownMenuItem(value: 'OUT', child: Text('Payments')),
                ],
                onChanged: (v) {
                  setState(() => _direction = v ?? '');
                  _load();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: Field(
                label: 'Search party or reference',
                controller: _search,
                prefix: const Icon(Icons.search_rounded, size: 18),
                onChanged: (_) => _load(),
              ),
            ),
          ],
          actions: [
            ElevatedButton.icon(
              onPressed: () => _add('IN'),
              icon: const Icon(Icons.call_received_rounded, size: 17),
              label: const Text('Receipt'),
            ),
            OutlinedButton.icon(
              onPressed: () => _add('OUT'),
              icon: const Icon(Icons.call_made_rounded, size: 17),
              label: const Text('Payment'),
            ),
          ],
        ),
        StatStrip(
          children: [
            Text('${_rows.length} vouchers',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            StatText('Received', Fmt.money(_in), color: AppTheme.success),
            StatText('Paid out', Fmt.money(_out), color: AppTheme.danger),
            StatText('Net', Fmt.money(_in - _out)),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState(
                      title: 'No vouchers in this range',
                      message:
                          'Receipts recorded at the billing counter appear '
                          'here automatically.',
                      icon: Icons.account_balance_wallet_rounded,
                    )
                  : MinWidthScroller(
                      minWidth: 860.0,
                      child: Scrollbar(
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemExtent: 50,
                          itemBuilder: (context, i) => _row(_rows[i], i),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _row(PaymentVoucher v, int index) {
    final isIn = v.direction == 'IN';
    return Container(
      decoration: BoxDecoration(
        color: index.isEven
            ? null
            : AppTheme.subtleOf(context).withValues(alpha: 0.5),
        border: Border(
            bottom: BorderSide(color: AppTheme.borderOf(context), width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            isIn ? Icons.call_received_rounded : Icons.call_made_rounded,
            size: 17,
            color: isIn ? AppTheme.success : AppTheme.danger,
          ),
          const SizedBox(width: 12),
          SizedBox(
              width: 96,
              child: Text(Fmt.date(v.date),
                  style: const TextStyle(fontSize: 12.5))),
          SizedBox(
              width: 100,
              child: Text(v.voucherNo,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700))),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.partyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  [
                    v.mode,
                    if (v.docNo.isNotEmpty) 'against ${v.docNo}',
                    if (v.refNo.isNotEmpty && v.refNo != 'AUTO-BILL') v.refNo,
                    if (v.notes.isNotEmpty) v.notes,
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (v.discount > 0)
            SizedBox(
              width: 110,
              child: Text('Disc ${Fmt.amount(v.discount)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11.5)),
            ),
          SizedBox(
            width: 120,
            child: Money(v.amount,
                size: 14,
                bold: true,
                color: isIn ? AppTheme.success : AppTheme.danger),
          ),
          SizedBox(
            width: 44,
            child: IconButton(
              tooltip: 'Delete voucher',
              icon: const Icon(Icons.delete_outline_rounded, size: 17),
              onPressed: () => _delete(v),
            ),
          ),
        ],
      ),
    );
  }
}
