import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../db.dart';
import '../models.dart';

/// Products, stock levels and the stock ledger.
class ProductRepo {
  Database get _db => AppDb.instance.db;

  Future<List<Product>> all({
    String query = '',
    String brand = '',
    String category = '',
    bool onlyActive = true,
    bool onlyLowStock = false,
    int limit = 5000,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (onlyActive) where.add('active = 1');
    if (brand.isNotEmpty) {
      where.add('brand = ?');
      args.add(brand);
    }
    if (category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    if (onlyLowStock) where.add('is_service = 0 AND stock <= min_stock');
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add('(name LIKE ? OR sku LIKE ? OR barcode LIKE ? '
          'OR brand LIKE ? OR shade_code LIKE ? OR shade_name LIKE ?)');
      final like = '%$q%';
      args.addAll([like, like, like, like, like, like]);
    }
    final rows = await _db.query('products',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'name COLLATE NOCASE, pack_size',
        limit: limit);
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> byId(int? id) async {
    if (id == null) return null;
    final rows = await _db.query('products', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// Exact match on barcode or SKU — the scanner path in speed billing.
  Future<Product?> byCode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final rows = await _db.query('products',
        where: '(barcode = ? OR sku = ?) AND active = 1',
        whereArgs: [c, c],
        limit: 1);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<bool> skuTaken(String sku, {int? exceptId}) async {
    final s = sku.trim();
    if (s.isEmpty) return false;
    final rows = await _db.query('products',
        where: 'sku = ?${exceptId != null ? ' AND id <> ?' : ''}',
        whereArgs: [s, if (exceptId != null) exceptId]);
    return rows.isNotEmpty;
  }

  Future<List<String>> brands() => _distinct('brand');
  Future<List<String>> categories() => _distinct('category');

  Future<List<String>> _distinct(String column) async {
    final rows = await _db.rawQuery(
        "SELECT DISTINCT $column AS v FROM products "
        "WHERE $column IS NOT NULL AND $column <> '' ORDER BY v COLLATE NOCASE");
    return rows.map((r) => (r['v'] ?? '') as String).toList();
  }

  Future<int> save(Product p) async {
    p.createdAt ??= DateTime.now();
    p.updatedAt = DateTime.now();
    if (p.id == null) {
      if (p.sku.trim().isEmpty) p.sku = await _nextSku();
      final id = await _db.insert('products', p.toMap());
      if (p.openingStock != 0 && !p.isService) {
        await _postMove(
          _db,
          productId: id,
          productName: p.fullName,
          refType: StockRef.opening,
          qtyIn: p.openingStock,
          balanceAfter: p.openingStock,
          rate: p.purchasePrice,
          notes: 'Opening stock',
        );
        await _db.update('products', {'stock': p.openingStock},
            where: 'id = ?', whereArgs: [id]);
      }
      return id;
    }
    // Stock is only ever moved through documents or explicit adjustments.
    final map = p.toMap()..remove('stock');
    await _db.update('products', map, where: 'id = ?', whereArgs: [p.id]);
    return p.id!;
  }

  Future<String> _nextSku() async {
    final n = firstInt(await _db.rawQuery('SELECT COUNT(*) FROM products'));
    return 'P${(n + 1).toString().padLeft(5, '0')}';
  }

  Future<String> deleteOrDeactivate(int id) async {
    final used = firstInt(await _db.rawQuery(
        'SELECT COUNT(*) FROM sales_items WHERE product_id = ?', [id]));
    final purchased = firstInt(await _db.rawQuery(
        'SELECT COUNT(*) FROM purchase_items WHERE product_id = ?', [id]));
    if (used + purchased > 0) {
      await _db.update('products', {'active': 0},
          where: 'id = ?', whereArgs: [id]);
      return 'Item has transactions — marked inactive instead of deleted.';
    }
    await _db.delete('products', where: 'id = ?', whereArgs: [id]);
    return 'Deleted.';
  }

  // ------------------------------------------------------------------
  // Stock
  // ------------------------------------------------------------------
  Future<double> stockOf(int productId) async {
    final rows = await _db.query('products',
        columns: ['stock'], where: 'id = ?', whereArgs: [productId]);
    return rows.isEmpty ? 0 : Fmt.toDouble(rows.first['stock']);
  }

  /// Moves stock and writes the ledger row. Call inside the caller's
  /// transaction so a bill and its stock can never diverge.
  static Future<void> moveStock(
    DatabaseExecutor txn, {
    required int productId,
    required String productName,
    required double delta, // + inward, - outward
    required String refType,
    int? refId,
    String refNo = '',
    double rate = 0,
    String notes = '',
    DateTime? date,
  }) async {
    if (delta == 0) return;
    final rows = await txn.query('products',
        columns: ['stock', 'is_service'],
        where: 'id = ?',
        whereArgs: [productId]);
    if (rows.isEmpty) return;
    if (Fmt.toBool(rows.first['is_service'])) return; // services hold no stock

    final current = Fmt.toDouble(rows.first['stock']);
    final next = Fmt.round(current + delta, 3);
    await txn.update('products', {'stock': next},
        where: 'id = ?', whereArgs: [productId]);
    await _postMove(
      txn,
      productId: productId,
      productName: productName,
      refType: refType,
      refId: refId,
      refNo: refNo,
      qtyIn: delta > 0 ? delta : 0,
      qtyOut: delta < 0 ? -delta : 0,
      balanceAfter: next,
      rate: rate,
      notes: notes,
      date: date,
    );
  }

  static Future<void> _postMove(
    DatabaseExecutor txn, {
    required int productId,
    required String productName,
    required String refType,
    int? refId,
    String refNo = '',
    double qtyIn = 0,
    double qtyOut = 0,
    double balanceAfter = 0,
    double rate = 0,
    String notes = '',
    DateTime? date,
  }) async {
    await txn.insert('stock_moves', {
      'product_id': productId,
      'product_name': productName,
      'date': (date ?? DateTime.now()).toIso8601String(),
      'ref_type': refType,
      'ref_id': refId,
      'ref_no': refNo,
      'qty_in': qtyIn,
      'qty_out': qtyOut,
      'balance_after': balanceAfter,
      'rate': rate,
      'notes': notes,
    });
  }

  /// Manual stock correction (damage, physical count, transfer).
  Future<void> adjust({
    required Product product,
    required double newQty,
    required String reason,
    String refType = StockRef.adjustment,
  }) async {
    final delta = Fmt.round(newQty - product.stock, 3);
    if (delta == 0) return;
    await _db.transaction((txn) async {
      await moveStock(
        txn,
        productId: product.id!,
        productName: product.fullName,
        delta: delta,
        refType: refType,
        notes: reason,
        rate: product.purchasePrice,
      );
    });
  }

  Future<List<StockMove>> moves(int productId, {int limit = 300}) async {
    final rows = await _db.query('stock_moves',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'date DESC, id DESC',
        limit: limit);
    return rows.map(StockMove.fromMap).toList();
  }

  Future<List<Product>> lowStock({int limit = 200}) => all(
        onlyLowStock: true,
        limit: limit,
      );

  /// Total stock valuation at cost and at selling price.
  Future<(double, double, double)> valuation() async {
    final rows = await _db.rawQuery('''
      SELECT COALESCE(SUM(stock * purchase_price), 0) AS cost,
             COALESCE(SUM(stock * CASE WHEN retail_price > 0
                                       THEN retail_price ELSE mrp END), 0) AS sale,
             COALESCE(SUM(stock), 0) AS qty
      FROM products WHERE active = 1 AND is_service = 0
    ''');
    final r = rows.first;
    return (
      Fmt.toDouble(r['cost']),
      Fmt.toDouble(r['sale']),
      Fmt.toDouble(r['qty'])
    );
  }

  /// Bulk price revision — used when a brand announces a rate change.
  Future<int> bulkPriceChange({
    String brand = '',
    String category = '',
    required double percent,
    bool alsoMrp = true,
  }) async {
    final factor = 1 + percent / 100;
    final where = <String>['active = 1'];
    final args = <Object?>[];
    if (brand.isNotEmpty) {
      where.add('brand = ?');
      args.add(brand);
    }
    if (category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    return _db.rawUpdate('''
      UPDATE products SET
        retail_price = ROUND(retail_price * $factor, 2),
        dealer_price = ROUND(dealer_price * $factor, 2),
        contractor_price = ROUND(contractor_price * $factor, 2)
        ${alsoMrp ? ', mrp = ROUND(mrp * $factor, 2)' : ''}
      WHERE ${where.join(' AND ')}
    ''', args);
  }
}
