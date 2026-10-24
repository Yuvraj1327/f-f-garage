import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the admin booking and assignment endpoints.
class AdminBookingApiService {
  AdminBookingApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list(Map<String, dynamic> query) async =>
      asJsonObject(
        await _client.get(ApiEndpoints.adminBookings, queryParameters: query),
      );

  Future<Map<String, dynamic>> get(String id) async =>
      asJsonObject(await _client.get(ApiEndpoints.adminBooking(id)));

  Future<Map<String, dynamic>> assign(String id, String driverId) async =>
      asJsonObject(
        await _client.put(
          ApiEndpoints.adminBookingDriver(id),
          data: {'driver_id': driverId},
        ),
      );

  Future<Map<String, dynamic>> unassign(String id) async => asJsonObject(
        await _client.delete(ApiEndpoints.adminBookingDriver(id)),
      );

  Future<List<Map<String, dynamic>>> history(String id) async =>
      asJsonObjectList(
        await _client.get(ApiEndpoints.adminBookingAssignments(id)),
      );

  Future<Map<String, dynamic>> driverBookings(
    String driverId,
    Map<String, dynamic> query,
  ) async =>
      asJsonObject(
        await _client.get(
          ApiEndpoints.adminDriverBookings(driverId),
          queryParameters: query,
        ),
      );
}
