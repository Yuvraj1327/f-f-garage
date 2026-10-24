import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';

/// Active services (with active packages and charges) for customers.
/// The family key is the vehicle-type filter; null = all.
final browseServicesProvider = FutureProvider.autoDispose
    .family<List<GarageService>, VehicleType?>(
  (ref, type) =>
      ref.watch(catalogRepositoryProvider).browse(vehicleType: type),
);

final browseServiceProvider =
    FutureProvider.autoDispose.family<GarageService, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).browseOne(id),
);
