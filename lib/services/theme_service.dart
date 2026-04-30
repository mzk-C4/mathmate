import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode { light, dark, system }

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._();
  static ThemeService get instance => _instance;
  ThemeService._();

  AppThemeMode _mode = AppThemeMode.light;

  AppThemeMode get mode => _mode;

  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String stored = prefs.getString('theme_mode') ?? 'light';
    _mode = AppThemeMode.values.firstWhere(
      (AppThemeMode e) => e.name == stored,
      orElse: () => AppThemeMode.light,
    );
    _initialized = true;
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
    notifyListeners();
  }
}
