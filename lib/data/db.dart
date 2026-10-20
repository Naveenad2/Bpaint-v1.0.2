import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/constants.dart';

/// Reads the first column of the first row as an int.
///
/// `Sqflite.firstIntValue` lives in `sqflite_common` and is not re-exported by
/// the `sqflite_common_ffi` barrel, so COUNT(*) queries use this instead.
int firstInt(List<Map<String, Object?>> rows, [int fallback = 0]) {
  if (rows.isEmpty) return fallback;
  final v = rows.first.values.first;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

/// Embedded SQLite database. Single file, no server, opens in < 100 ms on a
/// spinning disk and holds a full year of billing in a few megabytes.
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  static const int schemaVersion = 1;

  Database? _db;
  late String _dir;
  late String _path;

  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('Database not initialised. Call AppDb.init() first.');
    }
    return d;
  }

  String get path => _path;
  String get dataDir => _dir;
  bool get isOpen => _db != null;

  /// Opens the database. [overrideDir] replaces the platform application
  /// support folder — used by tests, and by anyone who wants the data file on
  /// a shared drive.
  Future<void> init({String? overrideDir}) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final base = overrideDir ?? (await getApplicationSupportDirectory()).path;
    _dir = p.join(base, 'data');
    await Directory(_dir).create(recursive: true);
    _path = p.join(_dir, 'paintpro.db');

    _db = await databaseFactory.openDatabase(
      _path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
          // WAL keeps the UI responsive while a bill is being written.
          // journal_mode returns a row, so it must be a query, not an execute.
          await d.rawQuery('PRAGMA journal_mode = WAL');
          await d.execute('PRAGMA synchronous = NORMAL');
          // 4 MB page cache — plenty for retail volumes, tiny footprint.
          await d.execute('PRAGMA cache_size = -4000');
          await d.execute('PRAGMA temp_store = MEMORY');
        },
        onCreate: (d, v) async => _createSchema(d),
        onUpgrade: (d, from, to) async => _migrate(d, from, to),
        onOpen: (d) async => _ensureSeed(d),
      ),
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Flushes the WAL so the .db file alone is a complete backup.
  Future<void> checkpoint() async {
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  Future<void> vacuum() async {
    await db.execute('VACUUM');
  }

  // ---------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------
  static Future<void> _createSchema(Database d) async {
    final batch = d.batch();

    batch.execute('''
      CREATE TABLE company (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        legal_name TEXT DEFAULT '',
        address1 TEXT DEFAULT '',
        address2 TEXT DEFAULT '',
        city TEXT DEFAULT '',
        state_code TEXT DEFAULT '',
        pincode TEXT DEFAULT '',
        gstin TEXT DEFAULT '',
        pan TEXT DEFAULT '',
        phone TEXT DEFAULT '',
        phone2 TEXT DEFAULT '',
        email TEXT DEFAULT '',
        website TEXT DEFAULT '',
        logo_path TEXT DEFAULT '',
        bank_name TEXT DEFAULT '',
        account_no TEXT DEFAULT '',
        ifsc TEXT DEFAULT '',
        branch TEXT DEFAULT '',
        upi_id TEXT DEFAULT '',
        jurisdiction TEXT DEFAULT '',
        licence_no TEXT DEFAULT ''
      )''');

    batch.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'CASHIER',
        active INTEGER NOT NULL DEFAULT 1,
        last_login TEXT
      )''');

    batch.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');

    batch.execute('''
      CREATE TABLE parties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL DEFAULT 'CUSTOMER',
        code TEXT DEFAULT '',
        name TEXT NOT NULL,
        contact_person TEXT DEFAULT '',
        phone TEXT DEFAULT '',
        phone2 TEXT DEFAULT '',
        email TEXT DEFAULT '',
        gstin TEXT DEFAULT '',
        pan TEXT DEFAULT '',
        address1 TEXT DEFAULT '',
        address2 TEXT DEFAULT '',
        city TEXT DEFAULT '',
        state_code TEXT DEFAULT '',
        pincode TEXT DEFAULT '',
        price_tier TEXT DEFAULT 'RETAIL',
        credit_limit REAL DEFAULT 0,
        credit_days INTEGER DEFAULT 0,
        opening_balance REAL DEFAULT 0,
        balance REAL DEFAULT 0,
        notes TEXT DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT
      )''');
    batch.execute('CREATE INDEX idx_parties_kind ON parties(kind, active)');
    batch.execute('CREATE INDEX idx_parties_name ON parties(name)');
    batch.execute('CREATE INDEX idx_parties_phone ON parties(phone)');

    batch.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sku TEXT DEFAULT '',
        barcode TEXT DEFAULT '',
        name TEXT NOT NULL,
        brand TEXT DEFAULT '',
        category TEXT DEFAULT '',
        hsn TEXT DEFAULT '',
        base_type TEXT DEFAULT '',
        shade_code TEXT DEFAULT '',
        shade_name TEXT DEFAULT '',
        color_hex TEXT DEFAULT '',
        pack_size TEXT DEFAULT '',
        unit TEXT DEFAULT 'LTR',
        mrp REAL DEFAULT 0,
        purchase_price REAL DEFAULT 0,
        retail_price REAL DEFAULT 0,
        dealer_price REAL DEFAULT 0,
        contractor_price REAL DEFAULT 0,
        gst_rate REAL DEFAULT 18,
        cess_rate REAL DEFAULT 0,
        tax_inclusive INTEGER DEFAULT 0,
        stock REAL DEFAULT 0,
        min_stock REAL DEFAULT 0,
        opening_stock REAL DEFAULT 0,
        rack TEXT DEFAULT '',
        is_service INTEGER DEFAULT 0,
        active INTEGER NOT NULL DEFAULT 1,
        notes TEXT DEFAULT '',
        created_at TEXT,
        updated_at TEXT
      )''');
    batch.execute(
        'CREATE UNIQUE INDEX idx_products_sku ON products(sku) WHERE sku <> \'\'');
    batch.execute('CREATE INDEX idx_products_barcode ON products(barcode)');
    batch.execute('CREATE INDEX idx_products_name ON products(name)');
    batch.execute('CREATE INDEX idx_products_active ON products(active)');

    batch.execute('''
      CREATE TABLE sales_docs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_type TEXT NOT NULL DEFAULT 'INVOICE',
        doc_no TEXT NOT NULL,
        doc_date TEXT NOT NULL,
        due_date TEXT,
        party_id INTEGER,
        party_name TEXT DEFAULT '',
        party_phone TEXT DEFAULT '',
        party_gstin TEXT DEFAULT '',
        party_address TEXT DEFAULT '',
        place_of_supply TEXT DEFAULT '',
        is_igst INTEGER DEFAULT 0,
        price_includes_tax INTEGER DEFAULT 0,
        price_tier TEXT DEFAULT 'RETAIL',
        gross_amount REAL DEFAULT 0,
        item_discount REAL DEFAULT 0,
        doc_discount_pct REAL DEFAULT 0,
        doc_discount_amt REAL DEFAULT 0,
        taxable_amount REAL DEFAULT 0,
        cgst REAL DEFAULT 0,
        sgst REAL DEFAULT 0,
        igst REAL DEFAULT 0,
        cess REAL DEFAULT 0,
        freight REAL DEFAULT 0,
        other_charges REAL DEFAULT 0,
        round_off REAL DEFAULT 0,
        total REAL DEFAULT 0,
        paid REAL DEFAULT 0,
        balance REAL DEFAULT 0,
        status TEXT DEFAULT 'UNPAID',
        payment_mode TEXT DEFAULT 'CASH',
        ref_no TEXT DEFAULT '',
        vehicle_no TEXT DEFAULT '',
        transport TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        user_id INTEGER,
        user_name TEXT DEFAULT '',
        ref_doc_id INTEGER,
        ref_doc_no TEXT DEFAULT '',
        created_at TEXT,
        FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE SET NULL
      )''');
    batch.execute(
        'CREATE UNIQUE INDEX idx_docs_no ON sales_docs(doc_type, doc_no)');
    batch.execute('CREATE INDEX idx_docs_date ON sales_docs(doc_date)');
    batch.execute('CREATE INDEX idx_docs_party ON sales_docs(party_id)');
    batch.execute('CREATE INDEX idx_docs_status ON sales_docs(status)');

    batch.execute('''
      CREATE TABLE sales_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id INTEGER NOT NULL,
        product_id INTEGER,
        sku TEXT DEFAULT '',
        name TEXT DEFAULT '',
        hsn TEXT DEFAULT '',
        shade TEXT DEFAULT '',
        pack_size TEXT DEFAULT '',
        unit TEXT DEFAULT '',
        qty REAL DEFAULT 0,
        free_qty REAL DEFAULT 0,
        mrp REAL DEFAULT 0,
        rate REAL DEFAULT 0,
        gross_rate REAL DEFAULT 0,
        discount_pct REAL DEFAULT 0,
        discount_amt REAL DEFAULT 0,
        taxable REAL DEFAULT 0,
        gst_rate REAL DEFAULT 0,
        cgst REAL DEFAULT 0,
        sgst REAL DEFAULT 0,
        igst REAL DEFAULT 0,
        cess_rate REAL DEFAULT 0,
        cess REAL DEFAULT 0,
        total REAL DEFAULT 0,
        cost_price REAL DEFAULT 0,
        batch TEXT DEFAULT '',
        notes TEXT DEFAULT '',
        FOREIGN KEY (doc_id) REFERENCES sales_docs(id) ON DELETE CASCADE
      )''');
    batch.execute('CREATE INDEX idx_items_doc ON sales_items(doc_id)');
    batch.execute('CREATE INDEX idx_items_product ON sales_items(product_id)');

    batch.execute('''
      CREATE TABLE purchase_docs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_type TEXT NOT NULL DEFAULT 'PURCHASE',
        doc_no TEXT NOT NULL,
        supplier_bill_no TEXT DEFAULT '',
        doc_date TEXT NOT NULL,
        bill_date TEXT,
        party_id INTEGER,
        party_name TEXT DEFAULT '',
        party_gstin TEXT DEFAULT '',
        place_of_supply TEXT DEFAULT '',
        is_igst INTEGER DEFAULT 0,
        taxable_amount REAL DEFAULT 0,
        cgst REAL DEFAULT 0,
        sgst REAL DEFAULT 0,
        igst REAL DEFAULT 0,
        cess REAL DEFAULT 0,
        discount_amt REAL DEFAULT 0,
        freight REAL DEFAULT 0,
        other_charges REAL DEFAULT 0,
        round_off REAL DEFAULT 0,
        total REAL DEFAULT 0,
        paid REAL DEFAULT 0,
        balance REAL DEFAULT 0,
        status TEXT DEFAULT 'UNPAID',
        payment_mode TEXT DEFAULT 'CREDIT',
        notes TEXT DEFAULT '',
        user_id INTEGER,
        created_at TEXT,
        FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE SET NULL
      )''');
    batch.execute(
        'CREATE UNIQUE INDEX idx_pdocs_no ON purchase_docs(doc_type, doc_no)');
    batch.execute('CREATE INDEX idx_pdocs_date ON purchase_docs(doc_date)');
    batch.execute('CREATE INDEX idx_pdocs_party ON purchase_docs(party_id)');

    batch.execute('''
      CREATE TABLE purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id INTEGER NOT NULL,
        product_id INTEGER,
        name TEXT DEFAULT '',
        hsn TEXT DEFAULT '',
        pack_size TEXT DEFAULT '',
        unit TEXT DEFAULT '',
        qty REAL DEFAULT 0,
        free_qty REAL DEFAULT 0,
        rate REAL DEFAULT 0,
        mrp REAL DEFAULT 0,
        sale_price REAL DEFAULT 0,
        discount_pct REAL DEFAULT 0,
        discount_amt REAL DEFAULT 0,
        taxable REAL DEFAULT 0,
        gst_rate REAL DEFAULT 0,
        cgst REAL DEFAULT 0,
        sgst REAL DEFAULT 0,
        igst REAL DEFAULT 0,
        cess REAL DEFAULT 0,
        total REAL DEFAULT 0,
        batch TEXT DEFAULT '',
        expiry TEXT,
        FOREIGN KEY (doc_id) REFERENCES purchase_docs(id) ON DELETE CASCADE
      )''');
    batch.execute('CREATE INDEX idx_pitems_doc ON purchase_items(doc_id)');

    batch.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucher_no TEXT DEFAULT '',
        date TEXT NOT NULL,
        direction TEXT NOT NULL DEFAULT 'IN',
        party_id INTEGER,
        party_name TEXT DEFAULT '',
        doc_id INTEGER,
        doc_no TEXT DEFAULT '',
        amount REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        mode TEXT DEFAULT 'CASH',
        ref_no TEXT DEFAULT '',
        bank_name TEXT DEFAULT '',
        cheque_date TEXT,
        notes TEXT DEFAULT '',
        user_id INTEGER,
        created_at TEXT,
        FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE SET NULL
      )''');
    batch.execute('CREATE INDEX idx_pay_party ON payments(party_id)');
    batch.execute('CREATE INDEX idx_pay_date ON payments(date)');

    batch.execute('''
      CREATE TABLE stock_moves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        product_name TEXT DEFAULT '',
        date TEXT NOT NULL,
        ref_type TEXT DEFAULT '',
        ref_id INTEGER,
        ref_no TEXT DEFAULT '',
        qty_in REAL DEFAULT 0,
        qty_out REAL DEFAULT 0,
        balance_after REAL DEFAULT 0,
        rate REAL DEFAULT 0,
        notes TEXT DEFAULT '',
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )''');
    batch.execute(
        'CREATE INDEX idx_moves_product ON stock_moves(product_id, date)');
    batch.execute('CREATE INDEX idx_moves_date ON stock_moves(date)');

    batch.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        category TEXT DEFAULT '',
        description TEXT DEFAULT '',
        amount REAL DEFAULT 0,
        mode TEXT DEFAULT 'CASH',
        ref_no TEXT DEFAULT '',
        user_id INTEGER
      )''');
    batch.execute('CREATE INDEX idx_exp_date ON expenses(date)');

    batch.execute('''
      CREATE TABLE held_bills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        label TEXT DEFAULT '',
        payload TEXT NOT NULL,
        created_at TEXT
      )''');

    batch.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        at TEXT NOT NULL,
        user_id INTEGER,
        user_name TEXT DEFAULT '',
        action TEXT DEFAULT '',
        entity TEXT DEFAULT '',
        entity_id INTEGER,
        detail TEXT DEFAULT ''
      )''');
    batch.execute('CREATE INDEX idx_audit_at ON audit_log(at)');

    await batch.commit(noResult: true);
  }

  static Future<void> _migrate(Database d, int from, int to) async {
    // Future schema revisions append their steps here, e.g.
    //   if (from < 2) { await d.execute('ALTER TABLE ...'); }
    // Every step must be idempotent and non-destructive.
  }

  // ---------------------------------------------------------------------
  // Seed / defaults
  // ---------------------------------------------------------------------
  static Future<void> _ensureSeed(Database d) async {
    final companyCount =
        firstInt(await d.rawQuery('SELECT COUNT(*) FROM company'));
    if (companyCount == 0) {
      await d.insert('company', {
        'id': 1,
        'name': 'My Paint Store',
        'legal_name': '',
        'state_code': '',
        'jurisdiction': '',
      });
    }

    final userCount = firstInt(await d.rawQuery('SELECT COUNT(*) FROM users'));
    if (userCount == 0) {
      // Default credentials: admin / admin123 (forced change on first run).
      await d.insert('users', {
        'name': 'Administrator',
        'username': 'admin',
        'password_hash':
            'a454aef7e48cb51917c79d5e2b0a83b5adf283c7e8fce3d0e36ac79621d41f1e',
        'salt': 'paintpro',
        'role': UserRole.admin,
        'active': 1,
      });
    }

    // Walk-in customer is id 1 and is never deleted.
    final walkIn = await d.query('parties',
        where: 'id = 1 AND kind = ?', whereArgs: ['CUSTOMER'], limit: 1);
    if (walkIn.isEmpty) {
      await d.insert('parties', {
        'id': 1,
        'kind': 'CUSTOMER',
        'code': 'WALK-IN',
        'name': 'Cash / Walk-in Customer',
        'price_tier': PriceTier.retail,
        'active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    const defaults = <String, String>{
      SKeys.invoicePrefix: 'INV-',
      SKeys.invoiceNext: '1',
      SKeys.estimatePrefix: 'EST-',
      SKeys.estimateNext: '1',
      SKeys.creditPrefix: 'CN-',
      SKeys.creditNext: '1',
      SKeys.purchasePrefix: 'PUR-',
      SKeys.purchaseNext: '1',
      SKeys.defaultGst: '18',
      SKeys.priceIncludesTax: '0',
      SKeys.roundOff: '1',
      SKeys.printFormat: PrintFormat.a5Landscape,
      SKeys.autoPrint: '1',
      SKeys.lowStockAlert: '1',
      SKeys.negativeStock: '0',
      SKeys.showBankOnInvoice: '1',
      SKeys.showUpiQr: '0',
      SKeys.themeMode: 'light',
      SKeys.accentColor: 'Ocean Blue',
      SKeys.terms: '1. Goods once sold will not be taken back or exchanged.\n'
          '2. Shade variation between batches is inherent to paint products.\n'
          '3. Interest @18% p.a. is chargeable on bills not paid within due date.\n'
          '4. Subject to local jurisdiction only.',
      SKeys.declaration:
          'We declare that this invoice shows the actual price of the goods '
              'described and that all particulars are true and correct.',
    };
    for (final e in defaults.entries) {
      await d.insert(
        'settings',
        {'key': e.key, 'value': e.value},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }
}
