import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ff_garage/core/network/api_client.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._respond);

  final ResponseBody Function(RequestOptions options) _respond;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return _respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, {int status = 200}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ResponseBody _plainText(String body, {required int status}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: ['text/plain'],
    },
  );
}

ApiClient _client(
  _StubAdapter adapter, {
  String? token,
  String baseUrl = 'http://api.test/api/v1',
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    baseUrl: baseUrl,
    accessTokenReader: () async => token,
    dio: dio,
  );
}

/// Matches an [ApiException] of the given type (no further chaining).
Matcher _apiError(ApiErrorType type) =>
    isA<ApiException>().having((e) => e.type, 'type', type);

void main() {
  group('requests', () {
    test('joins base URL and path', () async {
      final adapter = _StubAdapter((_) => _json('{"status":"ok"}'));
      await _client(adapter).get('/health');
      expect(
        adapter.lastRequest!.uri.toString(),
        'http://api.test/api/v1/health',
      );
    });

    test('ignores a trailing slash on the base URL', () async {
      final adapter = _StubAdapter((_) => _json('{}'));
      await _client(adapter, baseUrl: 'http://api.test/api/v1/').get('/health');
      expect(
        adapter.lastRequest!.uri.toString(),
        'http://api.test/api/v1/health',
      );
    });

    test('returns decoded JSON', () async {
      final adapter = _StubAdapter((_) => _json('{"status":"ok","n":1}'));
      final result = await _client(adapter).get('/health');
      expect(result, {'status': 'ok', 'n': 1});
    });

    test('sends the bearer token when signed in', () async {
      final adapter = _StubAdapter((_) => _json('{}'));
      await _client(adapter, token: 'abc123').get('/health');
      expect(adapter.lastRequest!.headers['Authorization'], 'Bearer abc123');
    });

    test('sends no Authorization header when signed out', () async {
      final adapter = _StubAdapter((_) => _json('{}'));
      await _client(adapter).get('/health');
      expect(adapter.lastRequest!.headers.containsKey('Authorization'), isFalse);
    });

    test('sends no Authorization header for an empty token', () async {
      final adapter = _StubAdapter((_) => _json('{}'));
      await _client(adapter, token: '').get('/health');
      expect(adapter.lastRequest!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('error mapping', () {
    Future<void> expectStatus(
      int status,
      String body,
      ApiErrorType type,
    ) async {
      final adapter = _StubAdapter((_) => _json(body, status: status));
      await expectLater(
        _client(adapter).get('/x'),
        throwsA(_apiError(type)),
      );
    }

    test('401 -> unauthorized', () {
      return expectStatus(401, '{"detail":"Not authenticated"}',
          ApiErrorType.unauthorized);
    });

    test('403 -> forbidden', () {
      return expectStatus(403, '{"detail":"Forbidden"}', ApiErrorType.forbidden);
    });

    test('404 -> notFound with the backend message', () async {
      final adapter = _StubAdapter(
        (_) => _json('{"detail":"Booking not found"}', status: 404),
      );
      await expectLater(
        _client(adapter).get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.notFound)
              .having((e) => e.message, 'message', 'Booking not found')
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('409 -> conflict', () {
      return expectStatus(409, '{"detail":"Duplicate"}', ApiErrorType.conflict);
    });

    test('422 with a list detail -> validation with a friendly message',
        () async {
      final adapter = _StubAdapter(
        (_) => _json(
          '{"detail":[{"loc":["body","pincode"],"msg":"bad"}]}',
          status: 422,
        ),
      );
      await expectLater(
        _client(adapter).post('/x', data: {'pincode': 'abc'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.validation)
              .having(
                (e) => e.message,
                'message',
                'Please check the information you entered.',
              )
              .having((e) => e.details, 'details', isA<List<dynamic>>()),
        ),
      );
    });

    test('500 -> server, without leaking the response body', () async {
      final adapter = _StubAdapter(
        (_) => _json('{"detail":"stack trace with secrets"}', status: 500),
      );
      await expectLater(
        _client(adapter).get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.server)
              .having((e) => e.message, 'message', isNot(contains('secrets'))),
        ),
      );
    });

    test('non-JSON error body still maps to an ApiException', () async {
      final adapter = _StubAdapter(
        (_) => _plainText('Bad Gateway', status: 502),
      );
      await expectLater(
        _client(adapter).get('/x'),
        throwsA(_apiError(ApiErrorType.server)),
      );
    });

    ApiException fromType(DioExceptionType type) {
      return ApiException.fromDioException(
        DioException(requestOptions: RequestOptions(path: '/x'), type: type),
      );
    }

    test('timeouts -> timeout', () {
      expect(fromType(DioExceptionType.connectionTimeout).type,
          ApiErrorType.timeout);
      expect(fromType(DioExceptionType.sendTimeout).type, ApiErrorType.timeout);
      expect(
          fromType(DioExceptionType.receiveTimeout).type, ApiErrorType.timeout);
    });

    test('connection error -> network', () {
      expect(fromType(DioExceptionType.connectionError).type,
          ApiErrorType.network);
    });

    test('cancel -> cancelled, anything else -> unknown', () {
      expect(fromType(DioExceptionType.cancel).type, ApiErrorType.cancelled);
      expect(fromType(DioExceptionType.unknown).type, ApiErrorType.unknown);
    });
  });

  group('asJsonObject', () {
    test('accepts an object', () {
      expect(asJsonObject({'a': 1}), {'a': 1});
    });

    test('rejects a list, null and strings', () {
      expect(() => asJsonObject([1]), throwsA(_apiError(ApiErrorType.invalidResponse)));
      expect(() => asJsonObject(null), throwsA(_apiError(ApiErrorType.invalidResponse)));
      expect(() => asJsonObject('x'), throwsA(_apiError(ApiErrorType.invalidResponse)));
    });
  });
}
