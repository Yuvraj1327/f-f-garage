import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../vehicles/providers/vehicle_providers.dart';

/// Active services (with active packages and charges) for customers.
/// The family key is the vehicle-type filter; null = all.
final browseServicesProvider = FutureProvider.autoDispose
    .family<List<GarageService>, VehicleType?>(
  (ref, type) =>
      ref.watch(catalogRepositoryProvider).browse(vehicleType: type),
);

/// The active categories in the admin's order (drives the repair rail).
final categoriesProvider = FutureProvider.autoDispose<List<ServiceCategory>>(
  (ref) => ref.watch(catalogRepositoryProvider).browseCategories(),
);

/// Every category, switched off ones too (admin screens).
final adminCategoriesProvider =
    FutureProvider.autoDispose<List<ServiceCategory>>(
  (ref) => ref.watch(catalogRepositoryProvider).adminCategories(),
);

final browseServiceProvider =
    FutureProvider.autoDispose.family<GarageService, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).browseOne(id),
);

/// The vehicle type chosen by hand on the service screen (when the customer
/// has no saved vehicle, or wants to look at the other kind). Null = follow
/// the selected vehicle.
final catalogTypeOverrideProvider = StateProvider<VehicleType?>((ref) => null);

/// Which kind of vehicle the service screen lists services for: the chosen
/// type, else the selected saved vehicle's type, else scooter.
final catalogVehicleTypeProvider = Provider.autoDispose<VehicleType>((ref) {
  final override = ref.watch(catalogTypeOverrideProvider);
  if (override != null) return override;
  return ref.watch(selectedVehicleProvider)?.type ?? VehicleType.scooter;
});
