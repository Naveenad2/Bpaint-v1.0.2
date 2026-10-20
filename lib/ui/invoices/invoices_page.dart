import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/backup_repo.dart';
import '../../data/repos/sales_repo.dart';
import '../../print/print_service.dart';
import '../../print/report_pdf.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'invoice_detail.dart';
import 'sales_return_dialog.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  final _repo = SalesRepo();
  final _search = TextEditingController();

  String _docType = DocType.invoice;
  String _status = '';
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  List<SalesDoc> _rows = const [];
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
      docType: _docType,
      from: _from,
      to: _to,
      status: _status,
      query: _search.text,
      limit: 800,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  double get _total => _rows
      .where((e) => !e.isCancelled)
      .fold<double>(0.0, (s, e) => s + e.total);
  double get _due => _rows
      .where((e) => !e.isCancelled)
      .fold<double>(0.0, (s, e) => s + e.balance);

  Future<void> _open(SalesDoc doc) async {
    final result = await InvoiceDetail.show(context, doc.id!);
    if (result == 'credit-note' && mounted) {
      final full = await _repo.byId(doc.id!);
      if (full != null && mounted) {
        final made = await SalesReturnDialog.show(context, full);
        if (made) await _load();
        return;
      }
    }
    if (result != null) await _load();
  }

  Future<void> _exportCsv() async {
    final path = await getSaveLocation(
      suggestedName: 'sales_register_${Fmt.iso(_from)}_to_${Fmt.iso(_to)}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (path == null) return;
    final rows = _rows
        .map((d) => <Object?>[
              Fmt.date(d.docDate),
              d.docNo,
              d.partyName,
              d.partyGstin,
              d.placeOfSupply,
              d.taxableAmount,
              d.cgst,
              d.sgst,
              d.igst,
              d.roundOff,
              d.total,
              d.paid,
              d.balance,
              d.status,
              d.paymentMode,
              d.userName,
            ])
        .toList();
    await BackupRepo().exportRows(
      path.path,
      const [
        'Date',
        'Bill No',
        'Party',
        'GSTIN',
        'POS',
        'Taxable',
        'CGST',
        'SGST',
        'IGST',
        'Round Off',
        'Total',
        'Paid',
        'Balance',
        'Status',
        'Mode',
        'User',
      ],
      rows,
    );
    if (!mounted) return;
    toast(context, 'Exported ${rows.length} rows.', success: true);
  }

  Future<void> _printRegister() async {
    final app = context.read<AppState>();
    final bytes = await ReportPdf.table(
      company: app.company,
      title: '${DocType.label[_docType]} Register',
      subtitle: '${Fmt.date(_from)} to ${Fmt.date(_to)}',
      landscape: true,
      columns: const [
        ReportColumn('Date', flex: 1.1),
        ReportColumn('Bill No', flex: 1.3),
        ReportColumn('Party', flex: 3),
        ReportColumn('GSTIN', flex: 1.8),
        ReportColumn('Taxable', flex: 1.2, numeric: true),
        ReportColumn('CGST', flex: 1, numeric: true),
        ReportColumn('SGST', flex: 1, numeric: true),
        ReportColumn('IGST', flex: 1, numeric: true),
        ReportColumn('Total', flex: 1.3, numeric: true),
        ReportColumn('Due', flex: 1.2, numeric: true),
        ReportColumn('Status', flex: 1),
      ],
      rows: _rows
          .map((d) => [
                Fmt.date(d.docDate),
                d.docNo,
                d.partyName,
                d.partyGstin,
                Fmt.amount(d.taxableAmount),
                Fmt.amount(d.cgst),
                Fmt.amount(d.sgst),
                Fmt.amount(d.igst),
                Fmt.amount(d.total),
                Fmt.amount(d.balance),
                d.status,
              ])
          .toList(),
      totalsRow: [
        '',
        '',
        '${_rows.length} documents',
        '',
        Fmt.amount(_rows.fold<double>(0.0, (s, e) => s + e.taxableAmount)),
        Fmt.amount(_rows.fold<double>(0.0, (s, e) => s + e.cgst)),
        Fmt.amount(_rows.fold<double>(0.0, (s, e) => s + e.sgst)),
        Fmt.amount(_rows.fold<double>(0.0, (s, e) => s + e.igst)),
        Fmt.amount(_total),
        Fmt.amount(_due),
        '',
      ],
    );
    if (!mounted) return;
    await PrintService.previewBytes(
      context,
      title: 'Sales Register',
      bytes: bytes,
      fileName: 'sales_register.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: DocType.invoice,
                          label: Text('Invoices'),
                          icon: Icon(Icons.receipt_long_rounded, size: 16)),
                      ButtonSegment(
                          value: DocType.estimate,
                          label: Text('Estimates'),
                          icon: Icon(Icons.description_rounded, size: 16)),
                      ButtonSegment(
                          value: DocType.creditNote,
                          label: Text('Credit notes'),
                          icon:
                              Icon(Icons.assignment_return_rounded, size: 16)),
                    ],
                    selected: {_docType},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      setState(() => _docType = s.first);
                      _load();
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _printRegister,
                        icon: const Icon(Icons.print_rounded, size: 17),
                        label: const Text('Print register'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _exportCsv,
                        icon: const Icon(Icons.download_rounded, size: 17),
                        label: const Text('Export CSV'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
                    width: 160,
                    child: Picker<String>(
                      label: 'Status',
                      value: _status,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All')),
                        DropdownMenuItem(
                            value: DocStatus.paid, child: Text('Paid')),
                        DropdownMenuItem(
                            value: DocStatus.partial, child: Text('Partial')),
                        DropdownMenuItem(
                            value: DocStatus.unpaid, child: Text('Unpaid')),
                        DropdownMenuItem(
                            value: DocStatus.cancelled,
                            child: Text('Cancelled')),
                      ],
                      onChanged: (v) {
                        setState(() => _status = v ?? '');
                        _load();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: Field(
                      label: 'Search bill no, party, phone or GSTIN',
                      controller: _search,
                      prefix: const Icon(Icons.search_rounded, size: 18),
                      onChanged: (_) => _load(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _summaryStrip(),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? const EmptyState(
                      title: 'No documents in this range',
                      message: 'Change the dates or start a new bill with F2.',
                      icon: Icons.receipt_long_rounded,
                    )
                  : MinWidthScroller(
                      minWidth: 940.0,
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

  Widget _summaryStrip() {
    return StatStrip(
      children: [
        StatText('Documents', '${_rows.length}'),
        StatText('Total value', Fmt.money(_total)),
        StatText('Outstanding', Fmt.money(_due),
            color: _due > 0 ? AppTheme.danger : null),
        StatText('Cancelled', '${_rows.where((e) => e.isCancelled).length}',
            color: AppTheme.warning),
      ],
    );
  }

  Widget _row(SalesDoc d, int index) {
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
                  style: const TextStyle(fontSize: 12.5)),
            ),
            SizedBox(
              width: 110,
              child: Text(d.docNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
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
                  Text(
                    [
                      if (d.partyGstin.isNotEmpty) d.partyGstin,
                      if (d.partyPhone.isNotEmpty) d.partyPhone,
                      d.paymentMode,
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
                width: 96,
                child: Money(d.taxableAmount, size: 12.5, symbol: false)),
            SizedBox(
                width: 88, child: Money(d.totalTax, size: 12.5, symbol: false)),
            SizedBox(width: 104, child: Money(d.total, size: 13.5, bold: true)),
            SizedBox(
              width: 96,
              child: Money(d.balance,
                  size: 12.5,
                  symbol: false,
                  color: d.balance > 0.5 ? AppTheme.danger : null),
            ),
            SizedBox(width: 86, child: StatusPill(d.status)),
            SizedBox(
              width: 78,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Print',
                    icon: const Icon(Icons.print_rounded, size: 17),
                    onPressed: () async {
                      final full = await _repo.byId(d.id!);
                      if (full == null || !mounted) return;
                      await PrintService.printInvoice(
                          context, context.read<AppState>(), full,
                          forceDialog: true);
                    },
                  ),
                  IconButton(
                    tooltip: 'Open',
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    onPressed: () => _open(d),
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
