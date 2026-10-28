import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Returns the current Supabase access token, or null when signed out.
typedef AccessTokenReader = Future<String?> Function();

/// Gets a fresh access token using the refresh token. Returns null when the
/// session cannot be refreshed (it is over); throws on a transient failure
/// such as no network (the session may still be fine).
typedef SessionRefresher = Future<String?> Function();

const String _sessionRetryKey = 'session_retry';

/// The single HTTP entry point to the FastAPI backend.
///
/// - Adds `Authorization: Bearer <token>` when a token is available.
/// - On a 401 for a signed-in request: refreshes the token and retries once.
///   If the session cannot be refreshed, or the retry is still 401, it calls
///   [onSessionExpired] (the app then signs the user out).
/// - Converts every failure into an [ApiException].
/// - Returns decoded JSON (`Map`, `List` or null); repositories map it to models.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required AccessTokenReader accessTokenReader,
    SessionRefresher? refreshSession,
    void Function()? onSessionExpired,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl.endsWith('/')
          ? baseUrl.substring(0, baseUrl.length - 1)
          : baseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 30)
      ..headers = <String, dynamic>{'Accept': 'application/json'};

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await accessTokenReader();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final options = error.requestOptions;
          final wasAuthenticated = options.headers.containsKey('Authorization');
          if (error.response?.statusCode != 401 || !wasAuthenticated) {
            handler.next(error);
            return;
          }

          // Already retried once, or nothing to refresh with: the session is over.
          if (options.extra[_sessionRetryKey] == true ||
              refreshSession == null) {
            onSessionExpired?.call();
            handler.next(error);
            return;
          }

          String? newToken;
          try {
            newToken = await refreshSession();
          } catch (_) {
            // Transient failure (e.g. offline): keep the session, report the 401.
            handler.next(error);
            return;
          }
          if (newToken == null || newToken.isEmpty) {
            onSessionExpired?.call();
            handler.next(error);
            return;
          }

          options.extra[_sessionRetryKey] = true;
          options.headers['Authorization'] = 'Bearer $newToken';
          try {
            handler.resolve(await _dio.fetch<dynamic>(options));
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
  }

  final Dio _dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _send('GET', path, queryParameters: queryParameters);

  Future<dynamic> post(String path, {Object? data}) =>
      _send('POST', path, data: data);

  /// Sends [bytes] as the whole request body (a picture upload).
  Future<dynamic> postBytes(
    String path,
    List<int> bytes, {
    required String contentType,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: Stream<List<int>>.fromIterable([bytes]),
        queryParameters: queryParameters,
        options: Options(
          method: 'POST',
          contentType: contentType,
          headers: {Headers.contentLengthHeader: bytes.length},
          // Pictures are up to 5 MB: give a slow mobile connection time.
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      return response.data;
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<dynamic> put(String path, {Object? data}) =>
      _send('PUT', path, data: data);

  Future<dynamic> patch(String path, {Object? data}) =>
      _send('PATCH', path, data: data);

  Future<dynamic> delete(String path, {Map<String, dynamic>? queryParameters}) =>
      _send('DELETE', path, queryParameters: queryParameters);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method),
      );
      return response.data;
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }
}

/// Narrows decoded JSON to an object, or throws [ApiException.invalidResponse].
Map<String, dynamic> asJsonObject(Object? json) {
  if (json is Map<String, dynamic>) {
    return json;
  }
  throw ApiException.invalidResponse();
}

/// Narrows decoded JSON to a list of objects, or throws
/// [ApiException.invalidResponse].
List<Map<String, dynamic>> asJsonObjectList(Object? json) {
  if (json is List && json.every((item) => item is Map<String, dynamic>)) {
    return json.cast<Map<String, dynamic>>();
  }
  throw ApiException.invalidResponse();
}
