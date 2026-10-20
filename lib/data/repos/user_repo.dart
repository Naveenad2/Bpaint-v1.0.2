import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../db.dart';
import '../models.dart';

/// Users, login and the audit trail.
class UserRepo {
  Database get _db => AppDb.instance.db;

  static String hash(String salt, String password) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  static String newSalt() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<List<AppUser>> all({bool onlyActive = false}) async {
    final rows = await _db.query('users',
        where: onlyActive ? 'active = 1' : null, orderBy: 'name');
    return rows.map(AppUser.fromMap).toList();
  }

  Future<AppUser?> byId(int id) async {
    final rows = await _db.query('users', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : AppUser.fromMap(rows.first);
  }

  /// Returns the user when credentials match and the account is active.
  Future<AppUser?> login(String username, String password) async {
    final rows = await _db.query('users',
        where: 'LOWER(username) = ? AND active = 1',
        whereArgs: [username.trim().toLowerCase()],
        limit: 1);
    if (rows.isEmpty) return null;
    final u = AppUser.fromMap(rows.first);
    if (hash(u.salt, password) != u.passwordHash) return null;
    u.lastLogin = DateTime.now();
    await _db.update('users', {'last_login': u.lastLogin!.toIso8601String()},
        where: 'id = ?', whereArgs: [u.id]);
    return u;
  }

  Future<bool> usernameTaken(String username, {int? exceptId}) async {
    final rows = await _db.query('users',
        where: 'LOWER(username) = ?${exceptId != null ? ' AND id <> ?' : ''}',
        whereArgs: [
          username.trim().toLowerCase(),
          if (exceptId != null) exceptId,
        ]);
    return rows.isNotEmpty;
  }

  Future<int> create(AppUser u, String password) async {
    u.salt = newSalt();
    u.passwordHash = hash(u.salt, password);
    return _db.insert('users', u.toMap());
  }

  Future<void> update(AppUser u, {String? newPassword}) async {
    if (newPassword != null && newPassword.isNotEmpty) {
      u.salt = newSalt();
      u.passwordHash = hash(u.salt, newPassword);
    }
    await _db.update('users', u.toMap(), where: 'id = ?', whereArgs: [u.id]);
  }

  Future<bool> changePassword(int userId, String oldPw, String newPw) async {
    final u = await byId(userId);
    if (u == null) return false;
    if (hash(u.salt, oldPw) != u.passwordHash) return false;
    final salt = newSalt();
    await _db.update(
      'users',
      {'salt': salt, 'password_hash': hash(salt, newPw)},
      where: 'id = ?',
      whereArgs: [userId],
    );
    return true;
  }

  /// Never hard-delete a user — invoices reference the operator name.
  Future<void> deactivate(int id) async {
    await _db.update('users', {'active': 0}, where: 'id = ?', whereArgs: [id]);
  }

  /// True when only one active admin remains (guards self-lockout).
  Future<bool> isLastAdmin(int id) async {
    final n = firstInt(await _db.rawQuery(
      "SELECT COUNT(*) FROM users WHERE role = 'ADMIN' AND active = 1 AND id <> ?",
      [id],
    ));
    return n == 0;
  }

  // ------------------------------------------------------------------
  // Audit trail
  // ------------------------------------------------------------------
  Future<void> logAction({
    AppUser? user,
    required String action,
    String entity = '',
    int? entityId,
    String detail = '',
    DatabaseExecutor? txn,
  }) async {
    final exec = txn ?? _db;
    await exec.insert('audit_log', {
      'at': DateTime.now().toIso8601String(),
      'user_id': user?.id,
      'user_name': user?.name ?? 'system',
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'detail': detail,
    });
  }

  Future<List<Map<String, Object?>>> auditLog({int limit = 300}) =>
      _db.query('audit_log', orderBy: 'at DESC', limit: limit);
}
