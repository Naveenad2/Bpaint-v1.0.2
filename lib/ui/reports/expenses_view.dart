import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/report_repo.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Shop running costs — rent, salary, electricity, transport. These feed the
/// net-profit line on the sales summary.
class ExpensesView extends StatefulWidget {
  const ExpensesView({super.key, required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  @override
  State<ExpensesView> createState() => _ExpensesViewState();
}

class _ExpensesViewState extends State<ExpensesView> {
  final _repo = ReportRepo();
  List<Expense> _rows = const [];
  bool _loading = true;

  static const categories = [
    'Rent',
    'Salary & wages',
    'Electricity',
    'Transport & freight',
    'Packing material',
    'Printing & stationery',
    'Telephone & internet',
    'Repairs & maintenance',
    'Bank charges',
    'Marketing',
    'Miscellaneous',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ExpensesView old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _repo.expenses(widget.from, widget.to);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _edit([Expense? e]) async {
    final userId = context.read<AppState>().user?.id;
    final amount =
        TextEditingController(text: e == null ? '' : Fmt.qty(e.amount));
    final desc = TextEditingController(text: e?.description ?? '');
    final ref = TextEditingController(text: e?.refNo ?? '');
    var category = e?.category ?? categories.last;
    var mode = e?.mode ?? PaymentModes.cash;
    var date = e?.date ?? DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(e == null ? 'Record expense' : 'Edit expense',
              style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FieldRow([
                  Picker<String>(
                    label: 'Category',
                    value: category,
                    items: ({...categories, category}.toList())
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setLocal(() => category = v ?? categories.last),
                  ),
                  Field(
                    label: 'Amount *',
                    controller: amount,
                    inputFormatters: Field.decimal,
                  ),
                ]),
                FieldRow([
                  Field(label: 'Description', controller: desc),
                ]),
                FieldRow([
                  Picker<String>(
                    label: 'Paid by',
                    value: mode,
                    items: PaymentModes.all
                        .where((m) => m != PaymentModes.credit)
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) =>
                        setLocal(() => mode = v ?? PaymentModes.cash),
                  ),
                  Field(label: 'Reference', controller: ref),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setLocal(() => date = d);
                    },
                    icon: const Icon(Icons.event_rounded, size: 16),
                    label: Text(Fmt.date(date)),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ], bottom: 0),
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

    final value = Fmt.toDouble(amount.text);
    final description = desc.text.trim();
    final reference = ref.text.trim();
    amount.dispose();
    desc.dispose();
    ref.dispose();
    if (ok != true || value <= 0) return;

    await _repo.saveExpense(Expense(
      id: e?.id,
      date: date,
      category: category,
      description: description,
      amount: value,
      mode: mode,
      refNo: reference,
      userId: userId,
    ));
    await _load();
  }

  Future<void> _delete(Expense e) async {
    final ok = await confirm(
      context,
      title: 'Delete this expense?',
      message: '${e.category} · ${Fmt.money(e.amount)}',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await _repo.deleteExpense(e.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0.0, (s, e) => s + e.amount);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppTheme.subtleOf(context),
          child: Row(
            children: [
              Text('${_rows.length} entries',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 20),
              const Text('Total: ', style: TextStyle(fontSize: 12)),
              Money(total, size: 13.5, bold: true, color: AppTheme.danger),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Record expense'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
                  ? EmptyState(
                      title: 'No expenses recorded',
                      message:
                          'Track rent, salary, electricity and freight here to '
                          'see a real net-profit figure.',
                      icon: Icons.payments_rounded,
                      action: ElevatedButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Record expense'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemExtent: 48,
                      itemBuilder: (context, i) {
                        final e = _rows[i];
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: AppTheme.borderOf(context),
                                    width: 0.5)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              SizedBox(
                                  width: 100,
                                  child: Text(Fmt.date(e.date),
                                      style: const TextStyle(fontSize: 12.5))),
                              SizedBox(
                                  width: 180,
                                  child: Text(e.category,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600))),
                              Expanded(
                                  child: Text(e.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5))),
                              SizedBox(
                                  width: 90,
                                  child: Text(e.mode,
                                      style: const TextStyle(fontSize: 12))),
                              SizedBox(
                                  width: 110,
                                  child: Money(e.amount, size: 13, bold: true)),
                              IconButton(
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                onPressed: () => _edit(e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 17),
                                onPressed: () => _delete(e),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
