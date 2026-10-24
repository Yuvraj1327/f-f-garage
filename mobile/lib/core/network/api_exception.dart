import 'package:dio/dio.dart';

enum ApiErrorType {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  server,
  cancelled,
  invalidResponse,
  unknown,
}

/// The only error type the rest of the app sees from the network layer.
/// `message` is safe to show to the user.
class ApiException implements Exception {
  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.details,
  });

  final ApiErrorType type;
  final String message;
  final int? statusCode;

  /// Raw `detail` payload from the backend (e.g. FastAPI validation errors).
  final Object? details;

  factory ApiException.invalidResponse() => const ApiException(
        type: ApiErrorType.invalidResponse,
        message: 'The server sent an unexpected response. Please try again.',
      );

  factory ApiException.fromDioException(DioException error) {
    final type = error.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout) {
      return const ApiException(
        type: ApiErrorType.timeout,
        message: 'The server took too long to respond. Please try again.',
      );
    }
    if (type == DioExceptionType.connectionError) {
      return const ApiException(
        type: ApiErrorType.network,
        message: 'Unable to reach the server. Check your internet connection.',
      );
    }
    if (type == DioExceptionType.cancel) {
      return const ApiException(
        type: ApiErrorType.cancelled,
        message: 'The request was cancelled.',
      );
    }
    if (type == DioExceptionType.badResponse) {
      return ApiException._fromResponse(
        error.response?.statusCode,
        error.response?.data,
      );
    }
    return const ApiException(
      type: ApiErrorType.unknown,
      message: 'Something went wrong. Please try again.',
    );
  }

  factory ApiException._fromResponse(int? statusCode, Object? body) {
    // FastAPI errors look like {"detail": "text"} or {"detail": [ {...} ]}.
    Object? detail;
    if (body is Map<String, dynamic>) {
      detail = body['detail'];
    }
    final detailText = detail is String && detail.isNotEmpty ? detail : null;

    if (statusCode == 401) {
      return ApiException(
        type: ApiErrorType.unauthorized,
        message: detailText ?? 'Please sign in to continue.',
        statusCode: statusCode,
        details: detail,
      );
    }
    if (statusCode == 403) {
      return ApiException(
        type: ApiErrorType.forbidden,
        message: detailText ?? 'You do not have access to this.',
        statusCode: statusCode,
        details: detail,
      );
    }
    if (statusCode == 404) {
      return ApiException(
        type: ApiErrorType.notFound,
        message: detailText ?? 'We could not find what you were looking for.',
        statusCode: statusCode,
        details: detail,
      );
    }
    if (statusCode == 409) {
      return ApiException(
        type: ApiErrorType.conflict,
        message: detailText ?? 'This conflicts with existing information.',
        statusCode: statusCode,
        details: detail,
      );
    }
    if (statusCode == 400 || statusCode == 422) {
      return ApiException(
        type: ApiErrorType.validation,
        message: detailText ?? 'Please check the information you entered.',
        statusCode: statusCode,
        details: detail,
      );
    }
    if (statusCode != null && statusCode >= 500) {
      return ApiException(
        type: ApiErrorType.server,
        message: 'The server ran into a problem. Please try again shortly.',
        statusCode: statusCode,
        details: detail,
      );
    }
    return ApiException(
      type: ApiErrorType.unknown,
      message: detailText ?? 'Something went wrong. Please try again.',
      statusCode: statusCode,
      details: detail,
    );
  }

  @override
  String toString() => 'ApiException($type, status: $statusCode): $message';
}
