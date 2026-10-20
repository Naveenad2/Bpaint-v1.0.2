import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../data/models.dart';
import '../../data/repos/product_repo.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Create / edit a paint product. Understands brand, base, shade and pack
/// size, which is how a paint counter actually identifies an item.
class ProductEditor extends StatefulWidget {
  const ProductEditor({super.key, this.product, this.seedName});

  final Product? product;
  final String? seedName;

  static Future<Product?> show(BuildContext context,
      {Product? product, String? seedName}) {
    return showDialog<Product>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductEditor(product: product, seedName: seedName),
    );
  }

  @override
  State<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<ProductEditor> {
  final _formKey = GlobalKey<FormState>();
  final _repo = ProductRepo();

  late Product _p;
  late final Map<String, TextEditingController> _c;
  List<String> _brands = const [];
  List<String> _categories = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _p = widget.product?.copy() ?? Product();
    if (widget.seedName != null && _p.name.isEmpty) _p.name = widget.seedName!;
    _c = {
      'sku': TextEditingController(text: _p.sku),
      'barcode': TextEditingController(text: _p.barcode),
      'name': TextEditingController(text: _p.name),
      'brand': TextEditingController(text: _p.brand),
      'category': TextEditingController(text: _p.category),
      'hsn': TextEditingController(text: _p.hsn),
      'shadeCode': TextEditingController(text: _p.shadeCode),
      'shadeName': TextEditingController(text: _p.shadeName),
      'pack': TextEditingController(text: _p.packSize),
      'mrp': TextEditingController(text: _num(_p.mrp)),
      'purchase': TextEditingController(text: _num(_p.purchasePrice)),
      'retail': TextEditingController(text: _num(_p.retailPrice)),
      'dealer': TextEditingController(text: _num(_p.dealerPrice)),
      'contractor': TextEditingController(text: _num(_p.contractorPrice)),
      'stock': TextEditingController(text: _num(_p.openingStock)),
      'minStock': TextEditingController(text: _num(_p.minStock)),
      'rack': TextEditingController(text: _p.rack),
      'notes': TextEditingController(text: _p.notes),
    };
    _loadLookups();
  }

  static String _num(double v) => v == 0 ? '' : Fmt.qty(v);

  Future<void> _loadLookups() async {
    final b = await _repo.brands();
    final c = await _repo.categories();
    if (!mounted) return;
    setState(() {
      _brands = b;
      _categories = c;
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final sku = _c['sku']!.text.trim();
    if (sku.isNotEmpty && await _repo.skuTaken(sku, exceptId: _p.id)) {
      if (!mounted) return;
      toast(context, 'That item code is already used by another product.',
          error: true);
      return;
    }
    setState(() => _busy = true);
    _p
      ..sku = sku
      ..barcode = _c['barcode']!.text.trim()
      ..name = _c['name']!.text.trim()
      ..brand = _c['brand']!.text.trim()
      ..category = _c['category']!.text.trim()
      ..hsn = _c['hsn']!.text.trim()
      ..shadeCode = _c['shadeCode']!.text.trim()
      ..shadeName = _c['shadeName']!.text.trim()
      ..packSize = _c['pack']!.text.trim()
      ..mrp = Fmt.toDouble(_c['mrp']!.text)
      ..purchasePrice = Fmt.toDouble(_c['purchase']!.text)
      ..retailPrice = Fmt.toDouble(_c['retail']!.text)
      ..dealerPrice = Fmt.toDouble(_c['dealer']!.text)
      ..contractorPrice = Fmt.toDouble(_c['contractor']!.text)
      ..minStock = Fmt.toDouble(_c['minStock']!.text)
      ..rack = _c['rack']!.text.trim()
      ..notes = _c['notes']!.text.trim();
    if (widget.product == null) {
      _p.openingStock = Fmt.toDouble(_c['stock']!.text);
    }
    // Retail price defaults to MRP so a bill never goes out at zero.
    if (_p.retailPrice == 0 && _p.mrp > 0) _p.retailPrice = _p.mrp;

    try {
      final id = await _repo.save(_p);
      _p.id = id;
      final fresh = await _repo.byId(id);
      if (!mounted) return;
      Navigator.pop(context, fresh ?? _p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'Could not save: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    if (widget.product == null && _p.gstRate == 18) {
      _p.gstRate = app.defaultGst;
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: BusyOverlay(
          busy: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                icon: Icons.palette_rounded,
                title: widget.product == null ? 'New Item' : 'Edit Item',
                subtitle: widget.product?.fullName ??
                    'Paint, primer, putty, hardware or a service charge',
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FieldRow([
                          Field(
                            label: 'Item name *',
                            controller: _c['name'],
                            autofocus: true,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => V.required(v, 'Item name'),
                          ),
                        ]),
                        FieldRow([
                          _suggest('Brand', _c['brand']!, _brands),
                          _suggest('Category', _c['category']!, _categories),
                          Picker<String>(
                            label: 'Base',
                            value: _p.baseType.isEmpty ? '—' : _p.baseType,
                            items: _baseOptions
                                .map((b) =>
                                    DropdownMenuItem(value: b, child: Text(b)))
                                .toList(),
                            onChanged: (v) => setState(
                                () => _p.baseType = (v == '—' ? '' : v ?? '')),
                          ),
                        ]),
                        FieldRow([
                          Field(
                            label: 'Shade code',
                            controller: _c['shadeCode'],
                            hint: 'e.g. AP-7132',
                          ),
                          Field(
                            label: 'Shade name',
                            controller: _c['shadeName'],
                            hint: 'e.g. Sandstone',
                            textCapitalization: TextCapitalization.words,
                          ),
                          _packField(),
                          Picker<String>(
                            label: 'Unit',
                            value: _p.unit,
                            items: _unitOptions
                                .map((u) =>
                                    DropdownMenuItem(value: u, child: Text(u)))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _p.unit = v ?? 'LTR'),
                          ),
                        ]),
                        const FormSubheader('Codes & tax'),
                        FieldRow([
                          Field(
                            label: 'Item code / SKU',
                            controller: _c['sku'],
                            helper: 'Leave blank to auto-generate',
                          ),
                          Field(
                            label: 'Barcode',
                            controller: _c['barcode'],
                            helper: 'Scan directly into this box',
                          ),
                          Field(
                            label: 'HSN code',
                            controller: _c['hsn'],
                            validator: V.hsn,
                            helper: 'Paints 3208/3209 · Putty 3214',
                          ),
                          Picker<double>(
                            label: 'GST rate',
                            value: _p.gstRate,
                            items: _gstOptions
                                .map((r) => DropdownMenuItem(
                                    value: r, child: Text('${Fmt.qty(r)} %')))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _p.gstRate = v ?? 18),
                          ),
                        ]),
                        const FormSubheader('Pricing'),
                        FieldRow([
                          Field(
                            label: 'Purchase price',
                            controller: _c['purchase'],
                            inputFormatters: Field.decimal,
                            onChanged: (_) => setState(() {}),
                          ),
                          Field(
                            label: 'MRP',
                            controller: _c['mrp'],
                            inputFormatters: Field.decimal,
                          ),
                          Field(
                            label: 'Retail price *',
                            controller: _c['retail'],
                            inputFormatters: Field.decimal,
                            onChanged: (_) => setState(() {}),
                          ),
                          Field(
                            label: 'Dealer price',
                            controller: _c['dealer'],
                            inputFormatters: Field.decimal,
                          ),
                          Field(
                            label: 'Contractor price',
                            controller: _c['contractor'],
                            inputFormatters: Field.decimal,
                          ),
                        ]),
                        _marginHint(),
                        const FormSubheader('Stock'),
                        FieldRow([
                          Field(
                            label: widget.product == null
                                ? 'Opening stock'
                                : 'Current stock',
                            controller: _c['stock'],
                            inputFormatters: Field.decimal,
                            enabled: widget.product == null,
                            helper: widget.product == null
                                ? null
                                : 'Change stock from Inventory › Adjust',
                          ),
                          Field(
                            label: 'Low-stock alert at',
                            controller: _c['minStock'],
                            inputFormatters: Field.decimal,
                          ),
                          Field(
                              label: 'Rack / location', controller: _c['rack']),
                        ]),
                        FieldRow(
                            [Field(label: 'Notes', controller: _c['notes'])]),
                        Row(
                          children: [
                            Expanded(
                              child: SwitchListTile(
                                value: _p.isService,
                                onChanged: (v) =>
                                    setState(() => _p.isService = v),
                                title: const Text('Service / charge item',
                                    style: TextStyle(fontSize: 13.5)),
                                subtitle: const Text(
                                    'Tinting, labour or delivery — no stock kept',
                                    style: TextStyle(fontSize: 11.5)),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                            Expanded(
                              child: SwitchListTile(
                                value: _p.active,
                                onChanged: (v) => setState(() => _p.active = v),
                                title: const Text('Active',
                                    style: TextStyle(fontSize: 13.5)),
                                subtitle: const Text(
                                    'Inactive items are hidden from billing',
                                    style: TextStyle(fontSize: 11.5)),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Save item'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _marginHint() {
    final cost = Fmt.toDouble(_c['purchase']!.text);
    final sale = Fmt.toDouble(_c['retail']!.text);
    if (cost <= 0 || sale <= 0) return const SizedBox(height: 4);
    final margin = Fmt.round((sale - cost) / cost * 100, 1);
    final profit = Fmt.round(sale - cost);
    final ok = margin >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(ok ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 16,
              color: ok ? Colors.green.shade700 : Colors.red.shade700),
          const SizedBox(width: 6),
          Text(
            'Margin ${Fmt.qty(margin)}%  ·  ${Fmt.money(profit)} per '
            '${_p.unit.toLowerCase()} before tax',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ok ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _packField() => SuggestField(
        label: 'Pack size',
        controller: _c['pack']!,
        options: PackSizes.all,
        hint: '4 LTR',
      );

  Widget _suggest(String label, TextEditingController controller,
          List<String> options) =>
      SuggestField(
        label: label,
        controller: controller,
        options: options,
        capitalizeWords: true,
      );

  /// Every dropdown includes the item's own stored value, so a legacy or
  /// imported record can never trip a "value not among items" assertion.
  List<double> get _gstOptions =>
      {...TaxRates.slabs, _p.gstRate}.toList()..sort();

  List<String> get _unitOptions =>
      {...Units.all, if (_p.unit.isNotEmpty) _p.unit}.toList();

  List<String> get _baseOptions =>
      {..._bases, if (_p.baseType.isNotEmpty) _p.baseType}.toList();

  static const List<String> _bases = [
    '—',
    'White Base',
    'Pastel Base',
    'Light Base',
    'Deep Base',
    'Ultra Deep Base',
    'Ready Mix',
  ];
}
