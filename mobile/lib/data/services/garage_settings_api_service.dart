import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the administrator's garage-details endpoints.
class GarageSettingsApiService {
  GarageSettingsApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> get() async =>
      asJsonObject(await _client.get(ApiEndpoints.adminGarageSettings));

  Future<Map<String, dynamic>> save(Map<String, dynamic> body) async =>
      asJsonObject(
        await _client.put(ApiEndpoints.adminGarageSettings, data: body),
      );
}
