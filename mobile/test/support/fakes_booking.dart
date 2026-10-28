import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/driver.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/payment.dart';
import 'package:ff_garage/data/repositories/booking_repository.dart';

Booking booking({
  String id = 'b1',
  int number = 1,
  BookingStatus status = BookingStatus.pendingPayment,
  String service = 'General Service',
  String package = 'Basic',
  double price = 499,
  double extras = 0,
  DateTime? date,
  ClockTime start = const ClockTime(9, 0),
  ClockTime end = const ClockTime(11, 0),
  String address = '12 MG Road',
  String? landmark,
  double? latitude,
  double? longitude,
  String? notes,
  String pincode = '560001',
  bool canCancel = true,
  bool canModify = true,
  String? cancelBlockedReason,
  String? cancellationReason,
  List<BookingCharge> charges = const [],
  Payment? payment,
  bool isPaid = false,
  bool canPay = false,
  DriverSummary? driver,
  AdminAssignment? assignment,
  bool canAssign = false,
  bool canUnassign = false,
  List<TimelineEvent> timeline = const [],
  DateTime? confirmedAt,
  DateTime? completedAt,
  DateTime? cancelledAt,
}) =>
    Booking(
      id: id,
      number: number,
      code: 'FF-${number.toString().padLeft(6, '0')}',
      status: status,
      vehicleType: VehicleType.scooter,
      serviceId: 's1',
      packageId: 'p1',
      serviceName: service,
      packageName: package,
      inclusions: const ['Wash', 'Oil top-up'],
      durationMinutes: 90,
      customerName: 'Test User',
      customerPhone: '+919876543210',
      addressLine: address,
      landmark: landmark,
      latitude: latitude,
      longitude: longitude,
      city: 'Bengaluru',
      state: 'Karnataka',
      pincode: pincode,
      date: date ?? DateTime(2026, 10, 21),
      slotStart: start,
      slotEnd: end,
      packagePrice: price,
      extraChargesTotal: extras,
      totalAmount: price + extras,
      charges: charges,
      notes: notes,
      cancellationReason: cancellationReason,
      createdAt: DateTime(2026, 10, 19, 8),
      canCancel: canCancel,
      canModify: canModify,
      cancelBlockedReason: cancelBlockedReason,
      payment: payment,
      isPaid: isPaid,
      canPay: canPay,
      driver: driver,
      assignment: assignment,
      canAssign: canAssign,
      canUnassign: canUnassign,
      timeline: timeline,
      confirmedAt: confirmedAt,
      completedAt: completedAt,
      cancelledAt: cancelledAt,
    );

BookingQuote quote({double price = 499}) => BookingQuote(
      serviceId: 's1',
      serviceName: 'General Service',
      vehicleType: VehicleType.scooter,
      packageId: 'p1',
      packageName: 'Basic',
      inclusions: const ['Wash', 'Oil top-up'],
      durationMinutes: 90,
      packagePrice: price,
      charges: const [
        QuoteCharge(
          id: 'c1',
          chargeType: ExtraChargeType.engineOil,
          name: 'Engine oil 10W-30',
          amount: 350,
          selectable: true,
        ),
        QuoteCharge(
          id: 'c2',
          chargeType: ExtraChargeType.sparePart,
          name: 'Air filter',
          selectable: false,
        ),
      ],
    );

/// In-memory bookings. Set [error] to fail every call, or one of the specific
/// errors to fail just that call.
class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({List<Booking>? bookings, BookingQuote? quoteResult})
      : bookings = bookings ?? [],
        quoteResult = quoteResult ?? quote();

  List<Booking> bookings;
  BookingQuote quoteResult;
  ApiException? error;
  ApiException? quoteError;
  ApiException? createError;
  ApiException? updateError;
  ApiException? cancelError;

  int quoteCalls = 0;
  final List<NewBooking> creates = [];
  final List<({List<BookingStatus>? statuses, int limit, int offset})> lists = [];
  Map<String, dynamic>? lastUpdate;
  String? lastCancelReason;
  final List<String> cancelled = [];

  void _check([ApiException? specific]) {
    if (error != null) throw error!;
    if (specific != null) throw specific;
  }

  @override
  Future<BookingQuote> quote(
    String packageId, {
    List<String> extraChargeIds = const [],
    String? couponCode,
  }) async {
    quoteCalls += 1;
    _check(quoteError);
    return quoteResult;
  }

  @override
  Future<Booking> create(NewBooking draft) async {
    creates.add(draft);
    _check(createError);
    final created = booking(
      id: 'new-${creates.length}',
      number: bookings.length + 1,
      price: quoteResult.packagePrice,
      extras: draft.expectedTotal - quoteResult.packagePrice,
      date: draft.date,
      address: draft.addressLine,
      landmark: draft.landmark,
      latitude: draft.latitude,
      longitude: draft.longitude,
      pincode: draft.pincode,
    );
    bookings = [created, ...bookings];
    return created;
  }

  @override
  Future<BookingPage> list({
    List<BookingStatus>? statuses,
    int limit = 20,
    int offset = 0,
  }) async {
    lists.add((statuses: statuses, limit: limit, offset: offset));
    _check();
    final matching = bookings
        .where((b) => statuses == null || statuses.contains(b.status))
        .toList();
    final page = matching.skip(offset).take(limit).toList();
    return BookingPage(
      items: page,
      total: matching.length,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<Booking> get(String id) async {
    _check();
    return bookings.firstWhere(
      (b) => b.id == id,
      orElse: () => throw const ApiException(
        type: ApiErrorType.notFound,
        message: 'Booking not found',
        statusCode: 404,
      ),
    );
  }

  @override
  Future<Booking> update(String id, Map<String, dynamic> changes) async {
    lastUpdate = changes;
    _check(updateError);
    final old = await get(id);
    final updated = booking(
      id: old.id,
      number: old.number,
      status: old.status,
      address: (changes['address_line'] as String?) ?? old.addressLine,
      landmark: changes.containsKey('landmark')
          ? changes['landmark'] as String?
          : old.landmark,
      notes: changes.containsKey('customer_notes')
          ? changes['customer_notes'] as String?
          : old.notes,
      latitude: changes.containsKey('latitude')
          ? changes['latitude'] as double?
          : old.latitude,
      longitude: changes.containsKey('longitude')
          ? changes['longitude'] as double?
          : old.longitude,
      pincode: (changes['pincode'] as String?) ?? old.pincode,
    );
    bookings = [for (final b in bookings) b.id == id ? updated : b];
    return updated;
  }

  @override
  Future<Booking> cancel(String id, {String? reason}) async {
    lastCancelReason = reason;
    _check(cancelError);
    final old = await get(id);
    cancelled.add(id);
    final done = booking(
      id: old.id,
      number: old.number,
      status: BookingStatus.cancelled,
      canCancel: false,
      canModify: false,
      cancellationReason: reason,
    );
    bookings = [for (final b in bookings) b.id == id ? done : b];
    return done;
  }
}
