import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paint_billing/core/theme.dart';
import 'package:paint_billing/data/db.dart';
import 'package:paint_billing/state/app_state.dart';
import 'package:paint_billing/state/billing_state.dart';
import 'package:paint_billing/ui/auth/login_page.dart';
import 'package:paint_billing/ui/billing/speed_billing_page.dart';
import 'package:paint_billing/ui/dashboard/dashboard_page.dart';
import 'package:paint_billing/ui/inventory/inventory_page.dart';
import 'package:paint_billing/ui/invoices/invoices_page.dart';
import 'package:paint_billing/ui/parties/parties_page.dart';
import 'package:paint_billing/ui/payments/payments_page.dart';
import 'package:paint_billing/ui/products/products_page.dart';
import 'package:paint_billing/ui/purchases/purchases_page.dart';
import 'package:paint_billing/ui/reports/reports_page.dart';
import 'package:paint_billing/ui/settings/settings_page.dart';
import 'package:provider/provider.dart';

/// Assertions inside the Flutter framework (bad theme values, unbounded
/// constraints, dropdown values missing from their item list) only fire when a
/// widget is actually built. These tests build every screen so that class of
/// bug fails here rather than on a shop counter.
void main() {
  group('Theme', () {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test('builds light and dark on $platform', () {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        for (final accent in AppTheme.accents.values) {
          expect(AppTheme.light(accent), isNotNull);
          expect(AppTheme.dark(accent), isNotNull);
        }
      });
    }
  });

  group('Screens', () {
    late Directory tmp;
    late AppState app;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('paintpro_ui_');
      app = AppState();
      await app.init(dataDir: tmp.path);
      final err = await app.signIn('admin', 'admin123');
      expect(err, isNull, reason: 'seeded admin must be able to sign in');
    });

    tearDown(() async {
      await AppDb.instance.close();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    /// The shell reserves 214 px for the sidebar, so a page gets 886 px at the
    /// enforced minimum window of 1100 x 680. Screens are checked at that
    /// width as well as on a roomy display.
    const sizes = [Size(1440, 900), Size(886, 654)];

    Future<void> mountAt(WidgetTester tester, Widget page, Size size,
        {bool dark = false}) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            ChangeNotifierProvider<BillingState>(
              create: (_) => BillingState(app),
            ),
          ],
          child: MaterialApp(
            theme:
                dark ? AppTheme.dark(app.accent) : AppTheme.light(app.accent),
            home: Scaffold(body: page),
          ),
        ),
      );
      // Screens load their data in a post-frame callback.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull,
          reason:
              'rendering \${page.runtimeType} at \${size.width}x\${size.height}');
    }

    Future<void> mount(WidgetTester tester, Widget page,
        {bool dark = false}) async {
      for (final size in sizes) {
        await mountAt(tester, page, size, dark: dark);
      }
    }

    testWidgets('login', (t) => mount(t, const LoginPage()));
    testWidgets('dashboard', (t) => mount(t, const DashboardPage()));
    testWidgets('speed billing', (t) => mount(t, const SpeedBillingPage()));
    testWidgets('invoices', (t) => mount(t, const InvoicesPage()));
    testWidgets(
        'customers', (t) => mount(t, const PartiesPage(kind: 'CUSTOMER')));
    testWidgets(
        'suppliers', (t) => mount(t, const PartiesPage(kind: 'SUPPLIER')));
    testWidgets('products', (t) => mount(t, const ProductsPage()));
    testWidgets('purchases', (t) => mount(t, const PurchasesPage()));
    testWidgets('inventory', (t) => mount(t, const InventoryPage()));
    testWidgets('payments', (t) => mount(t, const PaymentsPage()));
    testWidgets('reports', (t) => mount(t, const ReportsPage()));
    testWidgets('settings', (t) => mount(t, const SettingsPage()));
    testWidgets('settings in dark mode',
        (t) => mount(t, const SettingsPage(), dark: true));
  });
}
