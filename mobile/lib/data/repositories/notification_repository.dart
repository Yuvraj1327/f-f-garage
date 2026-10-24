import '../../core/network/api_exception.dart';
import '../models/app_notification.dart';
import '../models/json_reader.dart';
import '../services/notification_api_service.dart';

/// The signed-in customer's notifications. Throws [ApiException] only.
class NotificationRepository {
  NotificationRepository(this._service);

  final NotificationApiService _service;

  Future<NotificationPage> list({
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _service.list({
      if (unreadOnly) 'unread_only': true,
      'limit': limit,
      'offset': offset,
    });
    return _parse(() => NotificationPage.fromJson(json));
  }

  Future<int> unreadCount() async {
    final json = await _service.unreadCount();
    return _parse(() => JsonReader.integer(json, 'unread'));
  }

  /// Marks the given notifications read, or all of them when [ids] is null.
  /// Returns how many are still unread.
  Future<int> markRead([List<String>? ids]) async {
    final json = await _service.markRead(ids);
    return _parse(() => JsonReader.integer(json, 'unread'));
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
