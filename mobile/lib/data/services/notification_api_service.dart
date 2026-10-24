import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the customer notification endpoints.
class NotificationApiService {
  NotificationApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> list(Map<String, dynamic> query) async =>
      asJsonObject(
        await _client.get(ApiEndpoints.notifications, queryParameters: query),
      );

  Future<Map<String, dynamic>> unreadCount() async => asJsonObject(
        await _client.get(ApiEndpoints.notificationsUnreadCount),
      );

  Future<Map<String, dynamic>> markRead(List<String>? ids) async =>
      asJsonObject(
        await _client.post(
          ApiEndpoints.notificationsRead,
          data: {if (ids != null) 'ids': ids},
        ),
      );
}
