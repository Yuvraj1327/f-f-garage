import '../../core/network/api_exception.dart';
import '../models/booking.dart';
import '../models/driver.dart';
import '../models/enums.dart';
import '../services/admin_booking_api_service.dart';

/// Bookings and driver assignment for admins. Throws [ApiException] only.
class AdminBookingRepository {
  AdminBookingRepository(this._service);

  final AdminBookingApiService _service;

  Future<BookingPage> list({
    List<BookingStatus>? statuses,
    String? query,
    int limit = 25,
    int offset = 0,
  }) async {
    final text = query?.trim();
    final json = await _service.list({
      if (statuses != null && statuses.isNotEmpty)
        'status': [for (final s in statuses) s.apiValue],
      if (text != null && text.isNotEmpty) 'q': text,
      'limit': limit,
      'offset': offset,
    });
    return _parse(json, BookingPage.fromJson);
  }

  Future<Booking> get(String id) async =>
      _parse(await _service.get(id), Booking.fromJson);

  /// Assigns the driver, or changes the driver. Asking again for the current
  /// driver changes nothing.
  Future<Booking> assign(String bookingId, String driverId) async =>
      _parse(await _service.assign(bookingId, driverId), Booking.fromJson);

  /// Takes the driver off; only while the booking is "assigned".
  Future<Booking> unassign(String bookingId) async =>
      _parse(await _service.unassign(bookingId), Booking.fromJson);

  Future<List<AssignmentHistoryItem>> history(String bookingId) async {
    final rows = await _service.history(bookingId);
    try {
      return rows.map(AssignmentHistoryItem.fromJson).toList();
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }

  /// One driver's bookings. [scope] is "open" or "history".
  Future<BookingPage> driverBookings(
    String driverId, {
    String scope = 'open',
    int limit = 25,
    int offset = 0,
  }) async =>
      _parse(
        await _service.driverBookings(driverId, {
          'scope': scope,
          'limit': limit,
          'offset': offset,
        }),
        BookingPage.fromJson,
      );

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
