import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the driver's own booking endpoints.
class DriverWorkApiService {
  DriverWorkApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list(Map<String, dynamic> query) async =>
      asJsonObject(
        await _client.get(ApiEndpoints.driverBookings, queryParameters: query),
      );

  Future<Map<String, dynamic>> get(String id) async =>
      asJsonObject(await _client.get(ApiEndpoints.driverBooking(id)));

  Future<Map<String, dynamic>> updateStatus(String id, String status) async =>
      asJsonObject(
        await _client.post(
          ApiEndpoints.driverBookingStatus(id),
          data: {'status': status},
        ),
      );
}
