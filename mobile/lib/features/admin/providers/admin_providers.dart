import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/availability.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/driver.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/service_area.dart';
import '../../../data/providers/data_providers.dart';
import '../../catalog/providers/catalog_providers.dart';

/// Every service, including inactive ones, for the admin lists.
final adminServicesProvider = FutureProvider.autoDispose
    .family<List<GarageService>, VehicleType?>(
  (ref, type) =>
      ref.watch(catalogRepositoryProvider).adminList(vehicleType: type),
);

final adminServiceProvider =
    FutureProvider.autoDispose.family<GarageService, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).adminGet(id),
);

final adminAreasProvider = FutureProvider.autoDispose<List<ServiceArea>>(
  (ref) => ref.watch(serviceAreaRepositoryProvider).adminList(),
);

final adminSlotsProvider = FutureProvider.autoDispose<List<TimeSlot>>(
  (ref) => ref.watch(availabilityRepositoryProvider).slots(),
);

/// How far ahead the closures list looks.
const int closuresLookAheadDays = 180;

/// Closures and special openings from today onwards.
final adminExceptionsProvider =
    FutureProvider.autoDispose<List<AvailabilityException>>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return ref.watch(availabilityRepositoryProvider).exceptions(
        today,
        today.add(const Duration(days: closuresLookAheadDays)),
      );
});

/// Refreshes every catalogue list/detail after a change.
void refreshCatalog(WidgetRef ref) {
  ref.invalidate(adminServicesProvider);
  ref.invalidate(adminServiceProvider);
  // What customers see changes with it.
  ref.invalidate(browseServicesProvider);
  ref.invalidate(browseServiceProvider);
}

/// Every driver account, with how many open bookings each has.
final adminDriversProvider = FutureProvider.autoDispose<List<DriverAccount>>(
  (ref) => ref.watch(adminDriverRepositoryProvider).list(),
);

final adminDriverProvider =
    FutureProvider.autoDispose.family<DriverAccount, String>(
  (ref, id) => ref.watch(adminDriverRepositoryProvider).get(id),
);

/// One driver's open bookings (what an admin may need to move elsewhere).
final adminDriverOpenBookingsProvider =
    FutureProvider.autoDispose.family<BookingPage, String>(
  (ref, id) => ref.watch(adminBookingRepositoryProvider).driverBookings(id),
);

final adminBookingProvider = FutureProvider.autoDispose.family<Booking, String>(
  (ref, id) => ref.watch(adminBookingRepositoryProvider).get(id),
);

final adminAssignmentHistoryProvider =
    FutureProvider.autoDispose.family<List<AssignmentHistoryItem>, String>(
  (ref, id) => ref.watch(adminBookingRepositoryProvider).history(id),
);

/// Bumped when a booking or assignment changed, so open lists reload.
final adminBookingsRefreshProvider = StateProvider<int>((ref) => 0);

/// Reloads everything that shows a booking's driver or status after a change.
void refreshAdminBooking(WidgetRef ref, String bookingId) {
  ref.read(adminBookingsRefreshProvider.notifier).state++;
  ref.invalidate(adminBookingProvider(bookingId));
  ref.invalidate(adminAssignmentHistoryProvider(bookingId));
  ref.invalidate(adminDriversProvider);
  ref.invalidate(adminDriverProvider);
  ref.invalidate(adminDriverOpenBookingsProvider);
}

/// Reloads the driver list and driver details after an account change.
void refreshAdminDrivers(WidgetRef ref) {
  ref.invalidate(adminDriversProvider);
  ref.invalidate(adminDriverProvider);
}

/// Booking and driver figures for the admin dashboard, counted by the server
/// (the list endpoint's `total`), so no booking data is downloaded for them.
class AdminStats {
  const AdminStats({
    required this.total,
    required this.completed,
    required this.pending,
    required this.cancelled,
    required this.activeDrivers,
  });

  final int total;
  final int completed;

  /// Waiting for payment or for a driver.
  final int pending;
  final int cancelled;
  final int activeDrivers;
}

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) async {
  ref.watch(adminBookingsRefreshProvider);
  final bookings = ref.watch(adminBookingRepositoryProvider);
  Future<int> count([List<BookingStatus>? statuses]) async =>
      (await bookings.list(statuses: statuses, limit: 1)).total;
  final total = await count();
  final completed = await count([BookingStatus.completed]);
  final pending =
      await count([BookingStatus.pendingPayment, BookingStatus.confirmed]);
  final cancelled = await count([BookingStatus.cancelled]);
  final drivers = await ref.watch(adminDriverRepositoryProvider).list();
  return AdminStats(
    total: total,
    completed: completed,
    pending: pending,
    cancelled: cancelled,
    activeDrivers: drivers.where((d) => d.isActive).length,
  );
});
