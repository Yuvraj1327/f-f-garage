import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the profile endpoints. Returns JSON; no model mapping here.
class ProfileApiService {
  ProfileApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> fetchMyProfile() async {
    return asJsonObject(await _client.get(ApiEndpoints.myProfile));
  }

  Future<Map<String, dynamic>> updateMyProfile(
    Map<String, dynamic> changes,
  ) async {
    return asJsonObject(
      await _client.patch(ApiEndpoints.myProfile, data: changes),
    );
  }
}
