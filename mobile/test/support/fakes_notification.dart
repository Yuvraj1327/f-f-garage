import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/app_notification.dart';
import 'package:ff_garage/data/repositories/notification_repository.dart';

AppNotification notification({
  String id = 'n1',
  String kind = 'booking_confirmed',
  String title = 'Booking confirmed',
  String body = 'Payment received for FF-000001 (General Service).',
  String? bookingId = 'b1',
  String? bookingCode = 'FF-000001',
  bool read = false,
  DateTime? at,
}) =>
    AppNotification(
      id: id,
      kind: kind,
      title: title,
      body: body,
      bookingId: bookingId,
      bookingCode: bookingCode,
      createdAt: at ?? DateTime.utc(2026, 10, 21, 10),
      isRead: read,
    );

/// In-memory notifications, newest first as given. Set [error] to fail every
/// call, or [markError] to fail only marking as read.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({List<AppNotification>? items})
      : items = items ?? [];

  List<AppNotification> items;
  ApiException? error;
  ApiException? markError;
  int listCalls = 0;
  int unreadCalls = 0;
  final List<List<String>?> marked = [];

  void _check([ApiException? specific]) {
    if (error != null) throw error!;
    if (specific != null) throw specific;
  }

  int get _unread => items.where((n) => !n.isRead).length;

  @override
  Future<NotificationPage> list({
    bool unreadOnly = false,
    int limit = 20,
    int offset = 0,
  }) async {
    listCalls += 1;
    _check();
    final matching = items.where((n) => !unreadOnly || !n.isRead).toList();
    return NotificationPage(
      items: matching.skip(offset).take(limit).toList(),
      total: matching.length,
      unread: _unread,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> unreadCount() async {
    unreadCalls += 1;
    _check();
    return _unread;
  }

  @override
  Future<int> markRead([List<String>? ids]) async {
    marked.add(ids);
    _check(markError);
    items = [
      for (final n in items)
        ids == null || ids.contains(n.id) ? n.asRead() : n,
    ];
    return _unread;
  }
}
