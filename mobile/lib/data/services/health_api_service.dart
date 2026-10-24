import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the health endpoints. Returns JSON; no model mapping here.
class HealthApiService {
  HealthApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> fetchLiveness() async {
    return asJsonObject(await _client.get(ApiEndpoints.health));
  }
}
