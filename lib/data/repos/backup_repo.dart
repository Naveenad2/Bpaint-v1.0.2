import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import '../../core/formatters.dart';
import '../db.dart';
import '../models.dart';
import 'product_repo.dart';

/// Backup, restore and CSV interchange.
class BackupRepo {
  /// Copies the live database to [dir] with a timestamped name.
  /// The WAL is checkpointed first so the single file is self-contained.
  Future<File> backupTo(String dir) async {
    await AppDb.instance.checkpoint();
    final target = Directory(dir);
    if (!await target.exists()) await target.create(recursive: true);
    final name = 'paintpro_backup_${Fmt.stamp(DateTime.now())}.db';
    final dest = File(p.join(dir, name));
    await File(AppDb.instance.path).copy(dest.path);
    return dest;
  }

  /// Keeps the most recent [keep] backups and deletes older ones.
  Future<int> prune(String dir, {int keep = 20}) async {
    final d = Directory(dir);
    if (!await d.exists()) return 0;
    final files = (await d.list().toList())
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('paintpro_backup_'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    var removed = 0;
    for (final f in files.skip(keep)) {
      await f.delete();
      removed++;
    }
    return removed;
  }

  /// Replaces the live database with [file]. The current database is kept
  /// alongside as `*.pre-restore` so a bad restore is always undoable.
  /// The app must be restarted afterwards.
  Future<void> restoreFrom(String file) async {
    final src = File(file);
    if (!await src.exists()) {
      throw ArgumentError('Backup file not found.');
    }
    // Sanity check: every SQLite file opens with this 15-byte magic string.
    final handle = await src.open();
    final head = await handle.read(16);
    await handle.close();
    if (head.length < 15 ||
        String.fromCharCodes(head.sublist(0, 15)) != 'SQLite format 3') {
      throw ArgumentError('That file is not a PaintPro backup.');
    }

    final livePath = AppDb.instance.path;
    await AppDb.instance.close();

    final stamp = Fmt.stamp(DateTime.now());
    final live = File(livePath);
    if (await live.exists()) {
      await live.rename('$livePath.pre-restore-$stamp');
    }
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$livePath$suffix');
      if (await f.exists()) await f.delete();
    }
    await src.copy(livePath);
  }

  // ------------------------------------------------------------------
  // CSV export
  // ------------------------------------------------------------------
  static String toCsv(List<List<Object?>> rows) =>
      const ListToCsvConverter().convert(rows);

