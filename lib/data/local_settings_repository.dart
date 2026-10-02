import 'package:shared_preferences/shared_preferences.dart';

import '../domain/repositories.dart';
import 'local_database.dart';

/// Device-wide settings in SQLite. Existing SharedPreferences values are
/// copied once, then SQLite is the only source of truth.
class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository({LocalDatabase? database})
    : _database = database ?? LocalDatabase.instance;

  final LocalDatabase _database;
  Future<void>? _migration;
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();

  Future<void> _ensureMigrated() => _migration ??= _migrate();

  Future<void> _migrate() async {
    final db = await _database.database;
    final row = (await db.query('app_settings', where: 'id = 1')).single;
    if (row['prefs_migrated'] == 1) return;
    final language = await _preferences.getString('language') ?? '한국어';
    final dark = await _preferences.getBool('dark') ?? false;
    final push = await _preferences.getBool('push') ?? true;
    await db.update('app_settings', {
      'language': language,
      'dark_mode': dark ? 1 : 0,
      'push_enabled': push ? 1 : 0,
      'prefs_migrated': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = 1 AND prefs_migrated = 0');
  }

  Future<Map<String, Object?>> _row() async {
    await _ensureMigrated();
    final db = await _database.database;
    return (await db.query('app_settings', where: 'id = 1')).single;
  }

  @override
  Future<String> language() async => (await _row())['language'] as String;
  @override
  Future<bool> dark() async => (await _row())['dark_mode'] == 1;
  @override
  Future<bool> push() async => (await _row())['push_enabled'] == 1;

  Future<void> _save(String column, Object value) async {
    await _ensureMigrated();
    final db = await _database.database;
    await db.update('app_settings', {
      column: value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'id = 1');
  }

  @override
  Future<void> saveLanguage(String value) => _save('language', value);
  @override
  Future<void> saveDark(bool value) => _save('dark_mode', value ? 1 : 0);
  @override
  Future<void> savePush(bool value) => _save('push_enabled', value ? 1 : 0);
}
