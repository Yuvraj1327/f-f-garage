import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ff_garage/core/network/api_client.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this._respond);

  final int Function(RequestOptions options) _respond;
  final List<String?> authHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authHeaders.add(options.headers['Authorization'] as String?);
    return ResponseBody.fromString(
      '{"detail":"x"}',
      _respond(options),
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late String? currentToken;
  late int expiredCalls;
  late int refreshCalls;

  setUp(() {
    currentToken = 'old';
    expiredCalls = 0;
    refreshCalls = 0;
  });

  ApiClient client(
    _Adapter adapter, {
    Future<String?> Function()? refresh,
  }) {
    return ApiClient(
      baseUrl: 'http://api.test/api/v1',
      accessTokenReader: () async => currentToken,
      refreshSession: refresh == null
          ? null
          : () async {
              refreshCalls += 1;
              final token = await refresh();
              currentToken = token;
              return token;
            },
      onSessionExpired: () => expiredCalls += 1,
      dio: Dio()..httpClientAdapter = adapter,
    );
  }

  test('on 401 it refreshes the token and retries once with the new one',
      () async {
    final adapter = _Adapter(
      (o) => o.headers['Authorization'] == 'Bearer new' ? 200 : 401,
    );
    final result = await client(adapter, refresh: () async => 'new')
        .get('/profiles/me');

    expect(result, isA<Map<String, dynamic>>());
    expect(adapter.authHeaders, ['Bearer old', 'Bearer new']);
    expect(refreshCalls, 1);
    expect(expiredCalls, 0);
  });

  test('if the retry is also 401 the session is declared expired', () async {
    final adapter = _Adapter((_) => 401);
    await expectLater(
      client(adapter, refresh: () async => 'new').get('/x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.type, 'type', ApiErrorType.unauthorized),
      ),
    );
    expect(adapter.authHeaders.length, 2, reason: 'exactly one retry');
    expect(refreshCalls, 1);
    expect(expiredCalls, 1);
  });

  test('if the refresh token is rejected the session is declared expired',
      () async {
    final adapter = _Adapter((_) => 401);
    await expectLater(
      client(adapter, refresh: () async => null).get('/x'),
      throwsA(isA<ApiException>()),
    );
    expect(adapter.authHeaders.length, 1);
    expect(expiredCalls, 1);
  });

  test('a refresh that fails transiently keeps the session', () async {
    final adapter = _Adapter((_) => 401);
    await expectLater(
      client(adapter, refresh: () async => throw Exception('offline')).get('/x'),
      throwsA(isA<ApiException>()),
    );
    expect(expiredCalls, 0);
  });

  test('a 401 without a token (signed out) does not trigger expiry', () async {
    currentToken = null;
    final adapter = _Adapter((_) => 401);
    await expectLater(
      client(adapter, refresh: () async => 'new').get('/x'),
      throwsA(isA<ApiException>()),
    );
    expect(refreshCalls, 0);
    expect(expiredCalls, 0);
  });

  test('403 and other errors do not touch the session', () async {
    final adapter = _Adapter((_) => 403);
    await expectLater(
      client(adapter, refresh: () async => 'new').get('/x'),
      throwsA(
        isA<ApiException>().having((e) => e.type, 'type', ApiErrorType.forbidden),
      ),
    );
    expect(refreshCalls, 0);
    expect(expiredCalls, 0);
  });
}
