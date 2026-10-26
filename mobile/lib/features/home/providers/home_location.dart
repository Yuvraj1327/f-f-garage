import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences/app_preferences.dart';
import '../../../data/models/place.dart';
import '../../../data/providers/data_providers.dart';
import '../../../data/services/location_service.dart';

/// Where the Home screen is in its location story.
enum HomeLocationPhase {
  /// First visit: explain why location is useful and offer to allow it.
  ask,

  /// Reading the position and looking up the address.
  loading,

  /// A point is known (from the phone, or picked on the map).
  found,

  /// No location (said no, switched off, or not available). The customer can
  /// pick on the map or type a PIN code; nothing is asked again by itself.
  declined,
}

class HomeLocationState {
  const HomeLocationState(this.phase, {this.point, this.place, this.problem});

  final HomeLocationPhase phase;
  final MapPoint? point;

  /// The address found at [point]; null when the lookup was unavailable.
  final Place? place;

  /// Why the phone gave no position, when it did not.
  final LocationProblem? problem;
}

/// Drives the Home location card.
///
/// Permission is asked only after the customer taps "Allow location" on the
/// explanation card, once. After that the app reads the position again on later
/// visits only if it was granted before; a "Not now" or a refusal is never
/// followed by another prompt. The customer can always choose a place on the
/// map instead.
class HomeLocationController extends Notifier<HomeLocationState> {
  static const String doneKey = 'location_prompt_done';
  static const String grantedKey = 'location_granted';

  @override
  HomeLocationState build() {
    final store = ref.watch(preferencesStoreProvider);
    if (!(store.getBool(doneKey) ?? false)) {
      return const HomeLocationState(HomeLocationPhase.ask);
    }
    if (store.getBool(grantedKey) ?? false) {
      Future.microtask(_fetch);
      return const HomeLocationState(HomeLocationPhase.loading);
    }
    return const HomeLocationState(HomeLocationPhase.declined);
  }

  /// The customer agreed on the explanation card: ask the system once.
  Future<void> allow() async {
    await ref.read(preferencesStoreProvider).setBool(doneKey, true);
    await _fetch();
  }

  /// "Not now": remember it and never prompt by ourselves again.
  Future<void> skip() async {
    await ref.read(preferencesStoreProvider).setBool(doneKey, true);
    state = const HomeLocationState(HomeLocationPhase.declined);
  }

  /// The customer tapped "Use my current location".
  Future<void> useCurrent() => _fetch();

  /// A place chosen on the map.
  void picked(PickedLocation location) {
    state = HomeLocationState(
      HomeLocationPhase.found,
      point: location.point,
      place: location.place,
    );
  }

  Future<void> _fetch() async {
    state = const HomeLocationState(HomeLocationPhase.loading);
    final store = ref.read(preferencesStoreProvider);
    final result = await ref.read(locationServiceProvider).currentLocation();
    switch (result) {
      case LocationFailed(:final problem):
        if (problem == LocationProblem.denied ||
            problem == LocationProblem.deniedForever) {
          await store.setBool(grantedKey, false);
        }
        state = HomeLocationState(HomeLocationPhase.declined, problem: problem);
      case LocationFound(:final point):
        await store.setBool(grantedKey, true);
        Place? place;
        try {
          final places = await ref.read(mapsRepositoryProvider).reverse(point);
          place = places.isEmpty ? null : places.first;
        } catch (_) {
          // The address lookup is a bonus: the map and pin still work.
        }
        state = HomeLocationState(
          HomeLocationPhase.found,
          point: point,
          place: place,
        );
    }
  }
}

final homeLocationProvider =
    NotifierProvider<HomeLocationController, HomeLocationState>(
  HomeLocationController.new,
);
