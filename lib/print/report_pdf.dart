import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/formatters.dart';
import '../data/models.dart';

/// Column definition for the generic table report.
class ReportColumn {
  final String title;
  final double flex;
  final bool numeric;

  const ReportColumn(this.title, {this.flex = 1, this.numeric = false});
}

/// Renders any tabular report (registers, GST returns, stock, ageing) on A4
/// with a company letterhead, so every export looks like it came from the
/// same office.
class ReportPdf {
  static const PdfColor _ink = PdfColor.fromInt(0xFF14181D);
  static const PdfColor _muted = PdfColor.fromInt(0xFF5A6572);
  static const PdfColor _line = PdfColor.fromInt(0xFF9AA3AD);
  static const PdfColor _band = PdfColor.fromInt(0xFFEDEFF2);

  static Future<Uint8List> table({
    required Company company,
    required String title,
    String subtitle = '',
    required List<ReportColumn> columns,
    required List<List<String>> rows,
    List<String>? totalsRow,
    bool landscape = false,
    List<String> notes = const [],
  }) async {
    final pdf = pw.Document(title: title, author: company.name);
    final format = landscape
        ? const PdfPageFormat(297 * PdfPageFormat.mm, 210 * PdfPageFormat.mm,
            marginAll: 10 * PdfPageFormat.mm)
        : const PdfPageFormat(210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm,
            marginAll: 10 * PdfPageFormat.mm);

    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < columns.length; i++)
        i: pw.FlexColumnWidth(columns[i].flex),
    };

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        header: (ctx) => ctx.pageNumber == 1
            ? _letterhead(company, title, subtitle)
            : pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text('$title  ·  continued',
                    style: const pw.TextStyle(fontSize: 8, color: _muted)),
              ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Printed ${Fmt.dateTime(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 7, color: _muted)),
            pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ],
        ),
        build: (ctx) => [
          pw.Table(
            columnWidths: widths,
            border: pw.TableBorder.all(color: _line, width: 0.4),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: _band),
                repeat: true,
                children: [
                  for (final c in columns)
                    _cell(c.title, bold: true, numeric: c.numeric),
                ],
              ),
              for (final r in rows)
                pw.TableRow(
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      _cell(i < r.length ? r[i] : '',
                          numeric: columns[i].numeric),
                  ],
                ),
              if (totalsRow != null)
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _band),
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      _cell(i < totalsRow.length ? totalsRow[i] : '',
                          bold: true, numeric: columns[i].numeric),
                  ],
                ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            for (final n in notes)
              pw.Text('· $n',
                  style: const pw.TextStyle(fontSize: 7, color: _muted)),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _letterhead(
          Company company, String title, String subtitle) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(bottom: 5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(company.name,
                        style: const pw.TextStyle(
                            fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    if (company.addressLine.isNotEmpty)
                      pw.Text(company.addressLine,
                          style:
                              const pw.TextStyle(fontSize: 8, color: _muted)),
                    if (company.gstin.isNotEmpty)
                      pw.Text('GSTIN: ${company.gstin}',
                          style:
                              const pw.TextStyle(fontSize: 8, color: _muted)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(title.toUpperCase(),
                        style: const pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            letterSpacing: 0.5)),
                    if (subtitle.isNotEmpty)
                      pw.Text(subtitle,
                          style:
                              const pw.TextStyle(fontSize: 8, color: _muted)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

  static pw.Widget _cell(String text,
          {bool bold = false, bool numeric = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
        child: pw.Text(
          text,
          textAlign: numeric ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  // ------------------------------------------------------------------
  // Customer / supplier statement of account
  // ------------------------------------------------------------------
  static Future<Uint8List> statement({
    required Company company,
    required Party party,
    required List<LedgerRow> rows,
    DateTime? from,
    DateTime? to,
  }) async {
    final closing = rows.isEmpty ? 0.0 : rows.last.running;
    final data = rows
        .map((r) => [
              Fmt.date(r.date),
              r.voucherNo,
              r.particulars,
              r.debit == 0 ? '' : Fmt.amount(r.debit),
              r.credit == 0 ? '' : Fmt.amount(r.credit),
              Fmt.amount(r.running),
            ])
        .toList();

    return table(
      company: company,
      title: 'Statement of Account',
      subtitle: '${party.name}'
          '${party.phone.isNotEmpty ? '  ·  ${party.phone}' : ''}'
          '${from != null ? '  ·  ${Fmt.date(from)} to ${Fmt.date(to)}' : ''}',
      columns: const [
        ReportColumn('Date', flex: 1.2),
        ReportColumn('Voucher', flex: 1.4),
        ReportColumn('Particulars', flex: 4),
        ReportColumn('Debit', flex: 1.4, numeric: true),
        ReportColumn('Credit', flex: 1.4, numeric: true),
        ReportColumn('Balance', flex: 1.6, numeric: true),
      ],
      rows: data,
      totalsRow: [
        '',
        '',
        'Closing Balance',
        '',
        '',
        '${Fmt.amount(closing.abs())} ${closing >= 0 ? 'Dr' : 'Cr'}',
      ],
      notes: [
        'Amounts in Indian Rupees.',
        if (party.creditLimit > 0)
          'Credit limit: ${Fmt.amount(party.creditLimit)}'
              '${party.creditDays > 0 ? ', ${party.creditDays} days' : ''}.',
      ],
    );
  }

  // ------------------------------------------------------------------
  // Barcode / shelf labels
  // ------------------------------------------------------------------
  /// A4 sheet of 3 x 8 labels, sized for standard 65 x 35 mm sticker paper.
  static Future<Uint8List> barcodeLabels({
    required Company company,
    required List<Product> products,
    int copiesEach = 1,
    bool showMrp = true,
  }) async {
    final pdf = pw.Document(title: 'Barcode Labels');
    final expanded = <Product>[
      for (final p in products)
        for (var i = 0; i < copiesEach; i++) p,
    ];
    const perPage = 24;

    for (var start = 0; start < expanded.length; start += perPage) {
      final slice = expanded.skip(start).take(perPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(
              210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm,
              marginAll: 8 * PdfPageFormat.mm),
          build: (ctx) => pw.Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final p in slice) _label(p, company, showMrp),
            ],
          ),
        ),
      );
    }
    if (expanded.isEmpty) {
      pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('No items'))));
    }
    return pdf.save();
  }

  static pw.Widget _label(Product p, Company company, bool showMrp) {
    final code = p.barcode.isNotEmpty ? p.barcode : p.sku;
    return pw.Container(
      width: 62 * PdfPageFormat.mm,
      height: 33 * PdfPageFormat.mm,
      padding: const pw.EdgeInsets.all(3),
      decoration:
          pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.3)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(company.name,
              maxLines: 1,
              style: const pw.TextStyle(fontSize: 6, color: _muted)),
          pw.Text(p.fullName,
              maxLines: 2,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                  fontSize: 7, fontWeight: pw.FontWeight.bold)),
          if (code.isNotEmpty)
            pw.BarcodeWidget(
              barcode: bc.Barcode.code128(),
              data: code,
              width: 140,
              height: 26,
              drawText: true,
              textStyle: const pw.TextStyle(fontSize: 6),
            ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              if (showMrp && p.mrp > 0)
                pw.Text('MRP Rs.${Fmt.amount(p.mrp)}',
                    style: const pw.TextStyle(
                        fontSize: 7, fontWeight: pw.FontWeight.bold)),
              pw.Text(p.packSize, style: const pw.TextStyle(fontSize: 6.5)),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Day-close / Z report
  // ------------------------------------------------------------------
  static Future<Uint8List> dayClose({
    required Company company,
    required DateTime day,
    required int bills,
    required double sales,
    required double returns,
    required double collected,
    required double credit,
    required double expenses,
    required Map<String, double> byMode,
    required String user,
  }) async {
    final rows = <List<String>>[
      ['Bills issued', '$bills'],
      ['Gross sales', Fmt.amount(sales)],
      ['Sales returns', Fmt.amount(returns)],
      ['Net sales', Fmt.amount(sales - returns)],
      ['Collected at counter', Fmt.amount(collected)],
      ['Credit given', Fmt.amount(credit)],
      ['Expenses paid', Fmt.amount(expenses)],
      ...byMode.entries
          .map((e) => ['Collection · ${e.key}', Fmt.amount(e.value)]),
    ];
    return table(
      company: company,
      title: 'Day Close Report',
      subtitle: '${Fmt.date(day)}  ·  Prepared by $user',
      columns: const [
        ReportColumn('Particulars', flex: 3),
        ReportColumn('Amount', flex: 1.4, numeric: true),
      ],
      rows: rows,
      totalsRow: [
        'Cash in hand (cash collected less expenses)',
        Fmt.amount((byMode['CASH'] ?? 0) - expenses),
      ],
      notes: const [
        'Counted cash should match the figure above before the till is closed.',
      ],
    );
  }
}
