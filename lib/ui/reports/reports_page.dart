import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/repos/backup_repo.dart';
import '../../data/repos/purchase_repo.dart';
import '../../data/repos/report_repo.dart';
import '../../data/repos/sales_repo.dart';
import '../../print/print_service.dart';
import '../../print/report_pdf.dart';
import '../../state/app_state.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'expenses_view.dart';

/// A generic, printable table used by every report in this screen.
class ReportData {
  final String title;
  final String subtitle;
  final List<ReportColumn> columns;
  final List<List<String>> rows;
  final List<String>? totals;
  final bool landscape;
  final List<String> notes;

  const ReportData({
    required this.title,
    this.subtitle = '',
    required this.columns,
    required this.rows,
    this.totals,
    this.landscape = false,
    this.notes = const [],
  });
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _sales = SalesRepo();
  final _purchases = PurchaseRepo();
  final _reports = ReportRepo();

  int _index = 0;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _loading = true;

  ReportData? _table;
  Map<String, double> _summary = const {};
  Map<String, double> _profit = const {};
  Map<String, double> _purchaseSummary = const {};
  double _expenses = 0;
  List<ChartPoint> _trend = const [];
  List<ChartPoint> _topItems = const [];
  List<ChartPoint> _topCustomers = const [];
  Gstr3B? _gstr3b;
  DaySummary? _day;

