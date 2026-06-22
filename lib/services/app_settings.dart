import 'package:shared_preferences/shared_preferences.dart';

/// Persists the one piece of app-level configuration that needs to survive
/// restarts: where the user's data directory lives on disk. Everything
/// else (people, events, groups) lives in that directory as plain files —
/// this is the only thing we need a "real" settings store for.
class AppSettings {
  static const _dataDirectoryKey = 'data_directory_path';

  final SharedPreferences _prefs;

  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings._(prefs);
  }

  /// The previously chosen data directory, or null if first launch.
  String? get dataDirectoryPath => _prefs.getString(_dataDirectoryKey);

  Future<void> setDataDirectoryPath(String path) async {
    await _prefs.setString(_dataDirectoryKey, path);
  }

  Future<void> clearDataDirectoryPath() async {
    await _prefs.remove(_dataDirectoryKey);
  }
}
