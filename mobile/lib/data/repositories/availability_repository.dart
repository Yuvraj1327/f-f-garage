import '../../core/network/api_exception.dart';
import '../models/availability.dart';
import '../models/json_reader.dart';
import '../services/availability_api_service.dart';

/// Time slots, closures and availability. Throws [ApiException] only.
class AvailabilityRepository {
  AvailabilityRepository(this._service);

  final AvailabilityApiService _service;

  // ---- customers ----
  Future<List<DayAvailability>> availability(
    DateTime start, [
    DateTime? end,
  ]) async {
    final rows = await _service.availability(
      startDate: formatApiDate(start),
      endDate: end == null ? null : formatApiDate(end),
    );
    return _parseAll(rows, DayAvailability.fromJson);
  }

  // ---- admins ----
  Future<List<TimeSlot>> slots() async =>
      _parseAll(await _service.slots(), TimeSlot.fromJson);

  Future<TimeSlot> createSlot({
    required ClockTime start,
    required ClockTime end,
    required int capacity,
    required List<int> daysOfWeek,
    bool isActive = true,
  }) async {
    final json = await _service.createSlot({
      'start_time': start.toApi(),
      'end_time': end.toApi(),
      'capacity': capacity,
      'days_of_week': daysOfWeek,
      'is_active': isActive,
    });
    return _parse(json, TimeSlot.fromJson);
  }

  Future<TimeSlot> updateSlot(String id, Map<String, dynamic> changes) async =>
      _parse(await _service.updateSlot(id, changes), TimeSlot.fromJson);

  Future<void> deleteSlot(String id) => _service.deleteSlot(id);

  Future<List<AvailabilityException>> exceptions(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _service.exceptions(
      startDate: formatApiDate(start),
      endDate: formatApiDate(end),
    );
    return _parseAll(rows, AvailabilityException.fromJson);
  }

  Future<AvailabilityException> createException({
    required DateTime date,
    String? timeSlotId,
    bool isOpen = false,
    int? capacity,
    String? reason,
  }) async {
    final json = await _service.createException({
      'exception_date': formatApiDate(date),
      'time_slot_id': timeSlotId,
      'is_open': isOpen,
      'capacity': capacity,
      'reason': reason,
    });
    return _parse(json, AvailabilityException.fromJson);
  }

  Future<AvailabilityException> updateException(
    String id,
    Map<String, dynamic> changes,
  ) async =>
      _parse(
        await _service.updateException(id, changes),
        AvailabilityException.fromJson,
      );

  Future<void> deleteException(String id) => _service.deleteException(id);

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }

  List<T> _parseAll<T>(
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>) parse,
  ) =>
      rows.map((row) => _parse(row, parse)).toList(growable: false);
}