  static const _menu = <(String, IconData)>[
    ('Sales summary', Icons.insights_rounded),
    ('Sales register', Icons.receipt_long_rounded),
    ('GSTR-1 · B2B', Icons.business_center_rounded),
    ('GSTR-1 · B2C', Icons.people_alt_rounded),
    ('GSTR-1 · HSN summary', Icons.qr_code_2_rounded),
    ('GSTR-3B summary', Icons.account_balance_rounded),
    ('Purchase register', Icons.local_shipping_rounded),
    ('Item-wise sales & profit', Icons.trending_up_rounded),
    ('Outstanding & ageing', Icons.schedule_rounded),
    ('Day close (Z report)', Icons.point_of_sale_rounded),
    ('Expenses', Icons.payments_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _table = null;
    try {
      switch (_index) {
        case 0:
          await _loadSummary();
        case 1:
          await _loadSalesRegister();
        case 2:
          await _loadB2B();
        case 3:
          await _loadB2C();
        case 4:
          await _loadHsn();
        case 5:
          await _loadGstr3b();
        case 6:
          await _loadPurchaseRegister();
        case 7:
          await _loadItemWise();
        case 8:
          await _loadAgeing();
        case 9:
          await _loadDayClose();
        case 10:
          break; // expenses view manages its own data
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------------
  // Report builders
  // ------------------------------------------------------------------
  Future<void> _loadSummary() async {
    final summary = await _sales.summary(from: _from, to: _to);
    final profit = await _sales.profit(from: _from, to: _to);
    final purchases = await _purchases.summary(from: _from, to: _to);
    final expenses = await _reports.expenseTotal(_from, _to);
    final daily = await _sales.daily(from: _from, to: _to);
    final items = await _sales.topProducts(from: _from, to: _to, limit: 8);
    final customers = await _sales.topCustomers(from: _from, to: _to, limit: 8);
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _profit = profit;
      _purchaseSummary = purchases;
      _expenses = expenses;
      _trend = daily
          .map((d) => ChartPoint('${d.day.day}/${d.day.month}', d.total))
          .toList();
      _topItems = items
          .map((r) =>
              ChartPoint((r['name'] ?? '') as String, Fmt.toDouble(r['value'])))
          .toList();
      _topCustomers = customers
          .map((r) =>
              ChartPoint((r['name'] ?? '') as String, Fmt.toDouble(r['value'])))
          .toList();
    });
  }

  Future<void> _loadSalesRegister() async {
    final rows = await _reports.salesRegister(_from, _to);
    _table = ReportData(
      title: 'Sales Register',
      subtitle: '${Fmt.date(_from)} to ${Fmt.date(_to)}',
      landscape: true,
      columns: const [
        ReportColumn('Date', flex: 1.1),
        ReportColumn('Bill No', flex: 1.3),
        ReportColumn('Type', flex: 1.1),
        ReportColumn('Party', flex: 2.6),
        ReportColumn('GSTIN', flex: 1.8),
        ReportColumn('Taxable', flex: 1.2, numeric: true),
        ReportColumn('CGST', flex: 1, numeric: true),
        ReportColumn('SGST', flex: 1, numeric: true),
        ReportColumn('IGST', flex: 1, numeric: true),
        ReportColumn('Total', flex: 1.3, numeric: true),
        ReportColumn('Status', flex: 1),
      ],
      rows: rows
          .map((r) => [
                Fmt.date(Fmt.parseIso(r['doc_date'] as String?)),
                (r['doc_no'] ?? '') as String,
                r['doc_type'] == 'CREDIT_NOTE' ? 'C/Note' : 'Invoice',
                (r['party_name'] ?? '') as String,
                (r['party_gstin'] ?? '') as String,
                Fmt.amount(Fmt.toDouble(r['taxable_amount'])),
                Fmt.amount(Fmt.toDouble(r['cgst'])),
                Fmt.amount(Fmt.toDouble(r['sgst'])),
                Fmt.amount(Fmt.toDouble(r['igst'])),
                Fmt.amount(Fmt.toDouble(r['total'])),
                (r['status'] ?? '') as String,
              ])
          .toList(),
      totals: [
        '',
        '',
        '',
        '${rows.length} documents',
        '',
        Fmt.amount(rows.fold<double>(
            0.0, (s, r) => s + Fmt.toDouble(r['taxable_amount']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['cgst']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['sgst']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['igst']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['total']))),
        '',
      ],
    );
  }

  Future<void> _loadB2B() async {
    final rows = await _reports.gstr1B2B(_from, _to);
    _table = ReportData(
      title: 'GSTR-1 · Table 4 — B2B Supplies',
      subtitle: '${Fmt.date(_from)} to ${Fmt.date(_to)}',
      landscape: true,
      columns: const [
        ReportColumn('GSTIN of recipient', flex: 2),
        ReportColumn('Receiver name', flex: 2.4),
        ReportColumn('Invoice No', flex: 1.4),
        ReportColumn('Date', flex: 1.1),
        ReportColumn('POS', flex: 0.8),
        ReportColumn('Rev. chg', flex: 0.8),
        ReportColumn('Taxable', flex: 1.3, numeric: true),
        ReportColumn('CGST', flex: 1.1, numeric: true),
        ReportColumn('SGST', flex: 1.1, numeric: true),
        ReportColumn('IGST', flex: 1.1, numeric: true),
        ReportColumn('Invoice value', flex: 1.4, numeric: true),
      ],
      rows: rows
          .map((r) => [
                r.gstin,
                r.name,
                r.docNo,
                Fmt.date(r.date),
                r.pos,
                'N',
                Fmt.amount(r.taxable),
                Fmt.amount(r.cgst),
                Fmt.amount(r.sgst),
                Fmt.amount(r.igst),
                Fmt.amount(r.total),
              ])
          .toList(),
      totals: [
        '${rows.length} invoices',
        '',
        '',
        '',
        '',
        '',
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.taxable)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.cgst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.sgst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.igst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.total)),
      ],
      notes: const [
        'Credit notes are shown as negative values against the original month.',
        'Reverse charge is reported as "N" — change it on the portal if a '
            'specific supply attracts RCM.',
      ],
    );
  }

  Future<void> _loadB2C() async {
    final rows = await _reports.gstr1B2C(_from, _to);
    _table = ReportData(
      title: 'GSTR-1 · Table 7 — B2C (Small) Supplies',
      subtitle: '${Fmt.date(_from)} to ${Fmt.date(_to)}',
      columns: const [
        ReportColumn('Place of supply', flex: 2),
        ReportColumn('Rate %', flex: 1, numeric: true),
        ReportColumn('Taxable value', flex: 1.6, numeric: true),
        ReportColumn('CGST', flex: 1.3, numeric: true),
        ReportColumn('SGST', flex: 1.3, numeric: true),
        ReportColumn('IGST', flex: 1.3, numeric: true),
        ReportColumn('Total', flex: 1.5, numeric: true),
      ],
      rows: rows
          .map((r) => [
                '${r.pos} · ${_stateName(r.pos)}',
                Fmt.qty(r.rate),
                Fmt.amount(r.taxable),
                Fmt.amount(r.cgst),
                Fmt.amount(r.sgst),
                Fmt.amount(r.igst),
                Fmt.amount(r.total),
              ])
          .toList(),
      totals: [
        'Total',
        '',
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.taxable)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.cgst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.sgst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.igst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.total)),
      ],
    );
  }

  Future<void> _loadHsn() async {
    final rows = await _reports.hsnSummary(_from, _to);
    _table = ReportData(
      title: 'GSTR-1 · Table 12 — HSN Summary',
      subtitle: '${Fmt.date(_from)} to ${Fmt.date(_to)}',
      columns: const [
        ReportColumn('HSN', flex: 1.2),
        ReportColumn('UQC', flex: 0.9),
        ReportColumn('Rate %', flex: 0.9, numeric: true),
        ReportColumn('Total quantity', flex: 1.3, numeric: true),
        ReportColumn('Taxable value', flex: 1.6, numeric: true),
        ReportColumn('CGST', flex: 1.2, numeric: true),
        ReportColumn('SGST', flex: 1.2, numeric: true),
        ReportColumn('IGST', flex: 1.2, numeric: true),
        ReportColumn('Total', flex: 1.5, numeric: true),
      ],
      rows: rows
          .map((r) => [
                r.hsn,
                r.unit,
                Fmt.qty(r.rate),
                Fmt.qty(r.qty),
                Fmt.amount(r.taxable),
                Fmt.amount(r.cgst),
                Fmt.amount(r.sgst),
                Fmt.amount(r.igst),
                Fmt.amount(r.total),
              ])
          .toList(),
      totals: [
        'Total',
        '',
        '',
        Fmt.qty(rows.fold<double>(0.0, (s, r) => s + r.qty)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.taxable)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.cgst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.sgst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.igst)),
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.total)),
      ],
      notes: const [
        'HSN reporting is mandatory at 4 digits for turnover up to Rs. 5 crore '
            'and 6 digits above it.',
      ],
    );
  }

  Future<void> _loadGstr3b() async {
    final g = await _reports.gstr3b(_from, _to);
    if (!mounted) return;
    setState(() => _gstr3b = g);
  }

  Future<void> _loadPurchaseRegister() async {
    final rows = await _reports.purchaseRegister(_from, _to);
    _table = ReportData(
      title: 'Purchase Register',
      subtitle: '${Fmt.date(_from)} to ${Fmt.date(_to)}',
      landscape: true,
      columns: const [
        ReportColumn('Date', flex: 1.1),
        ReportColumn('Our No', flex: 1.2),
        ReportColumn('Supplier bill', flex: 1.4),
        ReportColumn('Supplier', flex: 2.6),
        ReportColumn('GSTIN', flex: 1.8),
        ReportColumn('Taxable', flex: 1.2, numeric: true),
        ReportColumn('CGST', flex: 1, numeric: true),
        ReportColumn('SGST', flex: 1, numeric: true),
        ReportColumn('IGST', flex: 1, numeric: true),
        ReportColumn('Total', flex: 1.3, numeric: true),
        ReportColumn('Due', flex: 1.2, numeric: true),
      ],
      rows: rows
          .map((r) => [
                Fmt.date(Fmt.parseIso(r['doc_date'] as String?)),
                (r['doc_no'] ?? '') as String,
                (r['supplier_bill_no'] ?? '') as String,
                (r['party_name'] ?? '') as String,
                (r['party_gstin'] ?? '') as String,
                Fmt.amount(Fmt.toDouble(r['taxable_amount'])),
                Fmt.amount(Fmt.toDouble(r['cgst'])),
                Fmt.amount(Fmt.toDouble(r['sgst'])),
                Fmt.amount(Fmt.toDouble(r['igst'])),
                Fmt.amount(Fmt.toDouble(r['total'])),
                Fmt.amount(Fmt.toDouble(r['balance'])),
              ])
          .toList(),
      totals: [
        '',
        '',
        '',
        '${rows.length} bills',
        '',
        Fmt.amount(rows.fold<double>(
            0.0, (s, r) => s + Fmt.toDouble(r['taxable_amount']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['cgst']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['sgst']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['igst']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['total']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['balance']))),
      ],
    );
  }

  Future<void> _loadItemWise() async {
    final rows = await _reports.itemWiseSales(_from, _to);
    _table = ReportData(
      title: 'Item-wise Sales & Profit',
      subtitle: '${Fmt.date(_from)} to ${Fmt.date(_to)}',
      landscape: true,
      columns: const [
        ReportColumn('Code', flex: 1.1),
        ReportColumn('Item', flex: 3.4),
        ReportColumn('HSN', flex: 1),
        ReportColumn('Qty', flex: 1.1, numeric: true),
        ReportColumn('Taxable', flex: 1.4, numeric: true),
        ReportColumn('Tax', flex: 1.2, numeric: true),
        ReportColumn('Total', flex: 1.4, numeric: true),
        ReportColumn('Cost', flex: 1.3, numeric: true),
        ReportColumn('Profit', flex: 1.3, numeric: true),
      ],
      rows: rows
          .map((r) => [
                (r['sku'] ?? '') as String,
                (r['name'] ?? '') as String,
                (r['hsn'] ?? '') as String,
                '${Fmt.qty(Fmt.toDouble(r['qty']))} ${r['unit'] ?? ''}',
                Fmt.amount(Fmt.toDouble(r['taxable'])),
                Fmt.amount(Fmt.toDouble(r['tax'])),
                Fmt.amount(Fmt.toDouble(r['total'])),
                Fmt.amount(Fmt.toDouble(r['cost'])),
                Fmt.amount(Fmt.toDouble(r['profit'])),
              ])
          .toList(),
      totals: [
        '',
        '${rows.length} items',
        '',
        '',
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['taxable']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['tax']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['total']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['cost']))),
        Fmt.amount(
            rows.fold<double>(0.0, (s, r) => s + Fmt.toDouble(r['profit']))),
      ],
      notes: const [
        'Profit uses the purchase price captured on each bill line, so past '
            'margins are not disturbed by later price changes.',
      ],
    );
  }

  Future<void> _loadAgeing() async {
    final rows = await _reports.receivablesAgeing();
    _table = ReportData(
      title: 'Outstanding Receivables — Ageing',
      subtitle: 'As on ${Fmt.date(DateTime.now())}',
      columns: const [
        ReportColumn('Bill No', flex: 1.3),
        ReportColumn('Date', flex: 1.1),
        ReportColumn('Customer', flex: 3),
        ReportColumn('Phone', flex: 1.4),
        ReportColumn('Bill value', flex: 1.4, numeric: true),
        ReportColumn('Outstanding', flex: 1.4, numeric: true),
        ReportColumn('Days', flex: 0.9, numeric: true),
        ReportColumn('Bucket', flex: 1.3),
      ],
      rows: rows
          .map((r) => [
                r.docNo,
                Fmt.date(r.date),
                r.partyName,
                r.partyPhone,
                Fmt.amount(r.total),
                Fmt.amount(r.balance),
                '${r.days}',
                r.bucket,
              ])
          .toList(),
      totals: [
        '',
        '',
        '${rows.length} bills',
        '',
        '',
        Fmt.amount(rows.fold<double>(0.0, (s, r) => s + r.balance)),
        '',
        '',
      ],
    );
  }

  Future<void> _loadDayClose() async {
    final day = await _reports.dayBook(_to);
    if (!mounted) return;
    setState(() => _day = day);
  }

  static String _stateName(String code) =>
      code.isEmpty ? 'Not set' : IndianStates.name(code);

  // ------------------------------------------------------------------
  // Export / print
  // ------------------------------------------------------------------
  Future<void> _print() async {
    final t = _table;
    if (t == null) return;
    final app = context.read<AppState>();
    final bytes = await ReportPdf.table(
      company: app.company,
      title: t.title,
      subtitle: t.subtitle,
      columns: t.columns,
      rows: t.rows,
      totalsRow: t.totals,
      landscape: t.landscape,
      notes: t.notes,
    );
    if (!mounted) return;
    await PrintService.previewBytes(
      context,
      title: t.title,
      bytes: bytes,
      fileName:
          '${t.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.pdf',
    );
  }

  Future<void> _export() async {
    final t = _table;
    if (t == null) return;
    final loc = await getSaveLocation(
      suggestedName:
          '${t.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (loc == null) return;
    await BackupRepo().exportRows(
      loc.path,
      t.columns.map((c) => c.title).toList(),
      t.rows.map((r) => r.cast<Object?>()).toList(),
    );
    if (!mounted) return;
    toast(context, 'Exported ${t.rows.length} rows.', success: true);
  }

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 232,
          child: Container(
            color: AppTheme.subtleOf(context),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _menu.length,
              itemBuilder: (context, i) {
                final selected = i == _index;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  child: Material(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        setState(() => _index = i);
                        _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Row(
                          children: [
                            Icon(_menu[i].$2,
                                size: 17,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _menu[i].$1,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Container(width: 1, color: AppTheme.borderOf(context)),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: DateRangeBar(
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
                    ),
                    if (_table != null) ...[
                      OutlinedButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: const Text('CSV'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _print,
                        icon: const Icon(Icons.print_rounded, size: 17),
                        label: const Text('Print / PDF'),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _body(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_index == 0) return _summaryView();
    if (_index == 5) return _gstr3bView();
    if (_index == 9) return _dayCloseView();
    if (_index == 10) return ExpensesView(from: _from, to: _to);
    return _tableView();
  }

  Widget _tableView() {
    final t = _table;
    if (t == null || t.rows.isEmpty) {
      return const EmptyState(
        title: 'Nothing to report for this period',
        message: 'Change the date range and try again.',
        icon: Icons.insights_rounded,
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Text(t.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Text(t.subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text('${t.rows.length} rows',
                  style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        Expanded(
          child: ScrollableTable(
            minWidth: t.landscape ? 1400 : 900,
            child: Column(
              children: [
                _tableHeader(t),
                Expanded(
                  child: ListView.builder(
                    itemCount: t.rows.length,
                    itemExtent: 34,
                    itemBuilder: (context, i) => _tableRow(t, t.rows[i], i),
                  ),
                ),
                if (t.totals != null) _tableTotals(t),
              ],
            ),
          ),
        ),
        if (t.notes.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: AppTheme.subtleOf(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in t.notes)
                  Text('· $n',
                      style: TextStyle(
                          fontSize: 11.5,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _tableHeader(ReportData t) => Container(
        color: AppTheme.subtleOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            for (final c in t.columns)
              Expanded(
                flex: (c.flex * 10).round(),
                child: Text(
                  c.title,
                  textAlign: c.numeric ? TextAlign.right : TextAlign.left,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _tableRow(ReportData t, List<String> row, int index) => Container(
        decoration: BoxDecoration(
          color: index.isEven
              ? null
              : AppTheme.subtleOf(context).withValues(alpha: 0.45),
          border: Border(
              bottom:
                  BorderSide(color: AppTheme.borderOf(context), width: 0.4)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            for (var i = 0; i < t.columns.length; i++)
              Expanded(
                flex: (t.columns[i].flex * 10).round(),
                child: Text(
                  i < row.length ? row[i] : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign:
                      t.columns[i].numeric ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      );

  Widget _tableTotals(ReportData t) => Container(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.09),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            for (var i = 0; i < t.columns.length; i++)
              Expanded(
                flex: (t.columns[i].flex * 10).round(),
                child: Text(
                  i < t.totals!.length ? t.totals![i] : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign:
                      t.columns[i].numeric ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      );

  Widget _summaryView() {
    final net = (_summary['total'] ?? 0);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3.2,
          children: [
            StatTile(
                label: 'Sales',
                value: Fmt.money(net),
                sub: '${Fmt.compact(_summary['bills'] ?? 0)} bills',
                icon: Icons.receipt_long_rounded),
            StatTile(
                label: 'Taxable value',
                value: Fmt.money(_summary['taxable'] ?? 0),
                icon: Icons.calculate_rounded,
                tint: AppTheme.info),
            StatTile(
                label: 'GST collected',
                value: Fmt.money(_summary['tax'] ?? 0),
                icon: Icons.account_balance_rounded,
                tint: AppTheme.warning),
            StatTile(
                label: 'Discounts given',
                value: Fmt.money(_summary['discount'] ?? 0),
                icon: Icons.percent_rounded),
            StatTile(
                label: 'Gross profit',
                value: Fmt.money(_profit['profit'] ?? 0),
                sub: '${Fmt.qty(_profit['margin'] ?? 0)}% margin',
                icon: Icons.trending_up_rounded,
                tint: AppTheme.success),
            StatTile(
                label: 'Purchases',
                value: Fmt.money(_purchaseSummary['total'] ?? 0),
                icon: Icons.local_shipping_rounded),
            StatTile(
                label: 'Expenses',
                value: Fmt.money(_expenses),
                icon: Icons.payments_rounded,
                tint: AppTheme.danger),
            StatTile(
                label: 'Net profit (approx.)',
                value: Fmt.money((_profit['profit'] ?? 0) - _expenses),
                sub: 'gross profit less expenses',
                icon: Icons.savings_rounded,
                tint: AppTheme.success),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Daily sales', icon: Icons.bar_chart_rounded),
              BarChart(points: _trend, height: 210),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle('Top items',
                        icon: Icons.local_fire_department_rounded),
                    RankedBars(points: _topItems),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle('Top customers',
                        icon: Icons.emoji_events_rounded),
                    RankedBars(points: _topCustomers),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _gstr3bView() {
    final g = _gstr3b;
    if (g == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('3.1 (a) — Outward taxable supplies',
                  icon: Icons.upload_rounded),
              _gstRow('Total taxable value', g.outwardTaxable),
              _gstRow('Integrated tax (IGST)', g.outIgst),
              _gstRow('Central tax (CGST)', g.outCgst),
              _gstRow('State tax (SGST)', g.outSgst),
              _gstRow('Cess', g.outCess),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('4 (A)(5) — Input tax credit available',
                  icon: Icons.download_rounded),
              _gstRow('Total inward taxable value', g.inwardTaxable),
              _gstRow('Integrated tax (IGST)', g.itcIgst),
              _gstRow('Central tax (CGST)', g.itcCgst),
              _gstRow('State tax (SGST)', g.itcSgst),
              _gstRow('Cess', g.itcCess),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Net position', icon: Icons.balance_rounded),
              _gstRow('Output tax', g.outputTax),
              _gstRow('Less: input tax credit', g.inputTax),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    g.netPayable >= 0
                        ? 'Tax payable in cash'
                        : 'Credit carried forward',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  Money(g.netPayable.abs(),
                      size: 20,
                      bold: true,
                      color: g.netPayable >= 0
                          ? AppTheme.danger
                          : AppTheme.success),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'These figures come from your own books. Reconcile them with '
                'GSTR-2B on the portal before filing — ITC is allowed only on '
                'invoices your suppliers have actually reported.',
                style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _gstRow(String k, double v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 13)),
            Money(v, size: 13.5, bold: true),
          ],
        ),
      );

  Widget _dayCloseView() {
    final d = _day;
    if (d == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Day close for ${Fmt.date(d.day)}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: () async {
                final app = context.read<AppState>();
                final bytes = await ReportPdf.dayClose(
                  company: app.company,
                  day: d.day,
                  bills: d.bills,
                  sales: d.salesTotal,
                  returns: d.returns,
                  collected: d.collected,
                  credit: d.creditGiven,
                  expenses: d.expenses,
                  byMode: d.collectionByMode,
                  user: app.user?.name ?? '',
                );
                if (!mounted) return;
                await PrintService.previewBytes(
                  context,
                  title: 'Day close',
                  bytes: bytes,
                  fileName: 'day_close_${Fmt.iso(d.day)}.pdf',
                );
              },
              icon: const Icon(Icons.print_rounded, size: 17),
              label: const Text('Print Z report'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3.2,
          children: [
            StatTile(
                label: 'Bills issued',
                value: '${d.bills}',
                icon: Icons.receipt_rounded),
            StatTile(
                label: 'Gross sales',
                value: Fmt.money(d.salesTotal),
                icon: Icons.point_of_sale_rounded),
            StatTile(
                label: 'Returns',
                value: Fmt.money(d.returns),
                icon: Icons.undo_rounded,
                tint: AppTheme.warning),
            StatTile(
                label: 'Collected',
                value: Fmt.money(d.collected),
                icon: Icons.call_received_rounded,
                tint: AppTheme.success),
            StatTile(
                label: 'Credit given',
                value: Fmt.money(d.creditGiven),
                icon: Icons.schedule_rounded,
                tint: AppTheme.danger),
            StatTile(
                label: 'Expenses',
                value: Fmt.money(d.expenses),
                icon: Icons.payments_rounded),
          ],
        ),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('Collection by mode',
                  icon: Icons.account_balance_wallet_rounded),
              if (d.collectionByMode.isEmpty)
                const Text('Nothing collected today.',
                    style: TextStyle(fontSize: 12.5))
              else
                for (final e in d.collectionByMode.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(e.key, style: const TextStyle(fontSize: 13)),
                        Money(e.value, size: 13.5, bold: true),
                      ],
                    ),
                  ),
              const Divider(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cash that should be in the till',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Money(d.cashInHand, size: 20, bold: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
