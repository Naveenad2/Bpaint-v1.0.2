import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/product_repo.dart';
import '../../data/repos/report_repo.dart';
import '../../print/print_service.dart';
import '../../print/report_pdf.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _repo = ProductRepo();
  final _reports = ReportRepo();
  final _search = TextEditingController();

  int _tab = 0;
  List<Product> _rows = const [];
  List<Map<String, Object?>> _dead = const [];
  double _cost = 0;
  double _sale = 0;
  double _qty = 0;
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
    final rows = await _repo.all(
      query: _search.text,
      onlyLowStock: _tab == 1,
      limit: 4000,
    );
    final (c, s, q) = await _repo.valuation();
    final dead = _tab == 2 ? await _reports.deadStock(days: 90) : _dead;
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _cost = c;
      _sale = s;
      _qty = q;
      _dead = dead;
      _loading = false;
    });
  }

  Future<void> _adjust(Product p) async {
    final qty = TextEditingController(text: Fmt.qty(p.stock));
    final reason = TextEditingController();
    var refType = StockRef.adjustment;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Adjust stock — ${p.fullName}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'System stock is ${Fmt.qty(p.stock)} ${p.unit}. '
                  'Enter what you actually counted on the shelf.',
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Field(
                  label: 'Counted quantity',
                  controller: qty,
                  autofocus: true,
                  inputFormatters: Field.decimal,
                ),
                const SizedBox(height: 12),
                Picker<String>(
                  label: 'Reason',
                  value: refType,
                  items: const [
                    DropdownMenuItem(
                        value: StockRef.adjustment,
                        child: Text('Physical count correction')),
                    DropdownMenuItem(
                        value: StockRef.damage,
                        child: Text('Damage / leakage / expiry')),
                    DropdownMenuItem(
                        value: StockRef.opening,
                        child: Text('Opening stock entry')),
                  ],
                  onChanged: (v) =>
                      setLocal(() => refType = v ?? StockRef.adjustment),
                ),
                const SizedBox(height: 12),
                Field(label: 'Remark', controller: reason),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apply')),
          ],
        ),
      ),
    );

    final newQty = Fmt.toDouble(qty.text, p.stock);
    final note = reason.text.trim();
    qty.dispose();
    reason.dispose();
    if (ok != true) return;

    await _repo.adjust(
      product: p,
      newQty: newQty,
      reason: note.isEmpty ? 'Stock adjusted' : note,
      refType: refType,
    );
    await _load();
    if (mounted) {
      await context.read<AppState>().refreshAlerts();
      if (mounted) toast(context, 'Stock updated.', success: true);
    }
  }

  Future<void> _history(Product p) async {
    final moves = await _repo.moves(p.id!);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                icon: Icons.history_rounded,
                title: 'Stock ledger — ${p.fullName}',
                subtitle: 'Current balance ${Fmt.qty(p.stock)} ${p.unit}',
              ),
              const Divider(height: 1),
              Expanded(
                child: moves.isEmpty
                    ? const EmptyState(
                        title: 'No movement recorded yet',
                        icon: Icons.timeline_rounded)
                    : ListView.builder(
                        itemCount: moves.length,
                        itemExtent: 46,
                        itemBuilder: (context, i) {
                          final m = moves[i];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: AppTheme.borderOf(context),
                                      width: 0.4)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                    width: 130,
                                    child: Text(Fmt.dateTime(m.date),
                                        style: const TextStyle(fontSize: 12))),
                                SizedBox(
                                    width: 130,
                                    child: Text(m.refType,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600))),
                                SizedBox(
                                    width: 110,
                                    child: Text(m.refNo,
                                        style: const TextStyle(fontSize: 12))),
                                Expanded(
                                    child: Text(m.notes,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            const TextStyle(fontSize: 11.5))),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                      m.qtyIn > 0 ? '+${Fmt.qty(m.qtyIn)}' : '',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.success)),
                                ),
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                      m.qtyOut > 0
                                          ? '-${Fmt.qty(m.qtyOut)}'
                                          : '',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.danger)),
                                ),
                                SizedBox(
                                  width: 80,
                                  child: Text(Fmt.qty(m.balanceAfter),
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700)),
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
      ),
    );
  }

  Future<void> _printStock() async {
    final app = context.read<AppState>();
    final rows = _tab == 2
        ? _dead
            .map((r) => [
                  (r['sku'] ?? '') as String,
                  (r['name'] ?? '') as String,
                  (r['brand'] ?? '') as String,
                  Fmt.qty(Fmt.toDouble(r['stock'])),
                  Fmt.amount(Fmt.toDouble(r['cost_value'])),
                  r['last_sold'] == null
                      ? 'never'
                      : Fmt.date(Fmt.parseIso(r['last_sold'] as String)),
                ])
            .toList()
        : _rows
            .map((p) => [
                  p.sku,
                  p.fullName,
                  p.brand,
                  '${Fmt.qty(p.stock)} ${p.unit}',
                  Fmt.amount(p.stock * p.purchasePrice),
                  Fmt.qty(p.minStock),
                ])
            .toList();

    final bytes = await ReportPdf.table(
      company: app.company,
      title: _tab == 2 ? 'Dead Stock Report' : 'Stock Report',
      subtitle: 'As on ${Fmt.date(DateTime.now())}',
      columns: [
        const ReportColumn('Code', flex: 1.2),
        const ReportColumn('Item', flex: 4),
        const ReportColumn('Brand', flex: 1.6),
        const ReportColumn('Stock', flex: 1.2, numeric: true),
        const ReportColumn('Value at cost', flex: 1.4, numeric: true),
        ReportColumn(_tab == 2 ? 'Last sold' : 'Reorder at',
            flex: 1.2, numeric: _tab != 2),
      ],
      rows: rows,
      totalsRow: [
        '',
        '${rows.length} items',
        '',
        '',
        Fmt.amount(_tab == 2
            ? _dead.fold<double>(
                0.0, (s, r) => s + Fmt.toDouble(r['cost_value']))
            : _rows.fold<double>(0.0, (s, p) => s + p.stock * p.purchasePrice)),
        '',
      ],
    );
    if (!mounted) return;
    await PrintService.previewBytes(
      context,
      title: 'Stock report',
      bytes: bytes,
      fileName: 'stock_report.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('All stock')),
                  ButtonSegment(value: 1, label: Text('Low stock')),
                  ButtonSegment(value: 2, label: Text('Dead stock')),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _tab = s.first);
                  _load();
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Field(
                  label: 'Search items',
                  controller: _search,
                  prefix: const Icon(Icons.search_rounded, size: 18),
                  onChanged: (_) => _load(),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _printStock,
                icon: const Icon(Icons.print_rounded, size: 17),
                label: const Text('Print report'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Stock value at cost',
                  value: Fmt.money(_cost),
                  icon: Icons.savings_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Value at selling price',
                  value: Fmt.money(_sale),
                  sub: 'Potential margin ${Fmt.money(_sale - _cost)}',
                  icon: Icons.sell_rounded,
                  tint: AppTheme.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Total units in hand',
                  value: Fmt.qty(_qty),
                  icon: Icons.inventory_rounded,
                  tint: AppTheme.info,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _tab == 2
                  ? _deadList()
                  : _rows.isEmpty
                      ? EmptyState(
                          title: _tab == 1
                              ? 'Nothing is below its reorder level'
                              : 'No items found',
                          message: _tab == 1
                              ? 'Set a reorder level on each item to get '
                                  'early warnings here.'
                              : 'Add items from the Products screen.',
                          icon: Icons.inventory_2_rounded,
                        )
                      : Scrollbar(
                          child: ListView.builder(
                            itemCount: _rows.length,
                            itemExtent: 52,
                            itemBuilder: (context, i) => _row(_rows[i], i),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _deadList() {
    if (_dead.isEmpty) {
      return const EmptyState(
        title: 'No dead stock',
        message: 'Every item in stock has sold in the last 90 days.',
        icon: Icons.check_circle_outline_rounded,
      );
    }
    return ListView.builder(
      itemCount: _dead.length,
      itemExtent: 50,
      itemBuilder: (context, i) {
        final r = _dead[i];
        final lastSold = r['last_sold'] as String?;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
                bottom:
                    BorderSide(color: AppTheme.borderOf(context), width: 0.5)),
          ),
          child: Row(
            children: [
              SizedBox(
                  width: 100,
                  child: Text((r['sku'] ?? '') as String,
                      style: const TextStyle(fontSize: 12))),
              Expanded(
                  child: Text((r['name'] ?? '') as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
              SizedBox(
                width: 150,
                child: Text(
                  lastSold == null
                      ? 'Never sold'
                      : 'Last sold ${Fmt.date(Fmt.parseIso(lastSold))}',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
              SizedBox(
                  width: 100,
                  child: Text(Fmt.qty(Fmt.toDouble(r['stock'])),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700))),
              SizedBox(
                  width: 120,
                  child: Money(Fmt.toDouble(r['cost_value']), size: 13)),
            ],
          ),
        );
      },
    );
  }

  Widget _row(Product p, int index) {
    final out = p.stock <= 0;
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
          Container(
            width: 4,
            height: 26,
            decoration: BoxDecoration(
              color: out
                  ? AppTheme.danger
                  : (p.lowStock ? AppTheme.warning : AppTheme.success),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  [
                    p.sku,
                    if (p.rack.isNotEmpty) 'Rack ${p.rack}',
                    'Reorder at ${Fmt.qty(p.minStock)}',
                  ].join('  ·  '),
                  style: TextStyle(
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Text('${Fmt.qty(p.stock)} ${p.unit}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: out
                      ? AppTheme.danger
                      : (p.lowStock ? AppTheme.warning : null),
                )),
          ),
          SizedBox(
              width: 120, child: Money(p.stock * p.purchasePrice, size: 12.5)),
          SizedBox(
            width: 96,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Adjust stock',
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  onPressed: () => _adjust(p),
                ),
                IconButton(
                  tooltip: 'Stock ledger',
                  icon: const Icon(Icons.history_rounded, size: 17),
                  onPressed: () => _history(p),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
