import '../../core/network/api_exception.dart';
import '../models/booking.dart';
import '../models/enums.dart';
import '../models/json_reader.dart';
import '../services/booking_api_service.dart';

/// Bookings for the signed-in customer. Throws [ApiException] only.
class BookingRepository {
  BookingRepository(this._service);

  final BookingApiService _service;

  Future<BookingQuote> quote(String packageId) async {
    final json = await _service.quote({
      'package_id': packageId,
      'extra_charge_ids': <String>[],
    });
    return _parse(json, BookingQuote.fromJson);
  }

  Future<Booking> create(NewBooking draft) async {
    final landmark = draft.landmark?.trim();
    final notes = draft.notes?.trim();
    final json = await _service.create({
      'package_id': draft.packageId,
      'extra_charge_ids': draft.extraChargeIds,
      'pincode': draft.pincode,
      'address_line': draft.addressLine,
      if (landmark != null && landmark.isNotEmpty) 'landmark': landmark,
      if (draft.latitude != null && draft.longitude != null) ...{
        'latitude': draft.latitude,
        'longitude': draft.longitude,
      },
      'scheduled_date': formatApiDate(draft.date),
      'time_slot_id': draft.timeSlotId,
      if (notes != null && notes.isNotEmpty) 'customer_notes': notes,
      'expected_total': draft.expectedTotal.toStringAsFixed(2),
      'client_request_id': draft.clientRequestId,
    });
    return _parse(json, Booking.fromJson);
  }

  Future<BookingPage> list({
    List<BookingStatus>? statuses,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _service.list({
      if (statuses != null && statuses.isNotEmpty)
        'status': [for (final s in statuses) s.apiValue],
      'limit': limit,
      'offset': offset,
    });
    return _parse(json, BookingPage.fromJson);
  }

  Future<Booking> get(String id) async =>
      _parse(await _service.get(id), Booking.fromJson);

  /// [changes] holds only what changed, using the API's field names.
  Future<Booking> update(String id, Map<String, dynamic> changes) async =>
      _parse(await _service.update(id, changes), Booking.fromJson);

  Future<Booking> cancel(String id, {String? reason}) async {
    final text = reason?.trim();
    final json = await _service.cancel(id, {
      if (text != null && text.isNotEmpty) 'reason': text,
    });
    return _parse(json, Booking.fromJson);
  }

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
