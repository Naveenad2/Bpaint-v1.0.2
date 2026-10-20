import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../data/models.dart';
import '../../data/repos/party_repo.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Create / edit a customer or supplier.
class PartyEditor extends StatefulWidget {
  const PartyEditor({super.key, required this.kind, this.party});

  final String kind;
  final Party? party;

  static Future<Party?> show(BuildContext context,
      {required String kind, Party? party}) {
    return showDialog<Party>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PartyEditor(kind: kind, party: party),
    );
  }

  @override
  State<PartyEditor> createState() => _PartyEditorState();
}

class _PartyEditorState extends State<PartyEditor> {
  final _formKey = GlobalKey<FormState>();
  final _repo = PartyRepo();

  late Party _p;
  late final Map<String, TextEditingController> _c;
  bool _busy = false;

  bool get _isSupplier => widget.kind == 'SUPPLIER';

  @override
  void initState() {
    super.initState();
    _p = widget.party?.copy() ?? Party(kind: widget.kind);
    _c = {
      'name': TextEditingController(text: _p.name),
      'contact': TextEditingController(text: _p.contactPerson),
      'phone': TextEditingController(text: _p.phone),
      'phone2': TextEditingController(text: _p.phone2),
      'email': TextEditingController(text: _p.email),
      'gstin': TextEditingController(text: _p.gstin),
      'pan': TextEditingController(text: _p.pan),
      'address1': TextEditingController(text: _p.address1),
      'address2': TextEditingController(text: _p.address2),
      'city': TextEditingController(text: _p.city),
      'pincode': TextEditingController(text: _p.pincode),
      'creditLimit': TextEditingController(
          text: _p.creditLimit == 0 ? '' : Fmt.qty(_p.creditLimit)),
      'creditDays': TextEditingController(
          text: _p.creditDays == 0 ? '' : '${_p.creditDays}'),
      'opening': TextEditingController(
          text: _p.openingBalance == 0 ? '' : Fmt.qty(_p.openingBalance)),
      'notes': TextEditingController(text: _p.notes),
    };
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
    setState(() => _busy = true);
    _p
      ..name = _c['name']!.text.trim()
      ..contactPerson = _c['contact']!.text.trim()
      ..phone = _c['phone']!.text.trim()
      ..phone2 = _c['phone2']!.text.trim()
      ..email = _c['email']!.text.trim()
      ..gstin = _c['gstin']!.text.trim().toUpperCase()
      ..pan = _c['pan']!.text.trim().toUpperCase()
      ..address1 = _c['address1']!.text.trim()
      ..address2 = _c['address2']!.text.trim()
      ..city = _c['city']!.text.trim()
      ..pincode = _c['pincode']!.text.trim()
      ..creditLimit = Fmt.toDouble(_c['creditLimit']!.text)
      ..creditDays = Fmt.toInt(_c['creditDays']!.text)
      ..openingBalance = Fmt.toDouble(_c['opening']!.text)
      ..notes = _c['notes']!.text.trim();

    // A GSTIN carries its own state code — trust it over the dropdown.
    final fromGstin = IndianStates.codeFromGstin(_p.gstin);
    if (fromGstin != null) _p.stateCode = fromGstin;

    try {
      final id = await _repo.save(_p);
      _p.id = id;
      if (!mounted) return;
      Navigator.pop(context, _p);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'Could not save: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    _p.stateCode = _p.stateCode.isEmpty ? app.company.stateCode : _p.stateCode;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 660),
        child: BusyOverlay(
          busy: _busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                icon: _isSupplier
                    ? Icons.store_mall_directory_rounded
                    : Icons.person_add_alt_1_rounded,
                title: widget.party == null
                    ? 'New ${_isSupplier ? 'Supplier' : 'Customer'}'
                    : 'Edit ${_p.name}',
                subtitle: widget.party?.code ?? 'A code is generated on save',
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
                        _row([
                          Field(
                            label: 'Name *',
                            controller: _c['name'],
                            autofocus: true,
                            textCapitalization: TextCapitalization.words,
                            validator: (v) => V.required(v, 'Name'),
                          ),
                          Field(
                            label: 'Contact person',
                            controller: _c['contact'],
                            textCapitalization: TextCapitalization.words,
                          ),
                        ]),
                        _row([
                          Field(
                            label: 'Mobile',
                            controller: _c['phone'],
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            validator: V.phone,
                          ),
                          Field(
                            label: 'Alternate phone',
                            controller: _c['phone2'],
                            keyboardType: TextInputType.phone,
                          ),
                          Field(
                            label: 'Email',
                            controller: _c['email'],
                            validator: V.email,
                          ),
                        ]),
                        _row([
                          Field(
                            label: 'GSTIN',
                            controller: _c['gstin'],
                            inputFormatters: Field.upper(15),
                            validator: V.gstin,
                            helper: 'Leave blank for a walk-in (B2C) buyer',
                            onChanged: (v) {
                              final code = IndianStates.codeFromGstin(v);
                              if (code != null && code != _p.stateCode) {
                                setState(() => _p.stateCode = code);
                              }
                            },
                          ),
                          Field(
                            label: 'PAN',
                            controller: _c['pan'],
                            inputFormatters: Field.upper(10),
                            validator: V.pan,
                          ),
                        ]),
                        const SizedBox(height: 4),
                        const FormSubheader('Address'),
                        _row([
                          Field(
                              label: 'Address line 1',
                              controller: _c['address1']),
                          Field(
                              label: 'Address line 2',
                              controller: _c['address2']),
                        ]),
                        _row([
                          Field(label: 'City', controller: _c['city']),
                          Field(
                            label: 'PIN code',
                            controller: _c['pincode'],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            validator: V.pincode,
                          ),
                          Picker<String>(
                            label: 'State (Place of Supply)',
                            value: _p.stateCode.isEmpty ? null : _p.stateCode,
                            items: IndianStates.codes
                                .map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                          '$c · ${IndianStates.byCode[c]}',
                                          overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _p.stateCode = v ?? ''),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        const FormSubheader('Commercial terms'),
                        _row([
                          if (!_isSupplier)
                            Picker<String>(
                              label: 'Price list',
                              value: _p.priceTier,
                              items: PriceTier.all
                                  .map((t) => DropdownMenuItem(
                                      value: t, child: Text(_tierLabel(t))))
                                  .toList(),
                              onChanged: (v) => setState(
                                  () => _p.priceTier = v ?? PriceTier.retail),
                            ),
                          Field(
                            label: 'Credit limit',
                            controller: _c['creditLimit'],
                            inputFormatters: Field.decimal,
                            prefix: const Icon(Icons.currency_rupee_rounded,
                                size: 15),
                          ),
                          Field(
                            label: 'Credit days',
                            controller: _c['creditDays'],
                            inputFormatters: Field.integer,
                          ),
                        ]),
                        _row([
                          Field(
                            label: 'Opening balance',
                            controller: _c['opening'],
                            inputFormatters: Field.decimal,
                            enabled: widget.party == null,
                            helper: _isSupplier
                                ? 'Amount you already owe this supplier'
                                : 'Amount this customer already owes you',
                          ),
                          Field(label: 'Notes', controller: _c['notes']),
                        ]),
                        if (widget.party != null) ...[
                          const SizedBox(height: 10),
                          SwitchListTile(
                            value: _p.active,
                            onChanged: (v) => setState(() => _p.active = v),
                            title: const Text('Active',
                                style: TextStyle(fontSize: 13.5)),
                            subtitle: const Text(
                                'Inactive parties are hidden from billing',
                                style: TextStyle(fontSize: 12)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
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
                    if (widget.party?.id != null)
                      Text('Balance: ${Fmt.money(_p.balance)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Save'),
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

  static String _tierLabel(String t) => switch (t) {
        PriceTier.dealer => 'Dealer',
        PriceTier.contractor => 'Contractor / Painter',
        _ => 'Retail (MRP)',
      };

  Widget _row(List<Widget> children) => FieldRow(children);
}
