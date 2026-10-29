import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../models/dashboard.dart';

/// Admin dashboard figures. Throws [ApiException] only.
class DashboardRepository {
  DashboardRepository(this._client);

  final ApiClient _client;

  Future<AdminDashboard> load() async {
    final json = asJsonObject(await _client.get(ApiEndpoints.adminDashboard));
    try {
      return AdminDashboard.fromJson(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
