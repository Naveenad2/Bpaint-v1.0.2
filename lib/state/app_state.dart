import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../data/repos/backup_repo.dart';
import '../data/repos/product_repo.dart';
import '../data/repos/settings_repo.dart';
import '../data/repos/user_repo.dart';

/// Session, company profile, preferences and app-wide notifications.
class AppState extends ChangeNotifier {
  final SettingsRepo settings = SettingsRepo();
  final UserRepo users = UserRepo();
  final ProductRepo products = ProductRepo();
  final BackupRepo backups = BackupRepo();

  Company company = Company();
  AppUser? user;
  bool ready = false;
  int lowStockCount = 0;
  int overdueCount = 0;

  bool get signedIn => user != null;
  bool get canManage => user?.canManage ?? false;
  bool get isAdmin => user?.isAdmin ?? false;

  ThemeMode get themeMode => settings.get(SKeys.themeMode, 'light') == 'dark'
      ? ThemeMode.dark
      : ThemeMode.light;

  Color get accent =>
      AppTheme.accents[settings.get(SKeys.accentColor, 'Ocean Blue')] ??
      AppTheme.brand;

  String get printFormat =>
      settings.get(SKeys.printFormat, PrintFormat.a5Landscape);

  bool get autoPrint => settings.getBool(SKeys.autoPrint, true);
  bool get priceIncludesTax => settings.getBool(SKeys.priceIncludesTax);
  bool get roundOffEnabled => settings.getBool(SKeys.roundOff, true);
  bool get allowNegativeStock => settings.getBool(SKeys.negativeStock);
  double get defaultGst => settings.getDouble(SKeys.defaultGst, 18);

  /// [dataDir] overrides the platform application-support folder — used by
  /// tests, and by anyone who wants the data file on a shared drive.
  Future<void> init({String? dataDir}) async {
    await AppDb.instance.init(overrideDir: dataDir);
    await settings.load();
    company = await settings.company();
    ready = true;
    notifyListeners();
  }

  Future<String?> signIn(String username, String password) async {
    final u = await users.login(username, password);
    if (u == null) return 'Invalid username or password.';
    user = u;
    await users.logAction(user: u, action: 'LOGIN', entity: 'SESSION');
    await refreshAlerts();
    notifyListeners();
    return null;
  }

  Future<void> signOut() async {
    if (user != null) {
      await users.logAction(user: user, action: 'LOGOUT', entity: 'SESSION');
    }
    user = null;
    notifyListeners();
  }

  Future<void> refreshCompany() async {
    company = await settings.company();
    notifyListeners();
  }

  Future<void> saveCompany(Company c) async {
    await settings.saveCompany(c);
    company = c;
    notifyListeners();
  }

  Future<void> setSetting(String key, Object? value) async {
    await settings.set(key, value);
    notifyListeners();
  }

  Future<void> setSettings(Map<String, Object?> values) async {
    await settings.setAll(values);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    await setSetting(
        SKeys.themeMode, themeMode == ThemeMode.dark ? 'light' : 'dark');
  }

  Future<void> refreshAlerts() async {
    final low = await products.lowStock(limit: 500);
    lowStockCount = low.length;
    notifyListeners();
  }

  /// Default backup location: `<app data>/backups`, overridable in Settings.
  String get backupDir {
    final custom = settings.get(SKeys.backupDir);
    if (custom.isNotEmpty) return custom;
    return p.join(AppDb.instance.dataDir, 'backups');
  }

  /// Silent daily backup. Runs on sign-in; skips if today's copy exists.
  Future<void> autoBackup() async {
    try {
      final last = settings.get(SKeys.lastBackup);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (last.startsWith(today)) return;
      await backups.backupTo(backupDir);
      await backups.prune(backupDir, keep: 30);
      await settings.set(SKeys.lastBackup, DateTime.now().toIso8601String());
    } on FileSystemException {
      // A missing or read-only backup folder must never block billing.
    }
  }
}
