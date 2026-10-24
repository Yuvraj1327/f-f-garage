import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/repositories/health_repository.dart';
import 'package:ff_garage/data/services/health_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeHealthApiService implements HealthApiService {
  _FakeHealthApiService(this._json);

  final Map<String, dynamic> _json;

  @override
  Future<Map<String, dynamic>> fetchLiveness() async => _json;
}

void main() {
  test('maps a valid response to HealthStatus', () async {
    final repository = HealthRepository(
      _FakeHealthApiService({
        'status': 'ok',
        'service': 'F&F Two Wheeler Garage API',
        'version': '0.1.0',
        'environment': 'development',
        'timestamp': '2026-10-17T11:04:08.361909Z',
      }),
    );

    final status = await repository.checkHealth();

    expect(status.isOk, isTrue);
    expect(status.version, '0.1.0');
    expect(status.timestamp.toUtc().year, 2026);
  });

  test('turns a malformed response into an invalidResponse ApiException',
      () async {
    final repository = HealthRepository(
      _FakeHealthApiService({'status': 'ok'}),
    );

    await expectLater(
      repository.checkHealth(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.type, 'type', ApiErrorType.invalidResponse),
      ),
    );
  });
}
