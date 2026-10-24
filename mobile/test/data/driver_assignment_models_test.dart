import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/driver.dart';
import 'package:ff_garage/data/models/driver_job.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/repositories/admin_booking_repository.dart';
import 'package:ff_garage/data/repositories/admin_driver_repository.dart';
import 'package:ff_garage/data/repositories/driver_work_repository.dart';
import 'package:ff_garage/data/services/admin_booking_api_service.dart';
import 'package:ff_garage/data/services/admin_driver_api_service.dart';
import 'package:ff_garage/data/services/driver_work_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_api.dart';

Map<String, dynamic> _job([Map<String, dynamic> override = const {}]) => {
      'id': 'b1',
      'booking_code': 'FF-000012',
      'status': 'assigned',
      'vehicle_type': 'scooter',
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
      'latitude': 23.25,
      'longitude': null,
      'scheduled_date': '2026-10-21',
      'slot_start': '09:00:00',
      'slot_end': '11:00:00',
      'customer_notes': null,
      'extra_charges': [],
      'next_status': 'on_the_way',
      ...override,
    };

Map<String, dynamic> _driver([Map<String, dynamic> override = const {}]) => {
      'id': 'd1',
      'driver_login_id': 'ravi01',
      'full_name': 'Ravi Kumar',
      'phone': '+919876500001',
      'is_active': true,
      'open_bookings': 2,
      'created_at': '2026-10-01T08:00:00Z',
      ...override,
    };

