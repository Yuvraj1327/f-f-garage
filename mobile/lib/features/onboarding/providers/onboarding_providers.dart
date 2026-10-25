import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers, on this device, that the welcome screens were seen.
abstract interface class OnboardingStore {
  Future<void> markSeen();
}

class PrefsOnboardingStore implements OnboardingStore {
  const PrefsOnboardingStore(this._prefs);

  static const String key = 'onboarding_seen';

  final SharedPreferences _prefs;

  /// True when onboarding was already seen. Any storage problem counts as
  /// "seen": the welcome screens are a nicety and must never trap anyone.
  static Future<bool> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<OnboardingStore?> open() async {
    try {
      return PrefsOnboardingStore(await SharedPreferences.getInstance());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> markSeen() async {
    try {
      await _prefs.setBool(key, true);
    } catch (_) {
      // Not remembering is harmless: the screens show once more next launch.
    }
  }
}

/// Where "seen" is saved. Null (the default, and in tests) = not saved.
final onboardingStoreProvider = Provider<OnboardingStore?>((ref) => null);

/// Whether the first-run onboarding has been seen. Defaults to true so nothing
/// but `main.dart` (which passes the stored value) ever shows it.
final initialOnboardingSeenProvider = Provider<bool>((ref) => true);

class OnboardingController extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialOnboardingSeenProvider);

  Future<void> markSeen() async {
    state = true;
    await ref.read(onboardingStoreProvider)?.markSeen();
  }
}

final onboardingSeenProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);
