import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/uuid.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/place.dart';
import '../../../data/providers/data_providers.dart';

/// Where the visit will happen. [city] and [areaName] come from the server's
/// PIN-code check, so the customer cannot book an address it does not service.
class BookingAddress {
  const BookingAddress({
    required this.pincode,
    required this.addressLine,
    required this.areaName,
    required this.city,
    this.landmark,
    this.latitude,
    this.longitude,
  });

  final String pincode;
  final String addressLine;
  final String? landmark;
  final String areaName;
  final String city;

  /// The map pin, when the customer chose one (both or neither).
  final double? latitude;
  final double? longitude;

  MapPoint? get point => latitude != null && longitude != null
      ? MapPoint(latitude!, longitude!)
      : null;
}

/// An address the customer used for an earlier booking, offered again on the
/// address step. (Derived from their booking history: there is no separate
/// address book.)
class PreviousAddress {
  const PreviousAddress({
    required this.pincode,
    required this.addressLine,
    this.landmark,
    this.latitude,
    this.longitude,
  });

  final String pincode;
  final String addressLine;
  final String? landmark;
  final double? latitude;
  final double? longitude;

  MapPoint? get point => latitude != null && longitude != null
      ? MapPoint(latitude!, longitude!)
      : null;
}

/// The chosen visit time.
class BookingSchedule {
  const BookingSchedule({
    required this.date,
    required this.slotId,
    required this.start,
    required this.end,
  });

  final DateTime date;
  final String slotId;
  final ClockTime start;
  final ClockTime end;

  String get timeLabel => '${start.format()} - ${end.format()}';
}

/// The booking being put together. Lives only while the customer is going
/// through the screens; nothing is sent to the server until they confirm.
class BookingFlowState {
  const BookingFlowState({
    required this.requestId,
    this.service,
    this.package,
    this.address,
    this.schedule,
    this.extraChargeIds = const {},
    this.notes = '',
  });

  /// Identifies this attempt. If "Confirm" is retried after a lost response the
  /// server returns the booking it already made instead of making a second one.
  final String requestId;
  final GarageService? service;
  final ServicePackage? package;
  final BookingAddress? address;
  final BookingSchedule? schedule;
  final Set<String> extraChargeIds;
  final String notes;

  bool get hasPackage => service != null && package != null;

  bool get isComplete => hasPackage && address != null && schedule != null;

  BookingFlowState copyWith({
    BookingAddress? address,
    BookingSchedule? schedule,
    Set<String>? extraChargeIds,
    String? notes,
  }) =>
      BookingFlowState(
        requestId: requestId,
        service: service,
        package: package,
        address: address ?? this.address,
        schedule: schedule ?? this.schedule,
        extraChargeIds: extraChargeIds ?? this.extraChargeIds,
        notes: notes ?? this.notes,
      );
}

class BookingFlowController extends Notifier<BookingFlowState> {
  @override
  BookingFlowState build() => BookingFlowState(requestId: newUuidV4());

  /// Starts a new booking for [package]; anything chosen before is dropped.
  void start(GarageService service, ServicePackage package) {
    state = BookingFlowState(
      requestId: newUuidV4(),
      service: service,
      package: package,
    );
  }

  void setAddress(BookingAddress address) =>
      state = state.copyWith(address: address);

  void setSchedule(BookingSchedule schedule) =>
      state = state.copyWith(schedule: schedule);

  void setNotes(String notes) => state = state.copyWith(notes: notes);

  void setExtraCharge(String id, bool selected) {
    final next = {...state.extraChargeIds};
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = state.copyWith(extraChargeIds: next);
  }

  void reset() => state = BookingFlowState(requestId: newUuidV4());
}

final bookingFlowProvider =
    NotifierProvider<BookingFlowController, BookingFlowState>(
  BookingFlowController.new,
);

/// The server's price summary for a package (no add-ons chosen).
final bookingQuoteProvider =
    FutureProvider.autoDispose.family<BookingQuote, String>(
  (ref, packageId) => ref.watch(bookingRepositoryProvider).quote(packageId),
);

/// Days a customer can pick from: today and the following 30 days (the API
/// answers at most 31 days at a time).
const int bookableDaysAhead = 30;

final bookableDaysProvider = FutureProvider.autoDispose<List<DayAvailability>>(
  (ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ref.watch(availabilityRepositoryProvider).availability(
          today,
          today.add(const Duration(days: bookableDaysAhead)),
        );
  },
);

/// Up to four different addresses from the customer's recent bookings, newest
/// first. A failure just means none are offered; booking never depends on it.
final previousAddressesProvider =
    FutureProvider.autoDispose<List<PreviousAddress>>((ref) async {
  final page = await ref.watch(bookingRepositoryProvider).list(limit: 30);
  final seen = <String>{};
  final found = <PreviousAddress>[];
  for (final booking in page.items) {
    final key = '${booking.pincode}|${booking.addressLine.trim().toLowerCase()}';
    if (!seen.add(key)) {
      continue;
    }
    found.add(
      PreviousAddress(
        pincode: booking.pincode,
        addressLine: booking.addressLine,
        landmark: booking.landmark,
        latitude: booking.latitude,
        longitude: booking.longitude,
      ),
    );
    if (found.length == 4) {
      break;
    }
  }
  return found;
});

final bookingProvider = FutureProvider.autoDispose.family<Booking, String>(
  (ref, id) => ref.watch(bookingRepositoryProvider).get(id),
);

/// Bumped whenever a booking is created, changed or cancelled, so the history
/// list reloads.
final bookingsRefreshProvider = StateProvider<int>((ref) => 0);

void refreshBookings(WidgetRef ref, {String? bookingId}) {
  ref.read(bookingsRefreshProvider.notifier).state++;
  if (bookingId != null) {
    ref.invalidate(bookingProvider(bookingId));
  }
}

/// How the history list is filtered.
enum BookingFilter {
  all('All', null),
  active('Active', [
    BookingStatus.pendingPayment,
    BookingStatus.confirmed,
    BookingStatus.assigned,
    BookingStatus.onTheWay,
    BookingStatus.inProgress,
  ]),
  completed('Completed', [BookingStatus.completed]),
  cancelled('Cancelled', [BookingStatus.cancelled]);

  const BookingFilter(this.label, this.statuses);

  final String label;
  final List<BookingStatus>? statuses;
}
