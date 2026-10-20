import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/backup_repo.dart';
import '../../data/demo_data.dart';
import '../../data/repos/product_repo.dart';
import '../../print/print_service.dart';
import '../../print/report_pdf.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'product_editor.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final _repo = ProductRepo();
  final _backup = BackupRepo();
  final _search = TextEditingController();

  List<Product> _rows = const [];
  List<String> _brands = const [];
  List<String> _categories = const [];
  final Set<int> _selected = {};
  String _brand = '';
  String _category = '';
  bool _lowOnly = false;
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
      brand: _brand,
      category: _category,
      onlyLowStock: _lowOnly,
      onlyActive: false,
    );
    final brands = await _repo.brands();
    final cats = await _repo.categories();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _brands = brands;
      _categories = cats;
      _selected.removeWhere((id) => !rows.any((p) => p.id == id));
      _loading = false;
    });
  }

  Future<void> _edit([Product? p]) async {
    final saved = await ProductEditor.show(context, product: p);
    if (saved != null) {
      await _load();
      if (mounted) await context.read<AppState>().refreshAlerts();
    }
  }

  Future<void> _delete(Product p) async {
    final ok = await confirm(
      context,
      title: 'Remove ${p.name}?',
      message: 'Items that appear on past bills are kept but marked inactive.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    final msg = await _repo.deleteOrDeactivate(p.id!);
    await _load();
    if (mounted) toast(context, msg);
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (file == null) return;
    final result = await _backup.importProducts(file.path);
    await _load();
    if (!mounted) return;
    toast(context, 'Import finished — ${result.summary}',
        success: result.ok, error: !result.ok);
    if (result.errors.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Rows that could not be imported'),
          content: SizedBox(
            width: 520,
            height: 320,
            child: ListView(
              children: result.errors
                  .map((e) => Text(e, style: const TextStyle(fontSize: 12)))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
          ],
        ),
      );
    }
  }

  Future<void> _export() async {
    final loc = await getSaveLocation(
      suggestedName: 'products_${Fmt.stamp(DateTime.now())}.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (loc == null) return;
    await _backup.exportProducts(loc.path, _rows);
    if (!mounted) return;
    toast(context, 'Exported ${_rows.length} items.', success: true);
  }

  Future<void> _template() async {
    final loc = await getSaveLocation(
      suggestedName: 'paintpro_item_template.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv'])
      ],
    );
    if (loc == null) return;
    await _backup.productTemplate(loc.path);
    if (!mounted) return;
    toast(context, 'Template saved. Fill it in Excel and import.',
        success: true);
  }

  Future<void> _labels() async {
    final chosen = _selected.isEmpty
        ? _rows.take(24).toList()
        : _rows.where((p) => _selected.contains(p.id)).toList();
    if (chosen.isEmpty) {
      toast(context, 'No items to print.', error: true);
      return;
    }
    final app = context.read<AppState>();
    final bytes = await ReportPdf.barcodeLabels(
      company: app.company,
      products: chosen,
    );
    if (!mounted) return;
    await PrintService.previewBytes(
      context,
      title: 'Barcode labels',
      bytes: bytes,
      fileName: 'labels.pdf',
    );
  }

  Future<void> _loadDemo() async {
    final ok = await confirm(
      context,
      title: 'Load the sample catalogue?',
      message: 'Adds about 35 typical paint, primer, putty and accessory items '
          'with stock, plus a few sample customers and suppliers, so you can '
          'try billing straight away. You can delete them later.',
      confirmLabel: 'Load samples',
    );
    if (!ok || !mounted) return;
    final app = context.read<AppState>();
    final n = await DemoData.load(stateCode: app.company.stateCode);
    await _load();
    if (!mounted) return;
    await app.refreshAlerts();
    if (mounted) toast(context, 'Added $n sample records.', success: true);
  }

  Future<void> _bulkPrice() async {
    final controller = TextEditingController();
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bulk price revision'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _brand.isEmpty && _category.isEmpty
                    ? 'This changes every active item. Filter by brand or '
                        'category first to limit the scope.'
                    : 'Applies to '
                        '${[
                        _brand,
                        _category
                      ].where((e) => e.isNotEmpty).join(' · ')}.',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Field(
                label: 'Change by %  (use -5 to reduce)',
                controller: controller,
                autofocus: true,
              ),
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
    );
    final pct = Fmt.toDouble(controller.text);
    controller.dispose();
    if (applied != true || pct == 0) return;
    final n = await _repo.bulkPriceChange(
        brand: _brand, category: _category, percent: pct);
    await _load();
    if (mounted) toast(context, 'Updated $n items.', success: true);
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
                  label: 'Search items by name, code, brand, shade or barcode',
                  controller: _search,
                  prefix: const Icon(Icons.search_rounded, size: 18),
                  onChanged: (_) => _load(),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 170,
                child: Picker<String>(
                  label: 'Brand',
                  value: _brand,
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('All brands')),
                    ..._brands
                        .map((b) => DropdownMenuItem(value: b, child: Text(b))),
                  ],
                  onChanged: (v) {
                    setState(() => _brand = v ?? '');
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 190,
                child: Picker<String>(
                  label: 'Category',
                  value: _category,
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('All categories')),
                    ..._categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  ],
                  onChanged: (v) {
                    setState(() => _category = v ?? '');
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilterChip(
                selected: _lowOnly,
                onSelected: (v) {
                  setState(() => _lowOnly = v);
                  _load();
                },
                avatar: const Icon(Icons.warning_amber_rounded, size: 15),
                label: const Text('Low stock'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New item'),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (v) async {
                  switch (v) {
                    case 'import':
                      await _import();
                    case 'export':
                      await _export();
                    case 'template':
                      await _template();
                    case 'labels':
                      await _labels();
                    case 'price':
                      await _bulkPrice();
                    case 'demo':
                      await _loadDemo();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'import', child: Text('Import from CSV…')),
                  PopupMenuItem(
                      value: 'template', child: Text('Download CSV template')),
                  PopupMenuItem(value: 'export', child: Text('Export to CSV')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                      value: 'labels', child: Text('Print barcode labels')),
                  PopupMenuItem(
                      value: 'price', child: Text('Bulk price revision…')),
                  PopupMenuDivider(),
                  PopupMenuItem(
                      value: 'demo', child: Text('Load sample catalogue')),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppTheme.subtleOf(context),
          child: Row(
            children: [
              Text('${_rows.length} items',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 20),
              Text(
                'Stock at cost ${Fmt.money(_rows.fold<double>(0.0, (s, p) => s + p.stock * p.purchasePrice))}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              if (_selected.isNotEmpty)
                Text('${_selected.length} selected',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? EmptyState(
                      title: 'No items yet',
                      message:
                          'Add your first paint, primer or hardware item — or '
                          'import your catalogue from a CSV file.',
                      icon: Icons.palette_rounded,
                      action: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _edit(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('New item'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: _import,
                            icon:
                                const Icon(Icons.upload_file_rounded, size: 18),
                            label: const Text('Import CSV'),
                          ),
                          const SizedBox(width: 10),
                          TextButton.icon(
                            onPressed: _loadDemo,
                            icon: const Icon(Icons.auto_awesome_rounded,
                                size: 18),
                            label: const Text('Load sample catalogue'),
                          ),
                        ],
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

  Widget _row(Product p, int index) {
    final out = !p.isService && p.stock <= 0;
    return InkWell(
      onTap: () => _edit(p),
      child: Container(
        decoration: BoxDecoration(
          color: index.isEven
              ? null
              : AppTheme.subtleOf(context).withValues(alpha: 0.5),
          border: Border(
              bottom:
                  BorderSide(color: AppTheme.borderOf(context), width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Checkbox(
                value: _selected.contains(p.id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selected.add(p.id!);
                  } else {
                    _selected.remove(p.id);
                  }
                }),
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(p.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              decoration:
                                  p.active ? null : TextDecoration.lineThrough,
                            )),
                      ),
                      if (p.isService) ...[
                        const SizedBox(width: 6),
                        const StatusPill('SERVICE', color: AppTheme.info),
                      ],
                    ],
                  ),
                  Text(
                    [
                      p.sku,
                      if (p.barcode.isNotEmpty) p.barcode,
                      if (p.category.isNotEmpty) p.category,
                      'HSN ${p.hsn}',
                      if (p.rack.isNotEmpty) 'Rack ${p.rack}',
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(p.packSize,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center),
            ),
            SizedBox(
                width: 84,
                child: Money(p.purchasePrice, size: 12.5, symbol: false)),
            SizedBox(
                width: 84,
                child: Money(p.retailPrice,
                    size: 12.5, bold: true, symbol: false)),
            SizedBox(width: 74, child: Money(p.mrp, size: 12.5, symbol: false)),
            SizedBox(
              width: 60,
              child: Text('${Fmt.qty(p.gstRate)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
            SizedBox(
              width: 108,
              child: p.isService
                  ? const Text('—', textAlign: TextAlign.center)
                  : Text(
                      '${Fmt.qty(p.stock)} ${p.unit}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: out
                            ? AppTheme.danger
                            : (p.lowStock ? AppTheme.warning : null),
                      ),
                    ),
            ),
            SizedBox(
              width: 76,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    onPressed: () => _edit(p),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline_rounded, size: 17),
                    onPressed: () => _delete(p),
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
