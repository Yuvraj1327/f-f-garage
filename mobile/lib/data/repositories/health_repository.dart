import '../../core/network/api_exception.dart';
import '../models/health_status.dart';
import '../services/health_api_service.dart';

/// Maps health API responses to [HealthStatus]. Throws [ApiException] only.
class HealthRepository {
  HealthRepository(this._service);

  final HealthApiService _service;

  Future<HealthStatus> checkHealth() async {
    final json = await _service.fetchLiveness();
    try {
      return HealthStatus.fromJson(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
