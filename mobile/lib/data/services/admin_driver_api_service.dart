import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the admin driver-account endpoints.
class AdminDriverApiService {
  AdminDriverApiService(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> list() async =>
      asJsonObjectList(await _client.get(ApiEndpoints.adminDrivers));

  Future<Map<String, dynamic>> get(String id) async =>
      asJsonObject(await _client.get(ApiEndpoints.adminDriver(id)));

  Future<Map<String, dynamic>> create(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.adminDrivers, data: body));

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> changes,
  ) async =>
      asJsonObject(
        await _client.patch(ApiEndpoints.adminDriver(id), data: changes),
      );

  Future<void> resetPassword(String id, String newPassword) async {
    await _client.post(
      ApiEndpoints.adminDriverPassword(id),
      data: {'new_password': newPassword},
    );
  }
}
