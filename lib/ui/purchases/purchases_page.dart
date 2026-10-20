import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/purchase_repo.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'purchase_editor.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _repo = PurchaseRepo();
  final _search = TextEditingController();

  DateTime _from = DateTime.now().subtract(const Duration(days: 60));
  DateTime _to = DateTime.now();
  String _docType = 'PURCHASE';
  List<PurchaseDoc> _rows = const [];
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
      docType: _docType,
      query: _search.text,
      limit: 500,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _new({bool isReturn = false}) async {
    // Captured before the await so no BuildContext crosses the async gap.
    final app = context.read<AppState>();
    final saved = await PurchaseEditor.show(context, isReturn: isReturn);
    if (!saved) return;
    await _load();
    await app.refreshAlerts();
  }

  Future<void> _open(PurchaseDoc d) async {
    final full = await _repo.byId(d.id!);
    if (full == null || !mounted) return;
    final saved = await PurchaseEditor.show(context, existing: full);
    if (saved) await _load();
  }

  Future<void> _delete(PurchaseDoc d) async {
    final user = context.read<AppState>().user;
    final ok = await confirm(
      context,
      title: 'Delete ${d.docNo}?',
      message: 'Stock brought in by this bill will be taken back out and the '
          'supplier balance reversed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _repo.delete(d.id!, user: user);
    await _load();
    if (mounted) toast(context, 'Purchase deleted.');
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0.0, (s, e) => s + e.total);
    final due = _rows.fold<double>(0.0, (s, e) => s + e.balance);

    return Column(
      children: [
        Toolbar(
          leading: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PURCHASE', label: Text('Purchases')),
                ButtonSegment(value: 'PURCHASE_RETURN', label: Text('Returns')),
              ],
              selected: {_docType},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _docType = s.first);
                _load();
              },
            ),
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
              width: 220,
              child: Field(
                label: 'Search bill no or supplier',
                controller: _search,
                prefix: const Icon(Icons.search_rounded, size: 18),
                onChanged: (_) => _load(),
              ),
            ),
          ],
          actions: [
            ElevatedButton.icon(
              onPressed: () => _new(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New purchase'),
            ),
            OutlinedButton.icon(
              onPressed: () => _new(isReturn: true),
              icon: const Icon(Icons.undo_rounded, size: 17),
              label: const Text('Return'),
            ),
          ],
        ),
        StatStrip(
          children: [
            Text('${_rows.length} bills',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
            StatText('Value', Fmt.money(total)),
            StatText('Unpaid', Fmt.money(due),
                color: due > 0.5 ? AppTheme.danger : null),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? EmptyState(
                      title: 'No purchase bills yet',
                      message:
                          'Enter supplier bills here — stock, cost prices and '
                          'input tax credit all follow from them.',
                      icon: Icons.local_shipping_rounded,
                      action: ElevatedButton.icon(
                        onPressed: () => _new(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New purchase'),
                      ),
                    )
                  : MinWidthScroller(
                      minWidth: 1020.0,
                      child: Scrollbar(
                        child: ListView.builder(
                          itemCount: _rows.length,
                          itemExtent: 52,
                          itemBuilder: (context, i) => _row(_rows[i], i),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _row(PurchaseDoc d, int index) {
    return InkWell(
      onTap: () => _open(d),
      child: Container(
        decoration: BoxDecoration(
          color: index.isEven
              ? null
              : AppTheme.subtleOf(context).withValues(alpha: 0.5),
          border: Border(
              bottom:
                  BorderSide(color: AppTheme.borderOf(context), width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
                width: 96,
                child: Text(Fmt.date(d.docDate),
                    style: const TextStyle(fontSize: 12.5))),
            SizedBox(
                width: 106,
                child: Text(d.docNo,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700))),
            SizedBox(
                width: 130,
                child: Text(d.supplierBillNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5))),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.partyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(d.partyGstin,
                      style: TextStyle(
                          fontSize: 11,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            SizedBox(
                width: 100,
                child: Money(d.taxableAmount, size: 12.5, symbol: false)),
            SizedBox(
                width: 96, child: Money(d.totalTax, size: 12.5, symbol: false)),
            SizedBox(width: 106, child: Money(d.total, size: 13.5, bold: true)),
            SizedBox(
              width: 96,
              child: Money(d.balance,
                  size: 12.5,
                  symbol: false,
                  color: d.balance > 0.5 ? AppTheme.danger : null),
            ),
            SizedBox(width: 84, child: StatusPill(d.status)),
            SizedBox(
              width: 44,
              child: IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                onPressed: () => _delete(d),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
