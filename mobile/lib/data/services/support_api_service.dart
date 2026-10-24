import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw call to the support endpoint.
class SupportApiService {
  SupportApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> contact() async =>
      asJsonObject(await _client.get(ApiEndpoints.supportContact));
}
