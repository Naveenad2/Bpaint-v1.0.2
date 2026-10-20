import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/tax.dart';
import '../data/models.dart';

/// Builds print-ready invoices.
///
/// The default is **A5 horizontal (210 x 148 mm)** — the size most Indian
/// paint counters use, because two bills fit on one A4 sheet and dot-matrix
/// stationery is cut to it.
///
/// Note on the rupee sign: PDFs use the built-in Helvetica metrics so the
/// file stays ~20 KB and prints instantly on cheap printers. Helvetica has
/// no glyph for the rupee symbol, so amounts are prefixed "Rs." — the
/// on-screen UI still shows the real symbol.
class InvoicePdf {
  static const PdfPageFormat a5Landscape = PdfPageFormat(
      210 * PdfPageFormat.mm, 148 * PdfPageFormat.mm,
      marginAll: 6 * PdfPageFormat.mm);
  static const PdfPageFormat a5Portrait = PdfPageFormat(
      148 * PdfPageFormat.mm, 210 * PdfPageFormat.mm,
      marginAll: 6 * PdfPageFormat.mm);
  static const PdfPageFormat a4 = PdfPageFormat(
      210 * PdfPageFormat.mm, 297 * PdfPageFormat.mm,
      marginAll: 10 * PdfPageFormat.mm);
  static const PdfPageFormat thermal80 = PdfPageFormat(
      80 * PdfPageFormat.mm, double.infinity,
      marginAll: 3 * PdfPageFormat.mm);

  static PdfPageFormat formatFor(String key) {
    switch (key) {
      case PrintFormat.a5Portrait:
        return a5Portrait;
      case PrintFormat.a4:
        return a4;
      case PrintFormat.thermal80:
        return thermal80;
      default:
        return a5Landscape;
    }
  }

  static const PdfColor _ink = PdfColor.fromInt(0xFF14181D);
  static const PdfColor _muted = PdfColor.fromInt(0xFF5A6572);
  static const PdfColor _line = PdfColor.fromInt(0xFF9AA3AD);
  static const PdfColor _band = PdfColor.fromInt(0xFFEDEFF2);

  static String _rs(num v) => 'Rs. ${Fmt.amount(v)}';