void main() {
  group('DriverJob', () {
    test('parses what a driver needs and has no prices', () {
      final job = DriverJob.fromJson(_job());
      expect(job.code, 'FF-000012');
      expect(job.status, BookingStatus.assigned);
      expect(job.nextStatus, BookingStatus.onTheWay);
      expect(job.timeLabel, contains('9:00'));
      expect(job.latitude, 23.25);
      expect(job.longitude, isNull);
      expect(job.isFinished, isFalse);
    });

    test('a finished job has no next step', () {
      final job = DriverJob.fromJson(
        _job({'status': 'completed', 'next_status': null}),
      );
      expect(job.nextStatus, isNull);
      expect(job.isFinished, isTrue);
    });

    test('rejects an unknown status', () {
      expect(
        () => DriverJob.fromJson(_job({'status': 'teleported'})),
        throwsFormatException,
      );
    });
  });

  group('DriverAccount and assignments', () {
    test('parses a driver account', () {
      final driver = DriverAccount.fromJson(_driver());
      expect(driver.label, 'Ravi Kumar');
      expect(driver.openBookings, 2);
      expect(driver.isActive, isTrue);
    });

    test('the label falls back to the login ID; missing count is zero', () {
      final driver = DriverAccount.fromJson(
        _driver({'full_name': null, 'open_bookings': null}),
      );
      expect(driver.label, 'ravi01');
      expect(driver.openBookings, 0);
    });

    test('parses the assignment an admin sees', () {
      final a = AdminAssignment.fromJson({
        'driver_id': 'd1',
        'driver_name': 'Ravi Kumar',
        'driver_login_id': 'ravi01',
        'driver_phone': '+919876500001',
        'driver_is_active': false,
        'assigned_at': '2026-10-19T10:00:00Z',
      });
      expect(a.label, 'Ravi Kumar');
      expect(a.driverIsActive, isFalse);
    });

    test('the customer sees only name and phone', () {
      final d = DriverSummary.fromJson({'name': 'Ravi', 'phone': '+91'});
      expect(d.label, 'Ravi');
      expect(DriverSummary.fromJson({}).label, 'Your driver');
    });

    test('parses an assignment history row', () {
      final h = AssignmentHistoryItem.fromJson({
        'id': 'h1',
        'driver_id': 'd1',
        'driver_name': null,
        'driver_login_id': 'ravi01',
        'assigned_by_name': 'Admin',
        'assigned_at': '2026-10-19T10:00:00Z',
        'unassigned_at': '2026-10-19T12:00:00Z',
        'is_active': false,
      });
      expect(h.label, 'ravi01');
      expect(h.unassignedAt, isNotNull);
      expect(h.isActive, isFalse);
    });
  });

  group('repositories', () {
    test('driver work: list and status update use the right calls', () async {
      final api = StubApi((r) {
        if (r.path.endsWith('/status')) {
          return (200, _job({'status': 'on_the_way', 'next_status': 'in_progress'}));
        }
        return (200, {'items': [_job()], 'total': 1, 'limit': 25, 'offset': 0});
      });
      final repo = DriverWorkRepository(DriverWorkApiService(api.client));

      final page = await repo.list(scope: 'history');
      expect(api.last.method, 'GET');
      expect(api.last.path, endsWith('/driver/bookings'));
      expect(api.last.query['scope'], 'history');
      expect(page.items.single.code, 'FF-000012');

      final job = await repo.updateStatus('b1', BookingStatus.onTheWay);
      expect(api.last.method, 'POST');
      expect(api.last.path, endsWith('/driver/bookings/b1/status'));
      expect(api.last.body, {'status': 'on_the_way'});
      expect(job.status, BookingStatus.onTheWay);
    });

    test('driver work: a 404 becomes a not-found ApiException', () async {
      final api = StubApi((_) => (404, {'detail': 'Booking not found'}));
      final repo = DriverWorkRepository(DriverWorkApiService(api.client));
      await expectLater(
        repo.get('x'),
        throwsA(
          isA<ApiException>().having((e) => e.type, 'type', ApiErrorType.notFound),
        ),
      );
    });

    test('admin: assign uses PUT, unassign uses DELETE', () async {
      final api = StubApi((r) => (200, _adminBooking()));
      final repo = AdminBookingRepository(AdminBookingApiService(api.client));

      final booking = await repo.assign('b1', 'd1');
      expect(api.last.method, 'PUT');
      expect(api.last.path, endsWith('/admin/bookings/b1/driver'));
      expect(api.last.body, {'driver_id': 'd1'});
      expect(booking.assignment?.driverId, 'd1');
      expect(booking.canUnassign, isTrue);

      await repo.unassign('b1');
      expect(api.last.method, 'DELETE');
      expect(api.last.path, endsWith('/admin/bookings/b1/driver'));
    });

    test('admin: a conflict is reported, not swallowed', () async {
      final api = StubApi(
        (_) => (409, {'detail': 'That driver already has a visit then'}),
      );
      final repo = AdminBookingRepository(AdminBookingApiService(api.client));
      await expectLater(
        repo.assign('b1', 'd1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.conflict)
              .having((e) => e.message, 'message', contains('already has')),
        ),
      );
    });

    test('admin: booking list sends the filters', () async {
      final api = StubApi(
        (_) => (200, {'items': [], 'total': 0, 'limit': 25, 'offset': 0}),
      );
      final repo = AdminBookingRepository(AdminBookingApiService(api.client));
      await repo.list(statuses: [BookingStatus.confirmed], query: ' FF-12 ');
      expect(api.last.query['status'], ['confirmed']);
      expect(api.last.query['q'], 'FF-12');
    });

    test('admin: drivers create sends only what was given', () async {
      final api = StubApi((_) => (201, _driver()));
      final repo = AdminDriverRepository(AdminDriverApiService(api.client));
      await repo.create(driverId: 'ravi01', password: 'pw', fullName: 'Ravi');
      expect(api.last.method, 'POST');
      expect(api.last.body, {
        'driver_id': 'ravi01',
        'password': 'pw',
        'full_name': 'Ravi',
      });
    });

    test('a malformed response becomes an invalid-response error', () async {
      final api = StubApi((_) => (200, {'id': 'd1'}));
      final repo = AdminDriverRepository(AdminDriverApiService(api.client));
      await expectLater(
        repo.get('d1'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.invalidResponse),
        ),
      );
    });
  });

  test('Booking parses driver and assignment fields', () {
    final b = Booking.fromJson({
      ..._adminBooking(),
      'driver': {'name': 'Ravi', 'phone': '+91'},
    });
    expect(b.driver?.name, 'Ravi');
    expect(b.assignment?.driverId, 'd1');
    expect(b.canAssign, isTrue);
  });
}

Map<String, dynamic> _adminBooking() => {
      'id': 'b1',
      'booking_number': 12,
      'booking_code': 'FF-000012',
      'status': 'assigned',
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
      'can_cancel': true,
      'can_modify': false,
      'cancel_blocked_reason': null,
      'assignment': {
        'driver_id': 'd1',
        'driver_name': 'Ravi Kumar',
        'driver_login_id': 'ravi01',
        'driver_phone': '+919876500001',
        'driver_is_active': true,
        'assigned_at': '2026-10-19T10:00:00Z',
      },
      'can_assign': true,
      'can_unassign': true,
    };
