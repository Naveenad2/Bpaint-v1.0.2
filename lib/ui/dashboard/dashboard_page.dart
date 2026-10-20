import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repos/party_repo.dart';
import '../../data/repos/product_repo.dart';
import '../../data/repos/purchase_repo.dart';
import '../../data/repos/report_repo.dart';
import '../../data/repos/sales_repo.dart';
import '../../state/app_state.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _sales = SalesRepo();
  final _parties = PartyRepo();
  final _products = ProductRepo();
  final _purchases = PurchaseRepo();
  final _reports = ReportRepo();

  bool _loading = true;
  Map<String, double> _today = const {};
  Map<String, double> _month = const {};
  Map<String, double> _profit = const {};
  Map<String, double> _purchaseMonth = const {};
  double _receivable = 0;
  double _payable = 0;
  double _stockCost = 0;
  double _expenses = 0;
  List<ChartPoint> _trend = const [];
  List<ChartPoint> _topItems = const [];
  List<SalesDoc> _recent = const [];
  List<Product> _lowStock = const [];
  DaySummary? _day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final trendFrom = now.subtract(const Duration(days: 13));

    final today = await _sales.summary(from: now, to: now);
    final month = await _sales.summary(from: monthStart, to: now);
    final profit = await _sales.profit(from: monthStart, to: now);
    final purchaseMonth = await _purchases.summary(from: monthStart, to: now);
    final receivable = await _parties.outstandingTotal('CUSTOMER');
    final payable = await _parties.outstandingTotal('SUPPLIER');
    final valuation = await _products.valuation();
    final stockCost = valuation.$1;
    final expenses = await _reports.expenseTotal(monthStart, now);
    final daily = await _sales.daily(from: trendFrom, to: now);
    final top = await _sales.topProducts(from: monthStart, to: now, limit: 6);
    final recent = await _sales.list(limit: 8);
    final low = await _products.lowStock(limit: 8);
    final day = await _reports.dayBook(now);

    if (!mounted) return;

    // Fill in the days with no sales so the bar chart keeps a steady rhythm.
    final byDay = {for (final d in daily) Fmt.iso(d.day): d.total};
    final trend = <ChartPoint>[];
    for (var i = 0; i < 14; i++) {
      final d = trendFrom.add(Duration(days: i));
      trend.add(ChartPoint('${d.day}/${d.month}', byDay[Fmt.iso(d)] ?? 0));
    }

    setState(() {
      _today = today;
      _month = month;
      _profit = profit;
      _purchaseMonth = purchaseMonth;
      _receivable = receivable;
      _payable = payable;
      _stockCost = stockCost;
      _expenses = expenses;
      _trend = trend;
      _topItems = top
          .map((r) =>
              ChartPoint((r['name'] ?? '') as String, Fmt.toDouble(r['value'])))
          .toList();
      _recent = recent;
      _lowStock = low;
      _day = day;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Good ${_greeting()}, ${app.user?.name.split(' ').first ?? ''}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Here is how ${app.company.name.isEmpty ? 'your shop' : app.company.name} '
            'is doing on ${Fmt.date(DateTime.now())}.',
            style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          _tiles(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: _trendCard()),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: _dayCard()),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: _topItemsCard()),
              const SizedBox(width: 14),
              Expanded(flex: 6, child: _recentCard()),
            ],
          ),
          const SizedBox(height: 14),
          _lowStockCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    return 'evening';
  }

  Widget _tiles() {
    final tiles = <Widget>[
      StatTile(
        label: "Today's sales",
        value: Fmt.money(_today['total'] ?? 0),
        sub: '${Fmt.compact(_today['bills'] ?? 0)} bills',
        icon: Icons.today_rounded,
      ),
      StatTile(
        label: 'This month',
        value: Fmt.money(_month['total'] ?? 0),
        sub: '${Fmt.compact(_month['bills'] ?? 0)} bills',
        icon: Icons.calendar_month_rounded,
        tint: AppTheme.info,
      ),
      StatTile(
        label: 'Gross profit (month)',
        value: Fmt.money(_profit['profit'] ?? 0),
        sub: '${Fmt.qty(_profit['margin'] ?? 0)}% margin',
        icon: Icons.trending_up_rounded,
        tint: AppTheme.success,
      ),
      StatTile(
        label: 'To collect',
        value: Fmt.money(_receivable),
        sub: 'from customers',
        icon: Icons.call_received_rounded,
        tint: AppTheme.danger,
      ),
      StatTile(
        label: 'To pay',
        value: Fmt.money(_payable),
        sub: 'to suppliers',
        icon: Icons.call_made_rounded,
        tint: AppTheme.warning,
      ),
      StatTile(
        label: 'Stock value',
        value: Fmt.money(_stockCost),
        sub: 'at cost',
        icon: Icons.inventory_2_rounded,
        tint: AppTheme.info,
      ),
      StatTile(
        label: 'Purchases (month)',
        value: Fmt.money(_purchaseMonth['total'] ?? 0),
        sub: '${Fmt.compact(_purchaseMonth['bills'] ?? 0)} bills',
        icon: Icons.local_shipping_rounded,
      ),
      StatTile(
        label: 'Expenses (month)',
        value: Fmt.money(_expenses),
        sub: 'shop running cost',
        icon: Icons.receipt_rounded,
        tint: AppTheme.danger,
      ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth > 1280
            ? 4
            : box.maxWidth > 900
                ? 3
                : 2;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 3.3,
          children: tiles,
        );
      },
    );
  }

  Widget _trendCard() => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Sales — last 14 days',
                icon: Icons.show_chart_rounded),
            BarChart(points: _trend, height: 190),
          ],
        ),
      );

  Widget _dayCard() {
    final d = _day;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Today at the counter',
              icon: Icons.point_of_sale_rounded),
          if (d == null)
            const Text('No data')
          else ...[
            _kv('Bills issued', '${d.bills}'),
            _kv('Gross sales', Fmt.money(d.salesTotal)),
            _kv('Returns', Fmt.money(d.returns)),
            _kv('Collected', Fmt.money(d.collected)),
            _kv('Credit given', Fmt.money(d.creditGiven)),
            _kv('Expenses', Fmt.money(d.expenses)),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cash in hand',
                    style:
                        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Money(d.cashInHand, size: 16, bold: true),
              ],
            ),
            if (d.collectionByMode.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in d.collectionByMode.entries)
                    StatusPill('${e.key} ${Fmt.compact(e.value)}',
                        color: AppTheme.info),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Text(v,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _topItemsCard() => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Best sellers this month',
                icon: Icons.local_fire_department_rounded),
            RankedBars(points: _topItems),
          ],
        ),
      );

  Widget _recentCard() => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle('Recent bills', icon: Icons.history_rounded),
            if (_recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: Text('No bills yet — press F2 to start billing.',
                        style: TextStyle(fontSize: 12.5))),
              )
            else
              for (final d in _recent)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 82,
                        child: Text(d.docNo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      Expanded(
                        child: Text(d.partyName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                      StatusPill(d.status),
                      const SizedBox(width: 10),
                      SizedBox(
                          width: 92,
                          child: Money(d.total, size: 12.5, bold: true)),
                    ],
                  ),
                ),
          ],
        ),
      );

  Widget _lowStockCard() => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(
              'Running low — reorder soon',
              icon: Icons.warning_amber_rounded,
              trailing: StatusPill('${_lowStock.length} items',
                  color: AppTheme.warning),
            ),
            if (_lowStock.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Every item is above its reorder level.',
                    style: TextStyle(fontSize: 12.5)),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final p in _lowStock)
                    Container(
                      width: 250,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppTheme.warning.withValues(alpha: 0.28)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(p.fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                                Text('Reorder level ${Fmt.qty(p.minStock)}',
                                    style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                          ),
                          Text('${Fmt.qty(p.stock)} ${p.unit}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.warning)),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
}