  /// Entry point used by every print/preview action.
  static Future<Uint8List> build({
    required Company company,
    required SalesDoc doc,
    required String format,
    String? terms,
    String? declaration,
    bool showBank = true,
    int copies = 1,
    List<String> copyLabels = const ['ORIGINAL FOR RECIPIENT'],
  }) async {
    if (format == PrintFormat.thermal80) {
      return _thermal(company: company, doc: doc, terms: terms);
    }
    final pdf = pw.Document(
      title: '${DocType.label[doc.docType] ?? 'Invoice'} ${doc.docNo}',
      author: company.name,
    );
    final pageFormat = formatFor(format);
    final compact = format != PrintFormat.a4;

    final labels = copies <= 1
        ? [copyLabels.isEmpty ? '' : copyLabels.first]
        : List.generate(
            copies, (i) => i < copyLabels.length ? copyLabels[i] : 'COPY');

    for (final label in labels) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: pageFormat,
          maxPages: 30,
          header: (ctx) => ctx.pageNumber == 1
              ? _header(company, doc, label, compact)
              : _continuationHeader(company, doc, ctx, compact),
          footer: (ctx) => _footer(ctx, compact),
          build: (ctx) => [
            _partyBlock(company, doc, compact),
            pw.SizedBox(height: 4),
            _itemsTable(doc, compact),
            pw.SizedBox(height: 4),
            _totalsBlock(company, doc, compact,
                terms: terms, declaration: declaration, showBank: showBank),
          ],
        ),
      );
    }
    return pdf.save();
  }

  // ------------------------------------------------------------------
  // Header
  // ------------------------------------------------------------------
  static pw.Widget _header(
      Company company, SalesDoc doc, String copyLabel, bool compact) {
    final titleSize = compact ? 13.0 : 16.0;
    final base = compact ? 6.5 : 8.0;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.2)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 6,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      company.name.isEmpty ? 'YOUR PAINT STORE' : company.name,
                      style: pw.TextStyle(
                        fontSize: titleSize,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (company.addressLine.isNotEmpty)
                      pw.Text(company.addressLine,
                          style: pw.TextStyle(fontSize: base, color: _muted)),
                    pw.Text(
                      [
                        if (company.stateCode.isNotEmpty)
                          'State: ${IndianStates.name(company.stateCode)} (${company.stateCode})',
                        if (company.phone.isNotEmpty) 'Ph: ${company.phone}',
                        if (company.email.isNotEmpty) company.email,
                      ].join('   '),
                      style: pw.TextStyle(fontSize: base, color: _muted),
                    ),
                    if (company.gstin.isNotEmpty)
                      pw.Text('GSTIN: ${company.gstin}',
                          style: pw.TextStyle(
                              fontSize: base + 0.5,
                              fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      color: _ink,
                      child: pw.Text(
                        (DocType.label[doc.docType] ?? 'TAX INVOICE')
                            .toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: compact ? 8 : 10,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    if (copyLabel.isNotEmpty)
                      pw.Text(copyLabel,
                          style: pw.TextStyle(
                              fontSize: base - 0.5,
                              color: _muted,
                              fontStyle: pw.FontStyle.italic)),
                    pw.SizedBox(height: 2),
                    _kv('Invoice No', doc.docNo, base, bold: true),
                    _kv('Date', Fmt.date(doc.docDate), base),
                    if (doc.dueDate != null)
                      _kv('Due Date', Fmt.date(doc.dueDate), base),
                    if (doc.refDocNo.isNotEmpty)
                      _kv('Against', doc.refDocNo, base),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (doc.status == DocStatus.cancelled)
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 3),
            padding: const pw.EdgeInsets.all(2),
            color: PdfColors.red100,
            child: pw.Text('*** CANCELLED ***',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                    fontSize: base + 1,
                    color: PdfColors.red800,
                    fontWeight: pw.FontWeight.bold)),
          ),
      ],
    );
  }

  static pw.Widget _continuationHeader(
      Company company, SalesDoc doc, pw.Context ctx, bool compact) {
    final base = compact ? 6.5 : 8.0;
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 2),
      margin: const pw.EdgeInsets.only(bottom: 3),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(company.name,
              style: pw.TextStyle(
                  fontSize: base + 1, fontWeight: pw.FontWeight.bold)),
          pw.Text('${doc.docNo}  ·  continued',
              style: pw.TextStyle(fontSize: base, color: _muted)),
        ],
      ),
    );
  }

  static pw.Widget _kv(String k, String v, double size, {bool bold = false}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('$k: ', style: pw.TextStyle(fontSize: size, color: _muted)),
          pw.Text(v,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );

  // ------------------------------------------------------------------
  // Party block
  // ------------------------------------------------------------------
  static pw.Widget _partyBlock(Company company, SalesDoc doc, bool compact) {
    final base = compact ? 6.5 : 8.0;
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4),
      decoration:
          pw.BoxDecoration(border: pw.Border.all(color: _line, width: 0.6)),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('BILL TO',
                      style: pw.TextStyle(
                          fontSize: base - 0.5,
                          color: _muted,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 0.5)),
                  pw.SizedBox(height: 1),
                  pw.Text(doc.partyName,
                      style: pw.TextStyle(
                          fontSize: base + 1.5,
                          fontWeight: pw.FontWeight.bold)),
                  if (doc.partyAddress.isNotEmpty)
                    pw.Text(doc.partyAddress,
                        style: pw.TextStyle(fontSize: base, color: _muted)),
                  pw.Row(children: [
                    if (doc.partyPhone.isNotEmpty)
                      pw.Text('Ph: ${doc.partyPhone}   ',
                          style: pw.TextStyle(fontSize: base)),
                    if (doc.partyGstin.isNotEmpty)
                      pw.Text('GSTIN: ${doc.partyGstin}',
                          style: pw.TextStyle(
                              fontSize: base, fontWeight: pw.FontWeight.bold)),
                  ]),
                ],
              ),
            ),
          ),
          pw.Container(width: 0.6, color: _line),
          pw.Expanded(
            flex: 4,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pair(
                      'Place of Supply',
                      '${IndianStates.name(doc.placeOfSupply)} (${doc.placeOfSupply})',
                      base),
                  _pair(
                      'Supply Type',
                      doc.isIgst
                          ? 'Inter-State (IGST)'
                          : 'Intra-State (CGST+SGST)',
                      base),
                  _pair('Payment', doc.paymentMode, base),
                  if (doc.vehicleNo.isNotEmpty)
                    _pair('Vehicle', doc.vehicleNo, base),
                  if (doc.transport.isNotEmpty)
                    _pair('Transport', doc.transport, base),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _pair(String k, String v, double size) => pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 58,
            child: pw.Text(k,
                style: pw.TextStyle(fontSize: size - 0.5, color: _muted)),
          ),
          pw.Expanded(
            child: pw.Text(v, style: pw.TextStyle(fontSize: size)),
          ),
        ],
      );

  // ------------------------------------------------------------------
  // Items
  // ------------------------------------------------------------------
  static pw.Widget _itemsTable(SalesDoc doc, bool compact) {
    final base = compact ? 6.5 : 8.0;
    final showDiscount = doc.items.any((e) => e.discountAmt > 0);

    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(16), // #
      1: const pw.FlexColumnWidth(6), // description
      2: const pw.FixedColumnWidth(34), // HSN
      3: const pw.FixedColumnWidth(38), // qty
      4: const pw.FixedColumnWidth(42), // rate
      if (showDiscount) 5: const pw.FixedColumnWidth(36), // discount
      (showDiscount ? 6 : 5): const pw.FixedColumnWidth(44), // taxable
      (showDiscount ? 7 : 6): const pw.FixedColumnWidth(28), // gst %
      (showDiscount ? 8 : 7): const pw.FixedColumnWidth(38), // tax
      (showDiscount ? 9 : 8): const pw.FixedColumnWidth(48), // amount
    };

    final head = <String>[
      '#',
      'Description of Goods',
      'HSN',
      'Qty',
      'Rate',
      if (showDiscount) 'Disc.',
      'Taxable',
      'GST%',
      'Tax',
      'Amount',
    ];

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _band),
        children: [
          for (var i = 0; i < head.length; i++)
            _cell(head[i], base,
                bold: true,
                align: i <= 2 ? pw.TextAlign.left : pw.TextAlign.right),
        ],
      ),
    ];

    for (var i = 0; i < doc.items.length; i++) {
      final it = doc.items[i];
      rows.add(pw.TableRow(
        children: [
          _cell('${i + 1}', base, align: pw.TextAlign.left),
          _descCell(it, base),
          _cell(it.hsn, base, align: pw.TextAlign.left),
          _cell(
              '${Fmt.qty(it.qty)}${it.freeQty > 0 ? '+${Fmt.qty(it.freeQty)}F' : ''} ${it.unit}',
              base),
          _cell(Fmt.amount(it.grossRate), base),
          if (showDiscount)
            _cell(it.discountAmt > 0 ? Fmt.amount(it.discountAmt) : '-', base),
          _cell(Fmt.amount(it.taxable), base),
          _cell(Fmt.qty(it.gstRate), base),
          _cell(Fmt.amount(it.taxAmount), base),
          _cell(Fmt.amount(it.total), base, bold: true),
        ],
      ));
    }

    return pw.Table(
      columnWidths: widths,
      border: pw.TableBorder.all(color: _line, width: 0.5),
      children: rows,
    );
  }

  static pw.Widget _descCell(SalesItem it, double size) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(it.name,
                maxLines: 2,
                style: pw.TextStyle(
                    fontSize: size + 0.5, fontWeight: pw.FontWeight.bold)),
            if (it.batch.isNotEmpty || it.mrp > 0)
              pw.Text(
                [
                  if (it.batch.isNotEmpty) 'Batch: ${it.batch}',
                  if (it.mrp > 0) 'MRP: ${Fmt.amount(it.mrp)}',
                ].join('   '),
                style: pw.TextStyle(fontSize: size - 0.5, color: _muted),
              ),
          ],
        ),
      );

  static pw.Widget _cell(
    String text,
    double size, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.right,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );

  // ------------------------------------------------------------------
  // Totals, tax summary, footer
  // ------------------------------------------------------------------
  static pw.Widget _totalsBlock(
    Company company,
    SalesDoc doc,
    bool compact, {
    String? terms,
    String? declaration,
    bool showBank = true,
  }) {
    final base = compact ? 6.5 : 8.0;
    final slabs = TaxEngine.slabSummary(doc);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // ---- Left: tax summary, bank, words -------------------------
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (slabs.isNotEmpty) _slabTable(doc, slabs, base),
                  pw.SizedBox(height: 3),
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(3),
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _line, width: 0.5)),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Amount in words',
                            style: pw.TextStyle(
                                fontSize: base - 0.5, color: _muted)),
                        pw.Text(NumberToWords.rupees(doc.total),
                            style: pw.TextStyle(
                                fontSize: base + 0.5,
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ),
                  if (showBank && company.bankName.isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'Bank: ${company.bankName}   A/c: ${company.accountNo}   '
                      'IFSC: ${company.ifsc}'
                      '${company.branch.isNotEmpty ? '   Branch: ${company.branch}' : ''}'
                      '${company.upiId.isNotEmpty ? '\nUPI: ${company.upiId}' : ''}',
                      style: pw.TextStyle(fontSize: base - 0.5, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 6),
            // ---- Right: money column -------------------------------------
            pw.Expanded(
              flex: 4,
              child: pw.Container(
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _line, width: 0.6)),
                child: pw.Column(
                  children: [
                    _money('Taxable Value', doc.taxableAmount, base),
                    if (doc.itemDiscount > 0)
                      _money('Item Discount', -doc.itemDiscount, base),
                    if (doc.docDiscountAmt > 0)
                      _money('Bill Discount', -doc.docDiscountAmt, base),
                    if (!doc.isIgst) ...[
                      _money('CGST', doc.cgst, base),
                      _money('SGST', doc.sgst, base),
                    ] else
                      _money('IGST', doc.igst, base),
                    if (doc.cess > 0) _money('Cess', doc.cess, base),
                    if (doc.freight > 0) _money('Freight', doc.freight, base),
                    if (doc.otherCharges > 0)
                      _money('Other Charges', doc.otherCharges, base),
                    if (doc.roundOff != 0)
                      _money('Round Off', doc.roundOff, base),
                    pw.Container(
                      color: _ink,
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 4, vertical: 3),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('GRAND TOTAL',
                              style: pw.TextStyle(
                                  fontSize: base + 1,
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text(_rs(doc.total),
                              style: pw.TextStyle(
                                  fontSize: base + 2,
                                  color: PdfColors.white,
                                  fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    ),
                    if (doc.paid > 0) _money('Paid', doc.paid, base),
                    if (doc.balance > 0.4)
                      _money('Balance Due', doc.balance, base, bold: true),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        // ---- Terms + signature -----------------------------------------
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 6,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if ((terms ?? '').trim().isNotEmpty) ...[
                    pw.Text('Terms & Conditions',
                        style: pw.TextStyle(
                            fontSize: base - 0.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _muted)),
                    pw.Text(terms!.trim(),
                        style: pw.TextStyle(fontSize: base - 1, color: _muted)),
                  ],
                  if ((declaration ?? '').trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(declaration!.trim(),
                        style: pw.TextStyle(
                            fontSize: base - 1,
                            color: _muted,
                            fontStyle: pw.FontStyle.italic)),
                  ],
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('For ${company.name}',
                      style: pw.TextStyle(
                          fontSize: base, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 22),
                  pw.Container(width: 110, height: 0.6, color: _line),
                  pw.Text('Authorised Signatory',
                      style: pw.TextStyle(fontSize: base - 0.5, color: _muted)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _slabTable(
      SalesDoc doc, List<TaxSlabRow> slabs, double base) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _band),
        children: [
          _cell('Rate', base, bold: true, align: pw.TextAlign.left),
          _cell('Taxable', base, bold: true),
          if (!doc.isIgst) ...[
            _cell('CGST', base, bold: true),
            _cell('SGST', base, bold: true),
          ] else
            _cell('IGST', base, bold: true),
          _cell('Total Tax', base, bold: true),
        ],
      ),
    ];
    for (final s in slabs) {
      rows.add(pw.TableRow(children: [
        _cell('${Fmt.qty(s.gstRate)}%', base, align: pw.TextAlign.left),
        _cell(Fmt.amount(s.taxable), base),
        if (!doc.isIgst) ...[
          _cell(Fmt.amount(s.cgst), base),
          _cell(Fmt.amount(s.sgst), base),
        ] else
          _cell(Fmt.amount(s.igst), base),
        _cell(Fmt.amount(s.totalTax), base),
      ]));
    }
    return pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.5),
      children: rows,
    );
  }

  static pw.Widget _money(String label, double value, double base,
          {bool bold = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.3)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: base,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            pw.Text(Fmt.amount(value),
                style: pw.TextStyle(
                    fontSize: base,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ],
        ),
      );

  static pw.Widget _footer(pw.Context ctx, bool compact) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}   ·   '
          'Generated by ${AppInfo.appName}',
          style: pw.TextStyle(fontSize: compact ? 5.5 : 7, color: _muted),
        ),
      );

  // ------------------------------------------------------------------
  // Thermal roll (80 mm)
  // ------------------------------------------------------------------
  static Future<Uint8List> _thermal({
    required Company company,
    required SalesDoc doc,
    String? terms,
  }) async {
    final pdf = pw.Document(title: doc.docNo);
    const s = 7.0;
    pdf.addPage(
      pw.Page(
        pageFormat: thermal80,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(company.name,
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ),
            if (company.addressLine.isNotEmpty)
              pw.Center(
                child: pw.Text(company.addressLine,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: s - 0.5)),
              ),
            if (company.phone.isNotEmpty)
              pw.Center(
                  child: pw.Text('Ph: ${company.phone}',
                      style: const pw.TextStyle(fontSize: s - 0.5))),
            if (company.gstin.isNotEmpty)
              pw.Center(
                  child: pw.Text('GSTIN: ${company.gstin}',
                      style: const pw.TextStyle(fontSize: s - 0.5))),
            pw.Divider(height: 6, thickness: 0.6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Bill: ${doc.docNo}',
                    style: const pw.TextStyle(
                        fontSize: s, fontWeight: pw.FontWeight.bold)),
                pw.Text(Fmt.dateTime(doc.docDate),
                    style: const pw.TextStyle(fontSize: s - 0.5)),
              ],
            ),
            pw.Text('Customer: ${doc.partyName}',
                style: const pw.TextStyle(fontSize: s)),
            pw.Divider(height: 6, thickness: 0.6),
            pw.Row(children: [
              pw.Expanded(
                  flex: 5,
                  child: pw.Text('Item',
                      style: const pw.TextStyle(
                          fontSize: s - 0.5, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(
                  flex: 2,
                  child: pw.Text('Qty',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(
                          fontSize: s - 0.5, fontWeight: pw.FontWeight.bold))),
              pw.Expanded(
                  flex: 3,
                  child: pw.Text('Amount',
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(
                          fontSize: s - 0.5, fontWeight: pw.FontWeight.bold))),
            ]),
            pw.Divider(height: 4, thickness: 0.4),
            for (final it in doc.items) ...[
              pw.Text(it.name, style: const pw.TextStyle(fontSize: s)),
              pw.Row(children: [
                pw.Expanded(
                    flex: 5,
                    child: pw.Text(
                        '  ${Fmt.qty(it.qty)} ${it.unit} x ${Fmt.amount(it.grossRate)}',
                        style: const pw.TextStyle(
                            fontSize: s - 0.5, color: _muted))),
                pw.Expanded(
                    flex: 3,
                    child: pw.Text(Fmt.amount(it.total),
                        textAlign: pw.TextAlign.right,
                        style: const pw.TextStyle(fontSize: s))),
              ]),
            ],
            pw.Divider(height: 6, thickness: 0.6),
            _tRow('Taxable', Fmt.amount(doc.taxableAmount), s),
            if (!doc.isIgst) ...[
              _tRow('CGST', Fmt.amount(doc.cgst), s),
              _tRow('SGST', Fmt.amount(doc.sgst), s),
            ] else
              _tRow('IGST', Fmt.amount(doc.igst), s),
            if (doc.roundOff != 0)
              _tRow('Round Off', Fmt.amount(doc.roundOff), s),
            pw.Divider(height: 4, thickness: 0.6),
            _tRow('TOTAL', _rs(doc.total), s + 2, bold: true),
            _tRow('Paid (${doc.paymentMode})', Fmt.amount(doc.paid), s),
            if (doc.balance > 0.4)
              _tRow('Balance', Fmt.amount(doc.balance), s, bold: true),
            pw.SizedBox(height: 4),
            pw.Center(
                child: pw.Text(
                    'Items: ${doc.items.length}   '
                    'Qty: ${Fmt.qty(doc.totalQty)}',
                    style: const pw.TextStyle(fontSize: s - 0.5))),
            pw.SizedBox(height: 6),
            pw.Center(
                child: pw.Text('Thank you! Visit again.',
                    style: const pw.TextStyle(
                        fontSize: s, fontWeight: pw.FontWeight.bold))),
            if ((terms ?? '').isNotEmpty)
              pw.Center(
                  child: pw.Text(terms!.split('\n').first,
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(
                          fontSize: s - 1.5, color: _muted))),
          ],
        ),
      ),
    );
    return pdf.save();
  }

  static pw.Widget _tRow(String k, String v, double size,
          {bool bold = false}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(k,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(v,
              style: pw.TextStyle(
                  fontSize: size,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );
}
