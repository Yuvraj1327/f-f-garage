import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/preferences/app_preferences.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/providers/data_providers.dart';

/// The customer's saved vehicles, loaded from the backend.
final vehiclesProvider = FutureProvider.autoDispose<List<Vehicle>>(
  (ref) => ref.watch(vehicleRepositoryProvider).list(),
);

/// Which saved vehicle the customer last chose (kept on this phone).
class SelectedVehicleController extends Notifier<String?> {
  static const String key = 'selected_vehicle';

  @override
  String? build() => ref.watch(preferencesStoreProvider).getString(key);

  Future<void> select(String id) async {
    state = id;
    await ref.read(preferencesStoreProvider).setString(key, id);
  }
}

final selectedVehicleIdProvider =
    NotifierProvider<SelectedVehicleController, String?>(
  SelectedVehicleController.new,
);

/// The vehicle to use: the chosen one if it still exists, else the first saved
/// one, else null. Null while loading or if the list cannot be loaded.
final selectedVehicleProvider = Provider.autoDispose<Vehicle?>((ref) {
  final vehicles = ref.watch(vehiclesProvider).valueOrNull;
  if (vehicles == null || vehicles.isEmpty) return null;
  final id = ref.watch(selectedVehicleIdProvider);
  for (final vehicle in vehicles) {
    if (vehicle.id == id) return vehicle;
  }
  return vehicles.first;
});

/// The vehicle to put on a booking for a service of [type]: [selected] if it is
/// of that type, else the first saved vehicle of that type, else null.
Vehicle? pickVehicle(
  List<Vehicle> vehicles,
  Vehicle? selected,
  VehicleType type,
) {
  if (selected != null && selected.type == type) return selected;
  for (final vehicle in vehicles) {
    if (vehicle.type == type) return vehicle;
  }
  return null;
}
