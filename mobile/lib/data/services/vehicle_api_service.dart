import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the saved-vehicles endpoints.
class VehicleApiService {
  VehicleApiService(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> list() async =>
      asJsonObjectList(await _client.get(ApiEndpoints.vehicles));

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.vehicles, data: body));

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.vehicle(id), data: body));

  Future<void> delete(String id) async {
    await _client.delete(ApiEndpoints.vehicle(id));
  }
}
