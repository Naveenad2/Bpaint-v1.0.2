import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/party_repo.dart';
import '../widgets/common.dart';
import 'party_editor.dart';

/// Keyboard-first party chooser: type to filter, arrows to move,
/// Enter to select, Ctrl+N to create on the fly.
class PartyPicker extends StatefulWidget {
  const PartyPicker({super.key, this.kind = 'CUSTOMER'});

  final String kind;

  static Future<Party?> show(BuildContext context, {String kind = 'CUSTOMER'}) {
    return showDialog<Party>(
      context: context,
      builder: (_) => PartyPicker(kind: kind),
    );
  }

  @override
  State<PartyPicker> createState() => _PartyPickerState();
}

class _PartyPickerState extends State<PartyPicker> {
  final _repo = PartyRepo();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();

  List<Party> _results = const [];
  int _highlight = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows =
        await _repo.all(kind: widget.kind, query: _search.text, limit: 300);
    if (!mounted) return;
    setState(() {
      _results = rows;
      _highlight = 0;
      _loading = false;
    });
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _highlight = (_highlight + delta).clamp(0, _results.length - 1);
    });
    // Keep the highlighted row on screen (rows are a fixed 52 px tall).
    if (_scroll.hasClients) {
      final target = (_highlight * 52.0) - 100;
      _scroll.animateTo(
        target.clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
      );
    }
  }

  void _choose([Party? p]) {
    final party = p ?? (_results.isEmpty ? null : _results[_highlight]);
    if (party == null) return;
    Navigator.pop(context, party);
  }

  Future<void> _create() async {
    final created = await PartyEditor.show(context, kind: widget.kind);
    if (created != null && mounted) Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
            const SingleActivator(LogicalKeyboardKey.enter): _choose,
            const SingleActivator(LogicalKeyboardKey.numpadEnter): _choose,
            const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                _create,
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogHeader(
                icon: widget.kind == 'SUPPLIER'
                    ? Icons.store_mall_directory_rounded
                    : Icons.people_alt_rounded,
                title:
                    'Select ${widget.kind == 'SUPPLIER' ? 'Supplier' : 'Customer'}',
                subtitle: '↑ ↓ to move · Enter to select · Ctrl+N to add new',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Field(
                  label: 'Search by name, phone, code or GSTIN',
                  controller: _search,
                  focusNode: _searchFocus,
                  autofocus: true,
                  prefix: const Icon(Icons.search_rounded, size: 18),
                  onChanged: (_) => _load(),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? EmptyState(
                            title: 'No match',
                            message: 'Press Ctrl+N to add a new party.',
                            icon: Icons.person_search_rounded,
                            action: ElevatedButton.icon(
                              onPressed: _create,
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add new'),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            itemCount: _results.length,
                            itemExtent: 52,
                            itemBuilder: (context, i) {
                              final p = _results[i];
                              final selected = i == _highlight;
                              return InkWell(
                                onTap: () => _choose(p),
                                child: Container(
                                  color: selected
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.10)
                                      : null,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 15,
                                        backgroundColor:
                                            AppTheme.subtleOf(context),
                                        child: Text(
                                          p.name.isEmpty
                                              ? '?'
                                              : p.name.characters.first
                                                  .toUpperCase(),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(p.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            Text(
                                              [
                                                p.code,
                                                if (p.phone.isNotEmpty) p.phone,
                                                if (p.gstin.isNotEmpty) p.gstin,
                                                if (p.city.isNotEmpty) p.city,
                                              ].join('  ·  '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (p.priceTier != 'RETAIL')
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: StatusPill(p.priceTier,
                                              color: AppTheme.info),
                                        ),
                                      if (p.balance.abs() > 0.5)
                                        Money(p.balance,
                                            size: 12.5,
                                            bold: true,
                                            color: p.balance > 0
                                                ? AppTheme.danger
                                                : AppTheme.success),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Text('${_results.length} found',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _create,
                      icon: const Icon(Icons.person_add_alt_rounded, size: 17),
                      label: const Text('Add new  (Ctrl+N)'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _results.isEmpty ? null : _choose,
                      child: const Text('Select'),
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
}
