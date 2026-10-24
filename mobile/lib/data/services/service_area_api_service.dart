import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls for serviceable PIN codes. Returns JSON.
class ServiceAreaApiService {
  ServiceAreaApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> check(String pincode) async => asJsonObject(
        await _client.get(
          ApiEndpoints.pincodeCheck,
          queryParameters: {'pincode': pincode},
        ),
      );

  Future<List<Map<String, dynamic>>> adminList() async =>
      asJsonObjectList(await _client.get(ApiEndpoints.adminAreas));

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.adminAreas, data: body));

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.adminArea(id), data: body));

  Future<void> delete(String id) async {
    await _client.delete(ApiEndpoints.adminArea(id));
  }
}
