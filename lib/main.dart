import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/constants.dart';
import 'state/app_state.dart';
import 'state/billing_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      // 1280x760 fits a 1366x768 laptop, the usual counter machine.
      size: Size(1360, 820),
      minimumSize: Size(1100, 680),
      center: true,
      title: '${AppInfo.appName} ${AppInfo.version}',
      titleBarStyle: TitleBarStyle.normal,
      backgroundColor: Color(0xFFF6F7F9),
    );
    unawaitedShow(options);
  }

  final app = AppState();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<BillingState>(
          create: (_) => BillingState(app),
        ),
      ],
      child: const PaintProApp(),
    ),
  );

  // The splash screen shows while the database opens, so a slow disk on an
  // older Windows 10 machine never blocks the first frame.
  await app.init();
}

void unawaitedShow(WindowOptions options) {
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