  Future<File> writeCsv(String path, List<List<Object?>> rows) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    // A BOM makes Excel open UTF-8 (and the ₹ sign) correctly.
    await f.writeAsString('﻿${toCsv(rows)}');
    return f;
  }

  Future<File> exportProducts(String path, List<Product> products) {
    final rows = <List<Object?>>[
      [
        'SKU',
        'Barcode',
        'Name',
        'Brand',
        'Category',
        'HSN',
        'Base',
        'Shade Code',
        'Shade Name',
        'Pack Size',
        'Unit',
        'MRP',
        'Purchase Price',
        'Retail Price',
        'Dealer Price',
        'Contractor Price',
        'GST %',
        'Cess %',
        'Stock',
        'Min Stock',
        'Rack',
      ],
      ...products.map((p) => [
            p.sku,
            p.barcode,
            p.name,
            p.brand,
            p.category,
            p.hsn,
            p.baseType,
            p.shadeCode,
            p.shadeName,
            p.packSize,
            p.unit,
            p.mrp,
            p.purchasePrice,
            p.retailPrice,
            p.dealerPrice,
            p.contractorPrice,
            p.gstRate,
            p.cessRate,
            p.stock,
            p.minStock,
            p.rack,
          ]),
    ];
    return writeCsv(path, rows);
  }

  Future<File> exportParties(String path, List<Party> parties) {
    final rows = <List<Object?>>[
      [
        'Code',
        'Name',
        'Contact',
        'Phone',
        'Email',
        'GSTIN',
        'Address',
        'City',
        'State Code',
        'PIN',
        'Price Tier',
        'Credit Limit',
        'Credit Days',
        'Balance',
      ],
      ...parties.map((p) => [
            p.code,
            p.name,
            p.contactPerson,
            p.phone,
            p.email,
            p.gstin,
            p.addressLine,
            p.city,
            p.stateCode,
            p.pincode,
            p.priceTier,
            p.creditLimit,
            p.creditDays,
            p.balance,
          ]),
    ];
    return writeCsv(path, rows);
  }

  /// Generic export used by every report screen.
  Future<File> exportRows(
    String path,
    List<String> headers,
    List<List<Object?>> data,
  ) =>
      writeCsv(path, [headers, ...data]);

  // ------------------------------------------------------------------
  // CSV import
  // ------------------------------------------------------------------
  /// Imports products from a CSV laid out like [exportProducts].
  /// Existing SKUs are updated; new ones are inserted.
  Future<ImportResult> importProducts(String path) async {
    final raw = await File(path).readAsString();
    final table = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(raw.replaceAll('\r\n', '\n').replaceFirst('﻿', ''));
    if (table.length < 2) {
      return ImportResult(0, 0, ['File has no data rows.']);
    }

    final header =
        table.first.map((e) => e.toString().trim().toLowerCase()).toList();
    int col(String name) => header.indexOf(name.toLowerCase());
    String cell(List<dynamic> row, int i) =>
        (i >= 0 && i < row.length) ? row[i].toString().trim() : '';

    final repo = ProductRepo();
    final errors = <String>[];
    var created = 0, updated = 0;

    final idx = {
      'sku': col('SKU'),
      'barcode': col('Barcode'),
      'name': col('Name'),
      'brand': col('Brand'),
      'category': col('Category'),
      'hsn': col('HSN'),
      'base': col('Base'),
      'shadeCode': col('Shade Code'),
      'shadeName': col('Shade Name'),
      'pack': col('Pack Size'),
      'unit': col('Unit'),
      'mrp': col('MRP'),
      'purchase': col('Purchase Price'),
      'retail': col('Retail Price'),
      'dealer': col('Dealer Price'),
      'contractor': col('Contractor Price'),
      'gst': col('GST %'),
      'cess': col('Cess %'),
      'stock': col('Stock'),
      'minStock': col('Min Stock'),
      'rack': col('Rack'),
    };
    if (idx['name']! < 0) {
      return ImportResult(0, 0, ['A "Name" column is required.']);
    }

    for (var r = 1; r < table.length; r++) {
      final row = table[r];
      final name = cell(row, idx['name']!);
      if (name.isEmpty) continue;
      try {
        final sku = cell(row, idx['sku']!);
        Product? existing;
        if (sku.isNotEmpty) existing = await repo.byCode(sku);

        final p = existing ?? Product();
        p.sku = sku.isNotEmpty ? sku : p.sku;
        p.barcode = cell(row, idx['barcode']!);
        p.name = name;
        p.brand = cell(row, idx['brand']!);
        p.category = cell(row, idx['category']!);
        p.hsn = cell(row, idx['hsn']!);
        p.baseType = cell(row, idx['base']!);
        p.shadeCode = cell(row, idx['shadeCode']!);
        p.shadeName = cell(row, idx['shadeName']!);
        p.packSize = cell(row, idx['pack']!);
        final unit = cell(row, idx['unit']!);
        if (unit.isNotEmpty) p.unit = unit.toUpperCase();
        p.mrp = Fmt.toDouble(cell(row, idx['mrp']!));
        p.purchasePrice = Fmt.toDouble(cell(row, idx['purchase']!));
        p.retailPrice = Fmt.toDouble(cell(row, idx['retail']!));
        p.dealerPrice = Fmt.toDouble(cell(row, idx['dealer']!));
        p.contractorPrice = Fmt.toDouble(cell(row, idx['contractor']!));
        p.gstRate = Fmt.toDouble(cell(row, idx['gst']!), 18);
        p.cessRate = Fmt.toDouble(cell(row, idx['cess']!));
        p.minStock = Fmt.toDouble(cell(row, idx['minStock']!));
        p.rack = cell(row, idx['rack']!);
        if (existing == null) {
          p.openingStock = Fmt.toDouble(cell(row, idx['stock']!));
        }

        await repo.save(p);
        existing == null ? created++ : updated++;
      } catch (e) {
        errors.add('Row ${r + 1}: $e');
      }
    }
    return ImportResult(created, updated, errors);
  }

  /// Blank template so a shop can prepare its catalogue in Excel.
  Future<File> productTemplate(String path) => writeCsv(path, [
        [
          'SKU',
          'Barcode',
          'Name',
          'Brand',
          'Category',
          'HSN',
          'Base',
          'Shade Code',
          'Shade Name',
          'Pack Size',
          'Unit',
          'MRP',
          'Purchase Price',
          'Retail Price',
          'Dealer Price',
          'Contractor Price',
          'GST %',
          'Cess %',
          'Stock',
          'Min Stock',
          'Rack',
        ],
        [
          'P00001',
          '8901234567890',
          'Premium Emulsion Interior',
          'Asian Paints',
          'Interior Emulsion',
          '3209',
          'White Base',
          'AP-101',
          'Ivory',
          '4 LTR',
          'LTR',
          1450,
          980,
          1250,
          1150,
          1100,
          18,
          0,
          24,
          6,
          'A-1',
        ],
      ]);
}

class ImportResult {
  final int created;
  final int updated;
  final List<String> errors;
  ImportResult(this.created, this.updated, this.errors);

  bool get ok => errors.isEmpty;
  String get summary => '$created added, $updated updated'
      '${errors.isEmpty ? '' : ', ${errors.length} skipped'}';
}
