import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/backup_repo.dart';
import '../../data/repos/party_repo.dart';
import '../payments/payment_editor.dart';
import '../widgets/common.dart';
import 'ledger_dialog.dart';
import 'party_editor.dart';

class PartiesPage extends StatefulWidget {
  const PartiesPage({super.key, required this.kind});
  final String kind;

  @override
  State<PartiesPage> createState() => _PartiesPageState();
}

class _PartiesPageState extends State<PartiesPage> {
  final _repo = PartyRepo();
  final _search = TextEditingController();

  List<Party> _rows = const [];
  bool _onlyDue = false;
  bool _loading = true;

  bool get _isSupplier => widget.kind == 'SUPPLIER';

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
    final rows = await _repo.all(
      kind: widget.kind,
      query: _search.text,
      onlyActive: false,
      onlyOutstanding: _onlyDue,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  double get _totalDue => _rows.fold<double>(0.0, (s, p) => s + p.balance);

  Future<void> _edit([Party? p]) async {
    final saved = await PartyEditor.show(context, kind: widget.kind, party: p);
    if (saved != null) await _load();
  }

  Future<void> _collect(Party p) async {
    final done = await PaymentEditor.show(
      context,
      party: p,
      direction: _isSupplier ? 'OUT' : 'IN',
    );
    if (done) await _load();
  }

  Future<void> _remove(Party p) async {
    final ok = await confirm(
      context,
      title: 'Remove ${p.name}?',
      message:
          'Parties with transactions are kept for the audit trail and only '
          'marked inactive.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    final msg = await _repo.deleteOrDeactivate(p.id!);
    await _load();
    if (mounted) toast(context, msg);
  }

  Future<void> _export() async {
    final loc = await getSaveLocation(
      suggestedName:
          '${_isSupplier ? 'suppliers' : 'customers'}_${Fmt.stamp(DateTime.now())}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (loc == null) return;
    await BackupRepo().exportParties(loc.path, _rows);
    if (!mounted) return;
    toast(context, 'Exported ${_rows.length} records.', success: true);
  }

  Future<void> _recalculate() async {
    final n = await _repo.recalculateBalances();
    await _load();
    if (mounted) {
      toast(
          context,
          n == 0
              ? 'All balances already match the vouchers.'
              : 'Corrected $n balances.',
          success: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Field(
                  label:
                      'Search ${_isSupplier ? 'suppliers' : 'customers'} by name, phone, code or GSTIN',
                  controller: _search,
                  prefix: const Icon(Icons.search_rounded, size: 18),
                  onChanged: (_) => _load(),
                ),
              ),
              const SizedBox(width: 10),
              FilterChip(
                selected: _onlyDue,
                onSelected: (v) {
                  setState(() => _onlyDue = v);
                  _load();
                },
                avatar: const Icon(Icons.error_outline_rounded, size: 15),
                label: Text(_isSupplier ? 'With payable' : 'With dues'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text('New ${_isSupplier ? 'supplier' : 'customer'}'),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) async {
                  if (v == 'export') await _export();
                  if (v == 'recalc') await _recalculate();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'export', child: Text('Export to CSV')),
                  PopupMenuItem(
                      value: 'recalc', child: Text('Recalculate all balances')),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          color: AppTheme.subtleOf(context),
          child: Row(
            children: [
              Text('${_rows.length} ${_isSupplier ? 'suppliers' : 'customers'}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 22),
              Text(_isSupplier ? 'Total payable: ' : 'Total receivable: ',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              Money(_totalDue,
                  size: 13,
                  bold: true,
                  color: _totalDue > 0.5 ? AppTheme.danger : null),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? EmptyState(
                      title:
                          'No ${_isSupplier ? 'suppliers' : 'customers'} yet',
                      message: _isSupplier
                          ? 'Add the dealers and depots you buy stock from.'
                          : 'Walk-in sales work without adding anyone. Add '
                              'regular customers, dealers and contractors to '
                              'track their dues.',
                      icon: Icons.people_alt_rounded,
                      action: ElevatedButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add now'),
                      ),
                    )
                  : Scrollbar(
                      child: ListView.builder(
                        itemCount: _rows.length,
                        itemExtent: 56,
                        itemBuilder: (context, i) => _row(_rows[i], i),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _row(Party p, int index) {
    return InkWell(
      onTap: () => LedgerDialog.show(context, p),
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
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.subtleOf(context),
              child: Text(
                p.name.isEmpty ? '?' : p.name.characters.first.toUpperCase(),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              decoration:
                                  p.active ? null : TextDecoration.lineThrough,
                            )),
                      ),
                      if (p.priceTier != 'RETAIL' && !_isSupplier) ...[
                        const SizedBox(width: 6),
                        StatusPill(p.priceTier, color: AppTheme.info),
                      ],
                    ],
                  ),
                  Text(
                    [
                      p.code,
                      if (p.phone.isNotEmpty) p.phone,
                      if (p.gstin.isNotEmpty) p.gstin,
                      if (p.city.isNotEmpty) p.city,
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
            SizedBox(
              width: 120,
              child: p.creditLimit == 0
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Limit',
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                        Money(p.creditLimit, size: 12, symbol: false),
                      ],
                    ),
            ),
            SizedBox(
              width: 130,
              child: Money(
                p.balance,
                size: 14,
                bold: true,
                color: p.balance > 0.5
                    ? AppTheme.danger
                    : (p.balance < -0.5 ? AppTheme.success : null),
              ),
            ),
            SizedBox(
              width: 132,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: _isSupplier ? 'Pay supplier' : 'Collect payment',
                    icon: const Icon(Icons.payments_rounded, size: 17),
                    onPressed: () => _collect(p),
                  ),
                  IconButton(
                    tooltip: 'Statement',
                    icon: const Icon(Icons.receipt_long_rounded, size: 17),
                    onPressed: () => LedgerDialog.show(context, p),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    onPressed: () => _edit(p),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    onPressed: () => _remove(p),
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
