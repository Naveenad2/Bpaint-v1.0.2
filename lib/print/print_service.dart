import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/constants.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'invoice_pdf.dart';

/// One place for everything that reaches a printer or a PDF file.
class PrintService {
  /// Sends the bill straight to the default printer when auto-print is on,
  /// otherwise opens the system print dialog.
  static Future<bool> printInvoice(
    BuildContext context,
    AppState app,
    SalesDoc doc, {
    String? formatOverride,
    int copies = 1,
    bool forceDialog = false,
  }) async {
    final format = formatOverride ?? app.printFormat;
    final bytes = await _bytes(app, doc, format, copies: copies);
    final name = '${doc.docNo.replaceAll('/', '-')}.pdf';

    if (app.autoPrint && !forceDialog) {
      try {
        return await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: name,
          format: InvoicePdf.formatFor(format),
          usePrinterSettings: true,
        );
      } catch (_) {
        // Fall through to the dialog if the default printer is unavailable.
      }
    }
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: name,
      format: InvoicePdf.formatFor(format),
    );
  }

  /// Full-screen preview with print / save / share actions.
  static Future<void> previewInvoice(
    BuildContext context,
    AppState app,
    SalesDoc doc, {
    String? formatOverride,
  }) async {
    final format = formatOverride ?? app.printFormat;
    final bytes = await _bytes(app, doc, format);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PreviewPage(
          title: '${DocType.label[doc.docType] ?? 'Invoice'}  ·  ${doc.docNo}',
          bytes: bytes,
          format: InvoicePdf.formatFor(format),
          fileName: '${doc.docNo.replaceAll('/', '-')}.pdf',
        ),
      ),
    );
  }

  static Future<Uint8List> _bytes(
    AppState app,
    SalesDoc doc,
    String format, {
    int copies = 1,
  }) =>
      InvoicePdf.build(
        company: app.company,
        doc: doc,
        format: format,
        terms: app.settings.get(SKeys.terms),
        declaration: app.settings.get(SKeys.declaration),
        showBank: app.settings.getBool(SKeys.showBankOnInvoice, true),
        copies: copies,
        copyLabels: const [
          'ORIGINAL FOR RECIPIENT',
          'DUPLICATE FOR TRANSPORTER',
          'TRIPLICATE FOR SUPPLIER',
        ],
      );

  /// Writes the invoice next to the database so it can be emailed later.
  static Future<File> saveInvoiceToFile(
    AppState app,
    SalesDoc doc,
    String path, {
    String? formatOverride,
  }) async {
    final bytes = await _bytes(app, doc, formatOverride ?? app.printFormat);
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    return f;
  }

  static Future<void> sharePdf(Uint8List bytes, String name) =>
      Printing.sharePdf(bytes: bytes, filename: name);

  /// Generic preview for reports and statements.
  static Future<void> previewBytes(
    BuildContext context, {
    required String title,
    required Uint8List bytes,
    PdfPageFormat format = PdfPageFormat.a4,
    String fileName = 'report.pdf',
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PreviewPage(
          title: title,
          bytes: bytes,
          format: format,
          fileName: fileName,
        ),
      ),
    );
  }

  static Future<List<Printer>> printers() async {
    try {
      return await Printing.listPrinters();
    } catch (_) {
      return const [];
    }
  }
}

class _PreviewPage extends StatelessWidget {
  const _PreviewPage({
    required this.title,
    required this.bytes,
    required this.format,
    required this.fileName,
  });

  final String title;
  final Uint8List bytes;
  final PdfPageFormat format;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Share / Save as PDF',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () =>
                Printing.sharePdf(bytes: bytes, filename: fileName),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        initialPageFormat: format,
        pdfFileName: fileName,
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        maxPageWidth: 900,
        useActions: true,
      ),
    );
  }
}
