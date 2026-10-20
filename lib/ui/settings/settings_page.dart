import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../data/repos/party_repo.dart';
import '../../data/repos/settings_repo.dart';
import '../../data/repos/user_repo.dart';
import '../../print/print_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _index = 0;

  static const _menu = <(String, IconData)>[
    ('Business profile', Icons.storefront_rounded),
    ('Billing & tax', Icons.receipt_long_rounded),
    ('Printing', Icons.print_rounded),
    ('Users & security', Icons.admin_panel_settings_rounded),
    ('Backup & data', Icons.backup_rounded),
    ('Appearance', Icons.palette_rounded),
    ('Keyboard shortcuts', Icons.keyboard_rounded),
    ('About', Icons.info_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 232,
          child: Container(
            color: AppTheme.subtleOf(context),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _menu.length,
              itemBuilder: (context, i) {
                final selected = i == _index;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                  child: Material(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _index = i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Row(
                          children: [
                            Icon(_menu[i].$2, size: 17),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_menu[i].$1,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  )),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Container(width: 1, color: AppTheme.borderOf(context)),
        Expanded(
          child: switch (_index) {
            0 => const _CompanySection(),
            1 => const _BillingSection(),
            2 => const _PrintingSection(),
            3 => const _UsersSection(),
            4 => const _BackupSection(),
            5 => const _AppearanceSection(),
            6 => const _ShortcutsSection(),
            _ => const _AboutSection(),
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Business profile
// ---------------------------------------------------------------------------
class _CompanySection extends StatefulWidget {
  const _CompanySection();

  @override
  State<_CompanySection> createState() => _CompanySectionState();
}

class _CompanySectionState extends State<_CompanySection> {
  final _formKey = GlobalKey<FormState>();
  late Company _c;
  late Map<String, TextEditingController> _f;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c = context.read<AppState>().company;
    _f = {
      'name': TextEditingController(text: _c.name),
      'legal': TextEditingController(text: _c.legalName),
      'address1': TextEditingController(text: _c.address1),
      'address2': TextEditingController(text: _c.address2),
      'city': TextEditingController(text: _c.city),
      'pincode': TextEditingController(text: _c.pincode),
      'gstin': TextEditingController(text: _c.gstin),
      'pan': TextEditingController(text: _c.pan),
      'phone': TextEditingController(text: _c.phone),
      'phone2': TextEditingController(text: _c.phone2),
      'email': TextEditingController(text: _c.email),
      'website': TextEditingController(text: _c.website),
      'bank': TextEditingController(text: _c.bankName),
      'account': TextEditingController(text: _c.accountNo),
      'ifsc': TextEditingController(text: _c.ifsc),
      'branch': TextEditingController(text: _c.branch),
      'upi': TextEditingController(text: _c.upiId),
      'jurisdiction': TextEditingController(text: _c.jurisdiction),
      'licence': TextEditingController(text: _c.licenceNo),
    };
    _ready = true;
  }

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    _c
      ..name = _f['name']!.text.trim()
      ..legalName = _f['legal']!.text.trim()
      ..address1 = _f['address1']!.text.trim()
      ..address2 = _f['address2']!.text.trim()
      ..city = _f['city']!.text.trim()
      ..pincode = _f['pincode']!.text.trim()
      ..gstin = _f['gstin']!.text.trim().toUpperCase()
      ..pan = _f['pan']!.text.trim().toUpperCase()
      ..phone = _f['phone']!.text.trim()
      ..phone2 = _f['phone2']!.text.trim()
      ..email = _f['email']!.text.trim()
      ..website = _f['website']!.text.trim()
      ..bankName = _f['bank']!.text.trim()
      ..accountNo = _f['account']!.text.trim()
      ..ifsc = _f['ifsc']!.text.trim().toUpperCase()
      ..branch = _f['branch']!.text.trim()
      ..upiId = _f['upi']!.text.trim()
      ..jurisdiction = _f['jurisdiction']!.text.trim()
      ..licenceNo = _f['licence']!.text.trim();

    final code = IndianStates.codeFromGstin(_c.gstin);
    if (code != null) _c.stateCode = code;

    await app.saveCompany(_c);
    if (!mounted) return;
    toast(context, 'Business details saved.', success: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    return _SettingsScaffold(
      title: 'Business profile',
      subtitle: 'These details appear on every invoice you print.',
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FormSubheader('Identity'),
            FieldRow([
              Field(
                label: 'Trade name (shown large on the bill) *',
                controller: _f['name'],
                validator: (v) => V.required(v, 'Shop name'),
              ),
              Field(
                  label: 'Legal name (if different)', controller: _f['legal']),
            ]),
            FieldRow([
              Field(
                label: 'GSTIN',
                controller: _f['gstin'],
                inputFormatters: Field.upper(15),
                validator: V.gstin,
                helper: 'Leave blank if you are not registered under GST',
                onChanged: (v) {
                  final code = IndianStates.codeFromGstin(v);
                  if (code != null) setState(() => _c.stateCode = code);
                },
              ),
              Field(
                  label: 'PAN',
                  controller: _f['pan'],
                  inputFormatters: Field.upper(10),
                  validator: V.pan),
              Field(
                  label: 'Drug / trade licence no', controller: _f['licence']),
            ]),
            const FormSubheader('Address'),
            FieldRow([
              Field(label: 'Address line 1', controller: _f['address1']),
              Field(label: 'Address line 2', controller: _f['address2']),
            ]),
            FieldRow([
              Field(label: 'City', controller: _f['city']),
              Field(
                  label: 'PIN code',
                  controller: _f['pincode'],
                  validator: V.pincode),
              Picker<String>(
                label: 'State *',
                value: _c.stateCode.isEmpty ? null : _c.stateCode,
                items: IndianStates.codes
                    .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text('$c · ${IndianStates.byCode[c]}',
                            overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setState(() => _c.stateCode = v ?? ''),
              ),
              Field(
                  label: 'Jurisdiction (for the bill footer)',
                  controller: _f['jurisdiction']),
            ]),
            const FormSubheader('Contact'),
            FieldRow([
              Field(
                  label: 'Phone', controller: _f['phone'], validator: V.phone),
              Field(label: 'Alternate phone', controller: _f['phone2']),
              Field(
                  label: 'Email', controller: _f['email'], validator: V.email),
              Field(label: 'Website', controller: _f['website']),
            ]),
            const FormSubheader('Bank details printed on the invoice'),
            FieldRow([
              Field(label: 'Bank name', controller: _f['bank']),
              Field(label: 'Account number', controller: _f['account']),
              Field(
                  label: 'IFSC',
                  controller: _f['ifsc'],
                  inputFormatters: Field.upper(11),
                  validator: V.ifsc),
              Field(label: 'Branch', controller: _f['branch']),
            ]),
            FieldRow([
              Field(
                  label: 'UPI ID',
                  controller: _f['upi'],
                  helper: 'e.g. yourshop@okhdfcbank'),
            ]),
            if (_c.stateCode.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: AppTheme.warning),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Set your state before billing — it decides whether a '
                        'sale carries CGST+SGST or IGST.',
                        style: TextStyle(fontSize: 12.5),
                      ),
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

// ---------------------------------------------------------------------------
// Billing & tax
// ---------------------------------------------------------------------------
class _BillingSection extends StatefulWidget {
  const _BillingSection();

  @override
  State<_BillingSection> createState() => _BillingSectionState();
}

class _BillingSectionState extends State<_BillingSection> {
  late final AppState _app;
  late final Map<String, TextEditingController> _f;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _f = {
      SKeys.invoicePrefix:
          TextEditingController(text: _app.settings.get(SKeys.invoicePrefix)),
      SKeys.invoiceNext:
          TextEditingController(text: _app.settings.get(SKeys.invoiceNext)),
      SKeys.estimatePrefix:
          TextEditingController(text: _app.settings.get(SKeys.estimatePrefix)),
      SKeys.estimateNext:
          TextEditingController(text: _app.settings.get(SKeys.estimateNext)),
      SKeys.creditPrefix:
          TextEditingController(text: _app.settings.get(SKeys.creditPrefix)),
      SKeys.creditNext:
          TextEditingController(text: _app.settings.get(SKeys.creditNext)),
      SKeys.purchasePrefix:
          TextEditingController(text: _app.settings.get(SKeys.purchasePrefix)),
      SKeys.purchaseNext:
          TextEditingController(text: _app.settings.get(SKeys.purchaseNext)),
      SKeys.terms: TextEditingController(text: _app.settings.get(SKeys.terms)),
      SKeys.declaration:
          TextEditingController(text: _app.settings.get(SKeys.declaration)),
    };
  }

  @override
  void dispose() {
    for (final c in _f.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await _app.setSettings({
      for (final e in _f.entries) e.key: e.value.text.trim(),
    });
    if (!mounted) return;
    toast(context, 'Billing preferences saved.', success: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return _SettingsScaffold(
      title: 'Billing & tax',
      subtitle:
          'Numbering, default tax behaviour and the wording printed at the '
          'bottom of each bill.',
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FormSubheader('Document numbering'),
          Text(
            'Use {FY} in a prefix to insert the financial year, e.g. '
            'INV/{FY}/ becomes INV/${SettingsRepo.financialYearLabel(DateTime.now())}/0001.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FieldRow([
            Field(label: 'Invoice prefix', controller: _f[SKeys.invoicePrefix]),
            Field(
                label: 'Next invoice number',
                controller: _f[SKeys.invoiceNext],
                inputFormatters: Field.integer),
            Field(
                label: 'Estimate prefix', controller: _f[SKeys.estimatePrefix]),
            Field(
                label: 'Next estimate number',
                controller: _f[SKeys.estimateNext],
                inputFormatters: Field.integer),
          ]),
          FieldRow([
            Field(
                label: 'Credit note prefix',
                controller: _f[SKeys.creditPrefix]),
            Field(
                label: 'Next credit note number',
                controller: _f[SKeys.creditNext],
                inputFormatters: Field.integer),
            Field(
                label: 'Purchase prefix', controller: _f[SKeys.purchasePrefix]),
            Field(
                label: 'Next purchase number',
                controller: _f[SKeys.purchaseNext],
                inputFormatters: Field.integer),
          ]),
          const FormSubheader('Tax behaviour'),
          Row(
            children: [
              SizedBox(
                width: 220,
                child: Picker<double>(
                  label: 'Default GST rate for new items',
                  value: app.defaultGst,
                  items: TaxRates.slabs
                      .map((r) => DropdownMenuItem(
                          value: r, child: Text('${Fmt.qty(r)} %')))
                      .toList(),
                  onChanged: (v) => app.setSetting(SKeys.defaultGst, v ?? 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _toggle(
            app,
            SKeys.priceIncludesTax,
            'Prices include GST by default',
            'Turn this on if you bill at MRP and want the tax worked '
                'backwards out of the price.',
          ),
          _toggle(
            app,
            SKeys.roundOff,
            'Round the bill total to the nearest rupee',
            'The difference is shown as a separate "Round off" line.',
            fallback: true,
          ),
          _toggle(
            app,
            SKeys.negativeStock,
            'Allow billing items that are out of stock',
            'Leave this off so the counter cannot sell what the shelf does '
                'not have.',
          ),
          _toggle(
            app,
            SKeys.lowStockAlert,
            'Warn me about low stock',
            'Shows a counter in the title bar and on the dashboard.',
            fallback: true,
          ),
          const FormSubheader('Invoice footer'),
          Field(
            label: 'Terms & conditions',
            controller: _f[SKeys.terms],
            maxLines: 5,
          ),
          const SizedBox(height: 12),
          Field(
            label: 'Declaration',
            controller: _f[SKeys.declaration],
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _toggle(AppState app, String key, String title, String subtitle,
      {bool fallback = false}) {
    return SwitchListTile(
      value: app.settings.getBool(key, fallback),
      onChanged: (v) => app.setSetting(key, v ? 1 : 0),
      title: Text(title, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      contentPadding: EdgeInsets.zero,
    );
  }
}

// ---------------------------------------------------------------------------
// Printing
// ---------------------------------------------------------------------------
class _PrintingSection extends StatefulWidget {
  const _PrintingSection();

  @override
  State<_PrintingSection> createState() => _PrintingSectionState();
}

class _PrintingSectionState extends State<_PrintingSection> {
  List<String> _printers = const [];
  bool _loadingPrinters = true;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    final list = await PrintService.printers();
    if (!mounted) return;
    setState(() {
      _printers = list.map((p) => p.name).toList();
      _loadingPrinters = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return _SettingsScaffold(
      title: 'Printing',
      subtitle: 'Paper size, automatic printing and the printers Windows sees.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FormSubheader('Bill format'),
          for (final entry in PrintFormat.label.entries)
            RadioListTile<String>(
              value: entry.key,
              // ignore: deprecated_member_use
              groupValue: app.printFormat,
              // ignore: deprecated_member_use
              onChanged: (v) => app.setSetting(SKeys.printFormat, v),
              title: Text(entry.value, style: const TextStyle(fontSize: 13.5)),
              subtitle: Text(_hint(entry.key),
                  style: const TextStyle(fontSize: 11.5)),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: app.autoPrint,
            onChanged: (v) => app.setSetting(SKeys.autoPrint, v ? 1 : 0),
            title: const Text('Send straight to the default printer',
                style: TextStyle(fontSize: 13.5)),
            subtitle: const Text(
                'F9 prints without showing the Windows print dialog. Turn off '
                'to choose a printer each time.',
                style: TextStyle(fontSize: 12)),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: app.settings.getBool(SKeys.showBankOnInvoice, true),
            onChanged: (v) =>
                app.setSetting(SKeys.showBankOnInvoice, v ? 1 : 0),
            title: const Text('Print bank details on the invoice',
                style: TextStyle(fontSize: 13.5)),
            contentPadding: EdgeInsets.zero,
          ),
          const FormSubheader('Printers found on this computer'),
          if (_loadingPrinters)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_printers.isEmpty)
            Text(
              'No printers detected. Install the printer in Windows first, '
              'then reopen this screen.',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in _printers)
                  Chip(
                    avatar: const Icon(Icons.print_rounded, size: 15),
                    label: Text(p, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loadPrinters,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Refresh printer list'),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.subtleOf(context),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Setting up A5 horizontal printing',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  '1. In Windows, open Printers & scanners › your printer › '
                  'Printing preferences.\n'
                  '2. Set the paper size to A5 and the orientation to '
                  'Landscape.\n'
                  '3. Set margins to "None" or the minimum the printer allows.\n'
                  '4. For a dot-matrix printer, define a custom size of '
                  '210 x 148 mm.\n'
                  'Amounts print as "Rs." rather than the ₹ symbol so the '
                  'bill renders identically on every printer, including older '
                  'dot-matrix models.',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _hint(String key) => switch (key) {
        PrintFormat.a5Landscape =>
          '210 x 148 mm — two bills per A4 sheet, the usual counter format',
        PrintFormat.a5Portrait => '148 x 210 mm — taller layout, fewer columns',
        PrintFormat.a4 => '210 x 297 mm — full page, best for B2B invoices',
        _ => 'Continuous roll for a thermal receipt printer',
      };
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------
class _UsersSection extends StatefulWidget {
  const _UsersSection();

  @override
  State<_UsersSection> createState() => _UsersSectionState();
}

class _UsersSectionState extends State<_UsersSection> {
  final _repo = UserRepo();
  List<AppUser> _users = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await _repo.all();
    if (!mounted) return;
    setState(() {
      _users = rows;
      _loading = false;
    });
  }

  Future<void> _edit([AppUser? u]) async {
    final name = TextEditingController(text: u?.name ?? '');
    final username = TextEditingController(text: u?.username ?? '');
    final password = TextEditingController();
    var role = u?.role ?? UserRole.cashier;
    var active = u?.active ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(u == null ? 'New user' : 'Edit ${u.name}',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FieldRow([
                  Field(label: 'Full name *', controller: name),
                ]),
                FieldRow([
                  Field(label: 'Username *', controller: username),
                  Picker<String>(
                    label: 'Role',
                    value: role,
                    items: UserRole.all
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) =>
                        setLocal(() => role = v ?? UserRole.cashier),
                  ),
                ]),
                FieldRow([
                  Field(
                    label: u == null ? 'Password *' : 'New password (optional)',
                    controller: password,
                    obscure: true,
                  ),
                ], bottom: 0),
                if (u != null)
                  SwitchListTile(
                    value: active,
                    onChanged: (v) => setLocal(() => active = v),
                    title:
                        const Text('Active', style: TextStyle(fontSize: 13.5)),
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: 8),
                Text(
                  'Cashiers can bill and take payments. Managers can also '
                  'cancel bills and edit masters. Admins can do everything, '
                  'including restoring a backup.',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
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
                child: const Text('Save')),
          ],
        ),
      ),
    );

    final n = name.text.trim();
    final un = username.text.trim();
    final pw = password.text;
    name.dispose();
    username.dispose();
    password.dispose();
    if (ok != true) return;

    if (n.isEmpty || un.isEmpty || (u == null && pw.isEmpty)) {
      if (mounted) {
        toast(context, 'Name, username and password are required.',
            error: true);
      }
      return;
    }
    if (await _repo.usernameTaken(un, exceptId: u?.id)) {
      if (mounted) {
        toast(context, 'That username is already taken.', error: true);
      }
      return;
    }
    if (u == null) {
      await _repo.create(AppUser(name: n, username: un, role: role), pw);
    } else {
      if (!active &&
          u.role == UserRole.admin &&
          await _repo.isLastAdmin(u.id!)) {
        if (mounted) {
          toast(context, 'You cannot deactivate the only admin account.',
              error: true);
        }
        return;
      }
      u
        ..name = n
        ..username = un
        ..role = role
        ..active = active;
      await _repo.update(u, newPassword: pw.isEmpty ? null : pw);
    }
    await _load();
    if (mounted) toast(context, 'User saved.', success: true);
  }

  Future<void> _changeOwnPassword() async {
    final userId = context.read<AppState>().user?.id;
    if (userId == null) return;
    final oldPw = TextEditingController();
    final newPw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change my password', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Field(
                  label: 'Current password',
                  controller: oldPw,
                  obscure: true,
                  autofocus: true),
              const SizedBox(height: 12),
              Field(label: 'New password', controller: newPw, obscure: true),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change')),
        ],
      ),
    );
    final o = oldPw.text;
    final n = newPw.text;
    oldPw.dispose();
    newPw.dispose();
    if (ok != true || n.isEmpty) return;

    final done = await _repo.changePassword(userId, o, n);
    if (!mounted) return;
    toast(
        context, done ? 'Password changed.' : 'Current password is incorrect.',
        success: done, error: !done);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return _SettingsScaffold(
      title: 'Users & security',
      subtitle: 'Every bill records who created it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: app.isAdmin ? () => _edit() : null,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Add user'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _changeOwnPassword,
                icon: const Icon(Icons.password_rounded, size: 17),
                label: const Text('Change my password'),
              ),
              if (!app.isAdmin) ...[
                const SizedBox(width: 12),
                Text('Only an admin can add or edit users.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            for (final u in _users)
              AppCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.subtleOf(context),
                      child: Text(
                          u.name.isEmpty
                              ? '?'
                              : u.name.characters.first.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(u.name,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600)),
                          Text(
                            '@${u.username}'
                            '${u.lastLogin == null ? '' : '  ·  last login ${Fmt.dateTime(u.lastLogin)}'}',
                            style: TextStyle(
                                fontSize: 11.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(u.role,
                        color: u.isAdmin ? AppTheme.brand : AppTheme.info),
                    const SizedBox(width: 10),
                    if (!u.active) const StatusPill('INACTIVE'),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 17),
                      onPressed: app.isAdmin ? () => _edit(u) : null,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backup & data
// ---------------------------------------------------------------------------
class _BackupSection extends StatefulWidget {
  const _BackupSection();

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  bool _busy = false;

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    final app = context.read<AppState>();
    try {
      final file = await app.backups.backupTo(app.backupDir);
      await app.settings
          .set(SKeys.lastBackup, DateTime.now().toIso8601String());
      if (!mounted) return;
      toast(context, 'Backup saved to ${file.path}', success: true);
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null || !mounted) return;
    await context.read<AppState>().setSetting(SKeys.backupDir, dir);
    if (!mounted) return;
    toast(context, 'Backups will now be written to $dir', success: true);
  }

  Future<void> _restore() async {
    final app = context.read<AppState>();
    if (!app.isAdmin) {
      toast(context, 'Only an admin can restore a backup.', error: true);
      return;
    }
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PaintPro backup', extensions: ['db'])
      ],
    );
    if (file == null || !mounted) return;
    final ok = await confirm(
      context,
      title: 'Restore this backup?',
      message:
          'Everything recorded since that backup will be lost. Your current '
          'data is kept alongside as a .pre-restore file. The app closes '
          'afterwards and must be reopened.',
      confirmLabel: 'Restore and close',
      destructive: true,
    );
    if (!ok) return;
    try {
      await app.backups.restoreFrom(file.path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore complete'),
          content: const Text(
              'Please close and reopen PaintPro to load the restored data.'),
          actions: [
            ElevatedButton(
              onPressed: () => exit(0),
              child: const Text('Close now'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Restore failed: $e', error: true);
    }
  }

  Future<void> _compact() async {
    setState(() => _busy = true);
    await AppDb.instance.checkpoint();
    await AppDb.instance.vacuum();
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context, 'Database compacted.', success: true);
  }

  Future<void> _recalc() async {
    setState(() => _busy = true);
    final n = await PartyRepo().recalculateBalances();
    if (!mounted) return;
    setState(() => _busy = false);
    toast(context,
        n == 0 ? 'All party balances already match.' : 'Corrected $n balances.',
        success: true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final last = app.settings.get(SKeys.lastBackup);
    return _SettingsScaffold(
      title: 'Backup & data',
      subtitle:
          'Your data lives in a single file on this computer. Keep a copy on '
          'a pen drive or cloud folder.',
      child: BusyOverlay(
        busy: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('Backup', icon: Icons.backup_rounded),
                  _kv('Database file', AppDb.instance.path),
                  _kv('Backup folder', app.backupDir),
                  _kv(
                      'Last backup',
                      last.isEmpty
                          ? 'never'
                          : Fmt.dateTime(Fmt.parseIso(last))),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _backupNow,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Back up now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _chooseFolder,
                        icon: const Icon(Icons.folder_open_rounded, size: 17),
                        label: const Text('Change backup folder'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _restore,
                        icon: const Icon(Icons.restore_rounded, size: 17),
                        label: const Text('Restore from backup…'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'A backup runs automatically the first time you sign in '
                    'each day, and the last 30 copies are kept.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle('Maintenance', icon: Icons.build_rounded),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _compact,
                        icon: const Icon(Icons.compress_rounded, size: 17),
                        label: const Text('Compact database'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _recalc,
                        icon: const Icon(Icons.calculate_rounded, size: 17),
                        label: const Text('Recalculate party balances'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Compacting reclaims space after large deletions. '
                    'Recalculating rebuilds every customer and supplier '
                    'balance from the underlying vouchers.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(k,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Expanded(
              child: SelectableText(v, style: const TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return _SettingsScaffold(
      title: 'Appearance',
      subtitle: 'Pick what is easiest on the eyes at your counter.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FormSubheader('Theme'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'light',
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_rounded, size: 16)),
              ButtonSegment(
                  value: 'dark',
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_rounded, size: 16)),
            ],
            selected: {app.settings.get(SKeys.themeMode, 'light')},
            showSelectedIcon: false,
            onSelectionChanged: (s) => app.setSetting(SKeys.themeMode, s.first),
          ),
          const FormSubheader('Accent colour'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final e in AppTheme.accents.entries)
                InkWell(
                  onTap: () => app.setSetting(SKeys.accentColor, e.key),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 150,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: app.settings.get(SKeys.accentColor) == e.key
                            ? e.value
                            : AppTheme.borderOf(context),
                        width: app.settings.get(SKeys.accentColor) == e.key
                            ? 2
                            : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: e.value,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(e.key, style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shortcuts & About
// ---------------------------------------------------------------------------
class _ShortcutsSection extends StatelessWidget {
  const _ShortcutsSection();

  static const _rows = <(String, String, String)>[
    ('F2', 'Speed billing', 'Jump to the counter screen, focus the search box'),
    ('F3', 'Customer', 'Pick or create the customer for this bill'),
    ('F4', 'Park bill', 'Hold the current bill and start a fresh one'),
    ('F5', 'Recall', 'Bring back a parked bill'),
    ('F6', 'Bill discount', 'Apply a percentage or flat discount'),
    ('F7', 'Charge line', 'Add tinting, labour or delivery charges'),
    ('F8', 'Payment', 'Choose mode, enter cash received, see change'),
    ('F9', 'Save & print', 'Save the bill and send it to the printer'),
    ('F10', 'Save only', 'Save without printing'),
    ('F12', 'Preview', 'See the bill exactly as it will print'),
    ('Esc', 'Clear bill', 'Empty the current bill'),
    ('Ctrl + Del', 'Remove line', 'Delete the selected line'),
    ('Alt + 1…9', 'Navigate', 'Jump between the main screens'),
    ('3 * code', 'Quantity', 'Type a quantity, star, then the item code'),
  ];

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Keyboard shortcuts',
      subtitle: 'The whole billing flow works without touching the mouse.',
      child: Column(
        children: [
          for (final r in _rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppTheme.borderOf(context))),
              ),
              child: Row(
                children: [
                  SizedBox(width: 110, child: KeyHint(r.$1)),
                  SizedBox(
                    width: 150,
                    child: Text(r.$2,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(r.$3,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'About',
      subtitle: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.brandDark,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.format_paint_rounded,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(AppInfo.appName,
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  Text('Version ${AppInfo.version}',
                      style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'GST billing, stock and accounts for Indian paint retailers.\n'
            'Runs fully offline — nothing leaves this computer.',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle('What this software does not do',
                    icon: Icons.info_outline_rounded),
                Text(
                  '· It does not file your GST returns. It prepares GSTR-1 and '
                  'GSTR-3B figures from your own books; filing happens on the '
                  'GST portal.\n'
                  '· It does not talk to the e-invoice (IRP) or e-way bill '
                  'portals. Shops below the turnover threshold do not need '
                  'them.\n'
                  '· It does not replace an accountant. Reconcile input tax '
                  'credit against GSTR-2B before you file.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.7,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared settings page frame
// ---------------------------------------------------------------------------
class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    this.onSave,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Future<void> Function()? onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  ],
                ),
              ),
              if (onSave != null)
                ElevatedButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Save changes'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: child,
          ),
        ),
      ],
    );
  }
}
