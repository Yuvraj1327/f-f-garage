/// Response of `GET /api/v1/health`.
class HealthStatus {
  const HealthStatus({
    required this.status,
    required this.service,
    required this.version,
    required this.environment,
    required this.timestamp,
  });

  /// Throws [FormatException] when a field is missing or has the wrong type.
  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      status: _string(json, 'status'),
      service: _string(json, 'service'),
      version: _string(json, 'version'),
      environment: _string(json, 'environment'),
      timestamp: DateTime.parse(_string(json, 'timestamp')),
    );
  }

  final String status;
  final String service;
  final String version;
  final String environment;
  final DateTime timestamp;

  bool get isOk => status == 'ok';

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String) {
      return value;
    }
    throw FormatException('Expected "$key" to be a string, got $value');
  }
}
