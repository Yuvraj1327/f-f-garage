import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ff_garage/core/network/api_client.dart';

class RecordedRequest {
  RecordedRequest(this.method, this.path, this.query, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;
}

/// An [ApiClient] whose "server" is a function; every request is recorded.
class StubApi {
  StubApi(this.respond) {
    client = ApiClient(
      baseUrl: 'http://api.test/api/v1',
      accessTokenReader: () async => 'token',
      dio: Dio()..httpClientAdapter = _Adapter(this),
    );
  }

  /// Returns (status, json body) for a request.
  final (int, Object?) Function(RecordedRequest request) respond;
  late final ApiClient client;
  final List<RecordedRequest> requests = [];

  RecordedRequest get last => requests.last;
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this._api);

  final StubApi _api;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = RecordedRequest(
      options.method,
      options.path,
      options.queryParameters,
      options.data,
    );
    _api.requests.add(request);
    final (status, body) = _api.respond(request);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
