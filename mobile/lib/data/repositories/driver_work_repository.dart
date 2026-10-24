import '../../core/network/api_exception.dart';
import '../models/driver_job.dart';
import '../models/enums.dart';
import '../services/driver_work_api_service.dart';

/// The signed-in driver's own bookings. Throws [ApiException] only.
class DriverWorkRepository {
  DriverWorkRepository(this._service);

  final DriverWorkApiService _service;

  /// [scope] is "open" (assigned, on the way, in progress) or "history".
  Future<DriverJobPage> list({
    String scope = 'open',
    int limit = 25,
    int offset = 0,
  }) async =>
      _parse(
        await _service.list({'scope': scope, 'limit': limit, 'offset': offset}),
        DriverJobPage.fromJson,
      );

  Future<DriverJob> get(String id) async =>
      _parse(await _service.get(id), DriverJob.fromJson);

  /// Moves the booking to its next step. The server decides whether that step is
  /// allowed; a repeat of the current step is accepted and changes nothing.
  Future<DriverJob> updateStatus(String id, BookingStatus status) async =>
      _parse(await _service.updateStatus(id, status.apiValue), DriverJob.fromJson);

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
