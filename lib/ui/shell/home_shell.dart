import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../billing/speed_billing_page.dart';
import '../dashboard/dashboard_page.dart';
import '../inventory/inventory_page.dart';
import '../invoices/invoices_page.dart';
import '../parties/parties_page.dart';
import '../payments/payments_page.dart';
import '../products/products_page.dart';
import '../purchases/purchases_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../widgets/common.dart';

class NavEntry {
  final String label;
  final IconData icon;
  final Widget page;
  final String shortcut;
  final bool managerOnly;

  const NavEntry(this.label, this.icon, this.page,
      {this.shortcut = '', this.managerOnly = false});
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 1;
  bool _railExpanded = true;

  static const List<NavEntry> _entries = [
    NavEntry('Dashboard', Icons.space_dashboard_rounded, DashboardPage(),
        shortcut: 'Alt+1'),
    NavEntry('Speed Billing', Icons.bolt_rounded, SpeedBillingPage(),
        shortcut: 'F2'),
    NavEntry('Invoices', Icons.receipt_long_rounded, InvoicesPage(),
        shortcut: 'Alt+3'),
    NavEntry(
        'Customers', Icons.people_alt_rounded, PartiesPage(kind: 'CUSTOMER'),
        shortcut: 'Alt+4'),
    NavEntry('Products', Icons.palette_rounded, ProductsPage(),
        shortcut: 'Alt+5'),
    NavEntry('Purchases', Icons.local_shipping_rounded, PurchasesPage(),
        shortcut: 'Alt+6'),
    NavEntry('Suppliers', Icons.store_mall_directory_rounded,
        PartiesPage(kind: 'SUPPLIER'),
        shortcut: 'Alt+7'),
    NavEntry('Inventory', Icons.inventory_2_rounded, InventoryPage(),
        shortcut: 'Alt+8'),
    NavEntry('Payments', Icons.account_balance_wallet_rounded, PaymentsPage(),
        shortcut: 'Alt+9'),
    NavEntry('Reports', Icons.insights_rounded, ReportsPage()),
    NavEntry('Settings', Icons.settings_rounded, SettingsPage()),
  ];

  void _go(int i) {
    if (i < 0 || i >= _entries.length) return;
    if (_index != i) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.f2): const _GoIntent(1),
        const SingleActivator(LogicalKeyboardKey.digit1, alt: true):
            const _GoIntent(0),
        const SingleActivator(LogicalKeyboardKey.digit2, alt: true):
            const _GoIntent(1),
        const SingleActivator(LogicalKeyboardKey.digit3, alt: true):
            const _GoIntent(2),
        const SingleActivator(LogicalKeyboardKey.digit4, alt: true):
            const _GoIntent(3),
        const SingleActivator(LogicalKeyboardKey.digit5, alt: true):
            const _GoIntent(4),
        const SingleActivator(LogicalKeyboardKey.digit6, alt: true):
            const _GoIntent(5),
        const SingleActivator(LogicalKeyboardKey.digit7, alt: true):
            const _GoIntent(6),
        const SingleActivator(LogicalKeyboardKey.digit8, alt: true):
            const _GoIntent(7),
        const SingleActivator(LogicalKeyboardKey.digit9, alt: true):
            const _GoIntent(8),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _GoIntent: CallbackAction<_GoIntent>(
            onInvoke: (intent) {
              _go(intent.index);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Row(
              children: [
                _Sidebar(
                  entries: _entries,
                  index: _index,
                  expanded: _railExpanded,
                  onSelect: _go,
                  onToggle: () =>
                      setState(() => _railExpanded = !_railExpanded),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        title: _entries[_index].label,
                        onOpenSettings: () => _go(_entries.length - 1),
                        onNewBill: () => _go(1),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: IndexedStack(
                          index: _index,
                          children: [for (final e in _entries) e.page],
                        ),
                      ),
                      _StatusBar(app: app),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoIntent extends Intent {
  const _GoIntent(this.index);
  final int index;
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.entries,
    required this.index,
    required this.expanded,
    required this.onSelect,
    required this.onToggle,
  });

  final List<NavEntry> entries;
  final int index;
  final bool expanded;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF11161B) : AppTheme.brandDark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: expanded ? 214 : 62,
      color: bg,
      child: Column(
        children: [
          const SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 8),
            child: Row(
              mainAxisAlignment:
                  expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.format_paint_rounded,
                      size: 19, color: Colors.white),
                ),
                if (expanded) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          AppInfo.shortName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          app.company.name.isEmpty
                              ? 'Set up your shop'
                              : app.company.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final selected = i == index;
                final item = Container(
                  margin: const EdgeInsets.only(bottom: 3),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: expanded ? 10 : 0, vertical: 9),
                        child: Row(
                          mainAxisAlignment: expanded
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          children: [
                            Icon(
                              e.icon,
                              size: 18,
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.62),
                            ),
                            if (expanded) ...[
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  e.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                              ),
                              if (e.shortcut.isNotEmpty)
                                Text(
                                  e.shortcut,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.white.withValues(alpha: 0.38),
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
                return expanded ? item : Tooltip(message: e.label, child: item);
              },
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
          IconButton(
            tooltip: expanded ? 'Collapse menu' : 'Expand menu',
            onPressed: onToggle,
            icon: Icon(
              expanded
                  ? Icons.keyboard_double_arrow_left_rounded
                  : Icons.keyboard_double_arrow_right_rounded,
              color: Colors.white.withValues(alpha: 0.65),
              size: 19,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onOpenSettings,
    required this.onNewBill,
  });

  final String title;
  final VoidCallback onOpenSettings;
  final VoidCallback onNewBill;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;

    return Container(
      height: 54,
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1B2027)
          : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 16),
          if (app.lowStockCount > 0)
            StatusPill('${app.lowStockCount} low stock',
                color: AppTheme.warning, icon: Icons.warning_amber_rounded),
          const Spacer(),
          FilledButton.icon(
            onPressed: onNewBill,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Bill  (F2)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Toggle light / dark',
            onPressed: app.toggleTheme,
            icon: Icon(
              app.themeMode == ThemeMode.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
              size: 19,
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Account',
            offset: const Offset(0, 44),
            onSelected: (v) async {
              switch (v) {
                case 'settings':
                  onOpenSettings();
                case 'lock':
                  await context.read<AppState>().signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_rounded, size: 18),
                  title: Text('Settings'),
                ),
              ),
              PopupMenuItem(
                value: 'lock',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_rounded, size: 18),
                  title: Text('Sign out'),
                ),
              ),
            ],
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    (user?.name ?? '?').characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.name ?? '',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(user?.role ?? '',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                  ],
                ),
                const Icon(Icons.arrow_drop_down_rounded, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(fontSize: 11, color: muted);
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: AppTheme.subtleOf(context),
        border: Border(top: BorderSide(color: AppTheme.borderOf(context))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: AppTheme.success),
          const SizedBox(width: 6),
          Text('Database connected · local', style: style),
          const SizedBox(width: 18),
          Text(
              'GSTIN: ${app.company.gstin.isEmpty ? 'not set' : app.company.gstin}',
              style: style),
          const Spacer(),
          Text('FY ${_fy()}', style: style),
          const SizedBox(width: 18),
          Text(Fmt.dateTime(DateTime.now()), style: style),
        ],
      ),
    );
  }

  static String _fy() {
    final now = DateTime.now();
    final start = now.month >= 4 ? now.year : now.year - 1;
    return '$start-${(start + 1).toString().substring(2)}';
  }
}
