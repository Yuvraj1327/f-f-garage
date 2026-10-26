import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small settings kept on this device (theme, notification choices). Never
/// holds anything private: no tokens, no personal data.
abstract interface class PreferencesStore {
  String? getString(String key);
  bool? getBool(String key);
  Future<void> setString(String key, String value);
  Future<void> setBool(String key, bool value);
}

/// Keeps values for the life of the app only (the default, and in tests).
class MemoryPreferences implements PreferencesStore {
  MemoryPreferences([Map<String, Object>? initial])
      : _values = {...?initial};

  final Map<String, Object> _values;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  bool? getBool(String key) => _values[key] as bool?;

  @override
  Future<void> setString(String key, String value) async => _values[key] = value;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;
}

/// Saved with `shared_preferences`, so choices survive restarts and sign-in
/// and sign-out. A storage failure is swallowed: the choice then lasts only
/// until the app closes, which is harmless.
class SharedPrefsPreferences implements PreferencesStore {
  SharedPrefsPreferences(this._prefs);

  final SharedPreferences _prefs;

  /// Null when storage is unavailable (the caller falls back to memory).
  static Future<SharedPrefsPreferences?> open() async {
    try {
      return SharedPrefsPreferences(await SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  @override
  String? getString(String key) {
    try {
      return _prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  bool? getBool(String key) {
    try {
      return _prefs.getBool(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    try {
      await _prefs.setString(key, value);
    } catch (_) {}
  }

  @override
  Future<void> setBool(String key, bool value) async {
    try {
      await _prefs.setBool(key, value);
    } catch (_) {}
  }
}

/// `main.dart` overrides this with the saved preferences.
final preferencesStoreProvider =
    Provider<PreferencesStore>((ref) => MemoryPreferences());

/// Light is the default; Dark and System Default are the choices.
class ThemeController extends Notifier<ThemeMode> {
  static const String key = 'theme_mode';

  @override
  ThemeMode build() => parse(ref.watch(preferencesStoreProvider).getString(key));

  static ThemeMode parse(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await ref.read(preferencesStoreProvider).setString(key, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

/// What the customer chose about update notifications on this device.
class NotificationPrefs {
  const NotificationPrefs({this.showBadge = true, this.autoRefresh = true});

  /// Show the unread number on the bell.
  final bool showBadge;

  /// Check for booking updates by itself while a screen is open.
  final bool autoRefresh;

  NotificationPrefs copyWith({bool? showBadge, bool? autoRefresh}) =>
      NotificationPrefs(
        showBadge: showBadge ?? this.showBadge,
        autoRefresh: autoRefresh ?? this.autoRefresh,
      );
}

class NotificationPrefsController extends Notifier<NotificationPrefs> {
  static const String badgeKey = 'notif_badge';
  static const String refreshKey = 'notif_auto_refresh';

  @override
  NotificationPrefs build() {
    final store = ref.watch(preferencesStoreProvider);
    return NotificationPrefs(
      showBadge: store.getBool(badgeKey) ?? true,
      autoRefresh: store.getBool(refreshKey) ?? true,
    );
  }

  Future<void> setShowBadge(bool value) async {
    state = state.copyWith(showBadge: value);
    await ref.read(preferencesStoreProvider).setBool(badgeKey, value);
  }

  Future<void> setAutoRefresh(bool value) async {
    state = state.copyWith(autoRefresh: value);
    await ref.read(preferencesStoreProvider).setBool(refreshKey, value);
  }
}

final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsController, NotificationPrefs>(
  NotificationPrefsController.new,
);
