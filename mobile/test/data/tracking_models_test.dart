import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/app_notification.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/repositories/notification_repository.dart';
import 'package:ff_garage/data/services/notification_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_api.dart';

Map<String, dynamic> _note([Map<String, dynamic> override = const {}]) => {
      'id': 'n1',
      'booking_id': 'b1',
      'booking_code': 'FF-000012',
      'kind': 'driver_assigned',
      'title': 'Driver assigned',
      'body': 'Ravi is assigned to FF-000012 (General Service).',
      'created_at': '2026-10-21T10:00:00Z',
      'is_read': false,
      ...override,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> items, {int unread = 1}) => {
      'items': items,
      'total': items.length,
      'unread': unread,
      'limit': 20,
      'offset': 0,
    };

NotificationRepository _repo(StubApi api) =>
    NotificationRepository(NotificationApiService(api.client));

void main() {
  group('AppNotification', () {
    test('parses a notification', () {
      final n = AppNotification.fromJson(_note());
      expect(n.title, 'Driver assigned');
      expect(n.bookingCode, 'FF-000012');
      expect(n.isRead, isFalse);
      expect(n.createdAt.isUtc, isTrue);
    });

    test('a notification without a booking is allowed', () {
      final n = AppNotification.fromJson(
        _note({'booking_id': null, 'booking_code': null}),
      );
      expect(n.bookingId, isNull);
      expect(n.bookingCode, isNull);
    });

    test('rejects missing or malformed fields', () {
      expect(() => AppNotification.fromJson(_note({'title': null})),
          throwsFormatException);
      expect(() => AppNotification.fromJson(_note({'is_read': 'no'})),
          throwsFormatException);
      expect(() => AppNotification.fromJson(_note({'created_at': 'soon'})),
          throwsFormatException);
    });

    test('asRead keeps everything else', () {
      final n = AppNotification.fromJson(_note()).asRead();
      expect(n.isRead, isTrue);
      expect(n.id, 'n1');
      expect(n.body, contains('Ravi'));
    });

    test('parses a page with the unread count', () {
      final page = NotificationPage.fromJson(_page([_note()], unread: 4));
      expect(page.items, hasLength(1));
      expect(page.unread, 4);
      expect(page.total, 1);
    });
  });

  group('Booking timeline fields', () {
    Map<String, dynamic> booking(Map<String, dynamic> extra) => {
          'id': 'b1',
          'booking_number': 12,
          'booking_code': 'FF-000012',
          'status': 'completed',
          'vehicle_type': 'scooter',
          'service_id': 's1',
          'package_id': 'p1',
          'service_name': 'General Service',
          'package_name': 'Basic',
          'package_inclusions': ['Wash'],
          'estimated_duration_minutes': 90,
          'customer_name': 'Asha',
          'customer_phone': '+919876543210',
          'address_line': '12 MG Road',
          'landmark': null,
          'city': 'Bhopal',
          'state': null,
          'pincode': '462001',
          'latitude': null,
          'longitude': null,
          'scheduled_date': '2026-10-21',
          'slot_start': '09:00:00',
          'slot_end': '11:00:00',
          'package_price': '499.00',
          'extra_charges_total': '0.00',
          'total_amount': '499.00',
          'extra_charges': [],
          'customer_notes': null,
          'cancellation_reason': null,
          'created_at': '2026-10-19T08:00:00Z',
          'can_cancel': false,
          'can_modify': false,
          'cancel_blocked_reason': null,
          ...extra,
        };

    test('parses the timeline and the dates', () {
      final b = Booking.fromJson(booking({
        'confirmed_at': '2026-10-19T09:00:00Z',
        'completed_at': '2026-10-21T12:00:00Z',
        'timeline': [
          {'status': 'pending_payment', 'at': '2026-10-19T08:00:00Z'},
          {'status': 'confirmed', 'at': '2026-10-19T09:00:00Z'},
        ],
      }));
      expect(b.timeline.map((e) => e.status), [
        BookingStatus.pendingPayment,
        BookingStatus.confirmed,
      ]);
      expect(b.confirmedAt, DateTime.utc(2026, 10, 19, 9));
      expect(b.completedAt, DateTime.utc(2026, 10, 21, 12));
      expect(b.cancelledAt, isNull);
    });

    test('a list item without a timeline has none', () {
      expect(Booking.fromJson(booking({})).timeline, isEmpty);
      expect(Booking.fromJson(booking({'timeline': []})).timeline, isEmpty);
    });

    test('an unknown status in the timeline is rejected', () {
      expect(
        () => Booking.fromJson(booking({
          'timeline': [
            {'status': 'teleported', 'at': '2026-10-19T08:00:00Z'},
          ],
        })),
        throwsFormatException,
      );
    });
  });

  group('NotificationRepository', () {
    test('list sends paging and the unread filter only when asked', () async {
      final api = StubApi((_) => (200, _page([_note()])));
      final repo = _repo(api);
      await repo.list(limit: 10, offset: 20);
      expect(api.last.method, 'GET');
      expect(api.last.path, endsWith('/notifications'));
      expect(api.last.query, {'limit': 10, 'offset': 20});
      await repo.list(unreadOnly: true);
      expect(api.last.query['unread_only'], true);
    });

    test('unread count', () async {
      final api = StubApi((_) => (200, {'unread': 3}));
      expect(await _repo(api).unreadCount(), 3);
      expect(api.last.path, endsWith('/notifications/unread-count'));
    });

    test('mark some read sends the ids, mark all sends none', () async {
      final api = StubApi((_) => (200, {'updated': 1, 'unread': 2}));
      final repo = _repo(api);
      expect(await repo.markRead(['n1']), 2);
      expect(api.last.method, 'POST');
      expect(api.last.path, endsWith('/notifications/read'));
      expect(api.last.body, {'ids': ['n1']});
      await repo.markRead();
      expect(api.last.body, <String, dynamic>{});
    });

    test('a 403 (not a customer) becomes a forbidden ApiException', () async {
      final api = StubApi((_) => (403, {'detail': 'Not allowed'}));
      await expectLater(
        _repo(api).unreadCount(),
        throwsA(isA<ApiException>()
            .having((e) => e.type, 'type', ApiErrorType.forbidden)),
      );
    });

    test('a malformed answer becomes an invalid-response error', () async {
      final api = StubApi((_) => (200, {'items': 'no'}));
      await expectLater(
        _repo(api).list(),
        throwsA(isA<ApiException>()
            .having((e) => e.type, 'type', ApiErrorType.invalidResponse)),
      );
      final api2 = StubApi((_) => (200, {'unread': 'many'}));
      await expectLater(
        _repo(api2).unreadCount(),
        throwsA(isA<ApiException>()
            .having((e) => e.type, 'type', ApiErrorType.invalidResponse)),
      );
    });
  });
}
