import 'json_reader.dart';

/// One in-app notification (a booking or payment update for the customer).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.bookingId,
    this.bookingCode,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: JsonReader.string(json, 'id'),
        bookingId: JsonReader.optionalString(json, 'booking_id'),
        bookingCode: JsonReader.optionalString(json, 'booking_code'),
        kind: JsonReader.string(json, 'kind'),
        title: JsonReader.string(json, 'title'),
        body: JsonReader.string(json, 'body'),
        createdAt: DateTime.parse(JsonReader.string(json, 'created_at')),
        isRead: JsonReader.boolean(json, 'is_read'),
      );

  final String id;
  final String? bookingId;
  final String? bookingCode;

  /// e.g. "driver_assigned"; the app only uses it to pick an icon.
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;

  AppNotification asRead() => AppNotification(
        id: id,
        bookingId: bookingId,
        bookingCode: bookingCode,
        kind: kind,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: true,
      );
}

class NotificationPage {
  const NotificationPage({
    required this.items,
    required this.total,
    required this.unread,
    required this.limit,
    required this.offset,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) =>
      NotificationPage(
        items: JsonReader.objectList(json, 'items', AppNotification.fromJson),
        total: JsonReader.integer(json, 'total'),
        unread: JsonReader.integer(json, 'unread'),
        limit: JsonReader.integer(json, 'limit'),
        offset: JsonReader.integer(json, 'offset'),
      );

  final List<AppNotification> items;
  final int total;
  final int unread;
  final int limit;
  final int offset;
}
