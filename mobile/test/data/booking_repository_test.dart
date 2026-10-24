import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/repositories/booking_repository.dart';
import 'package:ff_garage/data/services/booking_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_api.dart';

Map<String, dynamic> _booking() => {
      'id': 'b1',
      'booking_number': 1,
      'booking_code': 'FF-000001',
      'status': 'pending_payment',
      'vehicle_type': 'scooter',
      'service_id': 's1',
      'package_id': 'p1',
      'service_name': 'General Service',
      'package_name': 'Basic',
      'package_inclusions': <String>[],
      'estimated_duration_minutes': null,
      'customer_name': 'Asha',
      'customer_phone': '+919876543210',
      'address_line': '12 MG Road',
      'landmark': null,
      'city': 'Bhopal',
      'state': null,
      'pincode': '462001',
      'scheduled_date': '2026-10-21',
      'slot_start': '09:00:00',
      'slot_end': '11:00:00',
      'package_price': '499.00',
      'extra_charges_total': '0.00',
      'total_amount': '499.00',
      'extra_charges': <Object>[],
      'customer_notes': null,
      'cancellation_reason': null,
      'created_at': '2026-10-19T08:00:00+05:30',
      'can_cancel': true,
      'can_modify': true,
      'cancel_blocked_reason': null,
    };

BookingRepository _repo(StubApi api) =>
    BookingRepository(BookingApiService(api.client));

NewBooking _draft({
  List<String> extras = const [],
  String? landmark,
  String? notes,
  double total = 499,
}) =>
    NewBooking(
      packageId: 'p1',
      extraChargeIds: extras,
      pincode: '462001',
      addressLine: '12 MG Road',
      landmark: landmark,
      date: DateTime(2026, 10, 21),
      timeSlotId: 'slot1',
      notes: notes,
      expectedTotal: total,
      clientRequestId: '11111111-1111-4111-8111-111111111111',
    );

void main() {
  test('quote asks about the package only', () async {
    final api = StubApi((_) => (
          200,
          {
            'service_id': 's1',
            'service_name': 'G',
            'vehicle_type': 'bike',
            'package_id': 'p1',
            'package_name': 'B',
            'inclusions': <String>[],
            'package_price': '1.00',
            'extra_charges': <Object>[],
            'extra_charges_total': '0.00',
            'total_amount': '1.00',
          },
        ));
    await _repo(api).quote('p1');
    expect(api.last.method, 'POST');
    expect(api.last.path, '/bookings/quote');
    expect(api.last.body, {'package_id': 'p1', 'extra_charge_ids': <String>[]});
  });

  group('create', () {
    test('sends no price, only the expected total as a string', () async {
      final api = StubApi((_) => (201, _booking()));
      final created = await _repo(api).create(_draft(extras: ['c1'], total: 849));
      expect(created.code, 'FF-000001');
      expect(api.last.method, 'POST');
      expect(api.last.path, '/bookings');
      final body = api.last.body! as Map<String, dynamic>;
      expect(body, {
        'package_id': 'p1',
        'extra_charge_ids': ['c1'],
        'pincode': '462001',
        'address_line': '12 MG Road',
        'scheduled_date': '2026-10-21',
        'time_slot_id': 'slot1',
        'expected_total': '849.00',
        'client_request_id': '11111111-1111-4111-8111-111111111111',
      });
      for (final forbidden in ['package_price', 'total_amount', 'price', 'status']) {
        expect(body.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('includes landmark and notes only when they have text', () async {
      final api = StubApi((_) => (201, _booking()));
      await _repo(api).create(_draft(landmark: '  Near the temple ', notes: ' Gate 4 '));
      var body = api.last.body! as Map<String, dynamic>;
      expect(body['landmark'], 'Near the temple');
      expect(body['customer_notes'], 'Gate 4');

      await _repo(api).create(_draft(landmark: '   ', notes: ''));
      body = api.last.body! as Map<String, dynamic>;
      expect(body.containsKey('landmark'), isFalse);
      expect(body.containsKey('customer_notes'), isFalse);
    });

    test('a 409 becomes a conflict with the server message', () async {
      final api = StubApi((_) => (409, {'detail': 'The price has changed.'}));
      await expectLater(
        _repo(api).create(_draft()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.conflict)
              .having((e) => e.message, 'message', 'The price has changed.'),
        ),
      );
    });

    test('a malformed booking is an invalid-response error', () async {
      final api = StubApi((_) => (201, {'id': 'x'}));
      await expectLater(
        _repo(api).create(_draft()),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.invalidResponse),
        ),
      );
    });
  });

  group('list', () {
    test('sends repeated status parameters, limit and offset', () async {
      final api = StubApi((_) => (
            200,
            {'items': <Object>[], 'total': 0, 'limit': 20, 'offset': 40},
          ));
      final page = await _repo(api).list(
        statuses: [BookingStatus.confirmed, BookingStatus.cancelled],
        offset: 40,
      );
      expect(api.last.path, '/bookings');
      expect(api.last.query, {
        'status': ['confirmed', 'cancelled'],
        'limit': 20,
        'offset': 40,
      });
      expect(page.items, isEmpty);
    });

    test('without a filter there is no status parameter', () async {
      final api = StubApi((_) => (
            200,
            {'items': [_booking()], 'total': 1, 'limit': 20, 'offset': 0},
          ));
      final page = await _repo(api).list();
      expect(api.last.query.containsKey('status'), isFalse);
      expect(page.items.single.id, 'b1');
    });
  });

  test('get reads one booking and a 404 is a not-found error', () async {
    final ok = StubApi((_) => (200, _booking()));
    expect((await _repo(ok).get('b1')).id, 'b1');
    expect(ok.last.path, '/bookings/b1');

    final missing = StubApi((_) => (404, {'detail': 'Booking not found'}));
    await expectLater(
      _repo(missing).get('zzz'),
      throwsA(
        isA<ApiException>().having((e) => e.type, 'type', ApiErrorType.notFound),
      ),
    );
  });

  test('update patches only the given fields', () async {
    final api = StubApi((_) => (200, _booking()));
    await _repo(api).update('b1', {'landmark': null, 'address_line': '14 New Road'});
    expect(api.last.method, 'PATCH');
    expect(api.last.path, '/bookings/b1');
    expect(api.last.body, {'landmark': null, 'address_line': '14 New Road'});
  });

  group('cancel', () {
    test('sends the trimmed reason, or nothing', () async {
      final api = StubApi((_) => (200, _booking()));
      await _repo(api).cancel('b1', reason: '  Changed my mind ');
      expect(api.last.method, 'POST');
      expect(api.last.path, '/bookings/b1/cancel');
      expect(api.last.body, {'reason': 'Changed my mind'});

      await _repo(api).cancel('b1', reason: '   ');
      expect(api.last.body, <String, dynamic>{});
      await _repo(api).cancel('b1');
      expect(api.last.body, <String, dynamic>{});
    });

    test('a refusal is a conflict with the server message', () async {
      final api = StubApi((_) => (409, {'detail': 'Too close to the visit'}));
      await expectLater(
        _repo(api).cancel('b1'),
        throwsA(
          isA<ApiException>().having((e) => e.message, 'message', 'Too close to the visit'),
        ),
      );
    });
  });
}
