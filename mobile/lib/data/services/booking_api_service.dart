import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the booking endpoints. Returns JSON; no model mapping here.
class BookingApiService {
  BookingApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> quote(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.bookingQuote, data: body));

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.bookings, data: body));

  Future<Map<String, dynamic>> list(Map<String, dynamic> query) async =>
      asJsonObject(
        await _client.get(ApiEndpoints.bookings, queryParameters: query),
      );

  Future<Map<String, dynamic>> get(String id) async =>
      asJsonObject(await _client.get(ApiEndpoints.booking(id)));

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> changes,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.booking(id), data: changes));

  Future<Map<String, dynamic>> cancel(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.cancelBooking(id), data: body),
      );
}
