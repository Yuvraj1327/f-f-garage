import '../../core/network/api_exception.dart';
import '../models/place.dart';
import '../services/maps_api_service.dart';

/// Shown when address lookup is down; the customer can always type instead.
const String lookupUnavailableMessage =
    'Address lookup is not available right now. You can still type your '
    'address.';

/// Address lookup through the backend (which holds the Google key).
/// Throws [ApiException] only: 503 when lookup is not set up or Google is down
/// (the screens then let the customer type the address), 429 when searching
/// too fast.
class MapsRepository {
  MapsRepository(this._service);

  final MapsApiService _service;

  /// Up to 5 Indian addresses matching [text], best first.
  Future<List<Place>> search(String text) async =>
      _places(await _guard(() => _service.geocode(text.trim())));

  /// The addresses at [point], most specific first (possibly none).
  Future<List<Place>> reverse(MapPoint point) async => _places(
        await _guard(
          () => _service.reverse(point.latitude, point.longitude),
        ),
      );

  /// The API client words every 5xx as "the server ran into a problem". For
  /// address lookup the useful news is that typing the address still works.
  Future<Map<String, dynamic>> _guard(
    Future<Map<String, dynamic>> Function() call,
  ) async {
    try {
      return await call();
    } on ApiException catch (error) {
      if (error.type != ApiErrorType.server) {
        rethrow;
      }
      throw ApiException(
        type: ApiErrorType.server,
        message: lookupUnavailableMessage,
        statusCode: error.statusCode,
      );
    }
  }

  List<Place> _places(Map<String, dynamic> json) {
    try {
      final rows = json['results'];
      if (rows is! List) {
        throw const FormatException('Expected "results" to be a list');
      }
      return [
        for (final row in rows)
          Place.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } on FormatException {
      throw ApiException.invalidResponse();
    } on TypeError {
      throw ApiException.invalidResponse();
    }
  }
}
