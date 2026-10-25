import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls for address lookup. Returns JSON.
class MapsApiService {
  MapsApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> geocode(String text) async => asJsonObject(
        await _client.get(ApiEndpoints.mapsGeocode, queryParameters: {'q': text}),
      );

  Future<Map<String, dynamic>> reverse(double latitude, double longitude) async =>
      asJsonObject(
        await _client.get(
          ApiEndpoints.mapsReverse,
          queryParameters: {'latitude': latitude, 'longitude': longitude},
        ),
      );
}
