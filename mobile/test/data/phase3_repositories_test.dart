import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/repositories/availability_repository.dart';
import 'package:ff_garage/data/repositories/catalog_repository.dart';
import 'package:ff_garage/data/repositories/service_area_repository.dart';
import 'package:ff_garage/data/services/availability_api_service.dart';
import 'package:ff_garage/data/services/catalog_api_service.dart';
import 'package:ff_garage/data/services/service_area_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_api.dart';

const _pkgJson = {
  'id': 'p1', 'service_id': 's1', 'name': 'Basic', 'description': null,
  'price': '499.00', 'inclusions': ['Wash'], 'estimated_duration_minutes': null,
  'display_order': 0, 'is_active': true,
};

const _chargeJson = {
  'id': 'c1', 'service_id': 's1', 'package_id': null, 'charge_type': 'spare_part',
  'name': 'Air filter', 'description': null, 'amount': null, 'is_active': true,
};

const _areaJson = {
  'id': 'a1', 'pincode': '462001', 'area_name': 'New Market', 'city': 'Bhopal',
  'state': 'MP', 'is_active': true,
};

void main() {
  group('CatalogRepository', () {
    test('browse sends the vehicle filter and parses services', () async {
      final api = StubApi((_) => (200, <Object>[]));
      final repo = CatalogRepository(CatalogApiService(api.client));
      await repo.browse(vehicleType: VehicleType.bike);
      expect(api.last.method, 'GET');
      expect(api.last.path, '/catalog/services');
      expect(api.last.query, {'vehicle_type': 'bike'});
      await repo.browse();
      expect(api.last.query, isEmpty);
    });

    test('createPackage formats the price with two decimals', () async {
      final api = StubApi((_) => (201, _pkgJson));
      await CatalogRepository(CatalogApiService(api.client)).createPackage(
        's1',
        name: 'Basic',
        price: 499.5,
        inclusions: ['Wash'],
      );
      expect(api.last.method, 'POST');
      expect(api.last.path, '/admin/services/s1/packages');
      expect(api.last.body, containsPair('price', '499.50'));
      expect(api.last.body, containsPair('inclusions', ['Wash']));
      expect(api.last.body, containsPair('estimated_duration_minutes', null));
    });

    test('updates send only the changed fields', () async {
      final api = StubApi((_) => (200, _pkgJson));
      await CatalogRepository(CatalogApiService(api.client))
          .updatePackage('p1', {'is_active': false});
      expect(api.last.method, 'PATCH');
      expect(api.last.path, '/admin/packages/p1');
      expect(api.last.body, {'is_active': false});
    });

    test('createCharge sends a null amount for "at actuals"', () async {
      final api = StubApi((_) => (201, _chargeJson));
      await CatalogRepository(CatalogApiService(api.client)).createCharge(
        's1',
        name: 'Air filter',
        chargeType: ExtraChargeType.sparePart,
        packageId: 'p1',
      );
      expect(api.last.path, '/admin/services/s1/extra-charges');
      expect(api.last.body, containsPair('amount', null));
      expect(api.last.body, containsPair('charge_type', 'spare_part'));
      expect(api.last.body, containsPair('package_id', 'p1'));
    });

    test('deleteCharge accepts an empty 204', () async {
      final api = StubApi((_) => (204, null));
      await CatalogRepository(CatalogApiService(api.client)).deleteCharge('c1');
      expect(api.last.method, 'DELETE');
      expect(api.last.path, '/admin/extra-charges/c1');
    });

    test('a malformed response becomes an ApiException, not a crash', () async {
      final api = StubApi((_) => (200, {'id': 'p1'}));
      await expectLater(
        CatalogRepository(CatalogApiService(api.client)).updatePackage('p1', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.invalidResponse),
        ),
      );
    });

    test('a 409 from the server surfaces as a conflict with its message', () async {
      final api = StubApi((_) => (409, {'detail': 'Name already in use'}));
      await expectLater(
        CatalogRepository(CatalogApiService(api.client)).createService(
          name: 'X Service',
          vehicleType: VehicleType.bike,
          category: 'General',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.conflict)
              .having((e) => e.message, 'message', 'Name already in use'),
        ),
      );
    });

    test('a 403 (not an admin) surfaces as forbidden', () async {
      final api = StubApi((_) => (403, {'detail': 'No permission'}));
      await expectLater(
        CatalogRepository(CatalogApiService(api.client)).adminList(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.type, 'type', ApiErrorType.forbidden),
        ),
      );
    });
  });

  group('ServiceAreaRepository', () {
    test('checkPincode passes the PIN as a query parameter', () async {
      final api = StubApi((_) => (200, {'pincode': '462001', 'serviceable': true}));
      final result = await ServiceAreaRepository(ServiceAreaApiService(api.client))
          .checkPincode('462001');
      expect(api.last.path, '/service-areas/check');
      expect(api.last.query, {'pincode': '462001'});
      expect(result.serviceable, isTrue);
    });

    test('create and update hit the admin endpoints', () async {
      final api = StubApi((_) => (200, _areaJson));
      final repo = ServiceAreaRepository(ServiceAreaApiService(api.client));
      await repo.create(
        pincode: '462001', areaName: 'New Market', city: 'Bhopal', state: 'MP',
      );
      expect(api.last.method, 'POST');
      expect(api.last.path, '/admin/service-areas');
      await repo.update('a1', {'is_active': false});
      expect(api.last.method, 'PATCH');
      expect(api.last.path, '/admin/service-areas/a1');
      await repo.delete('a1');
      expect(api.last.method, 'DELETE');
    });
  });

  group('AvailabilityRepository', () {
    test('createSlot sends API-format times and sorted days', () async {
      final api = StubApi(
        (_) => (201, {
          'id': 'sl1', 'start_time': '09:00:00', 'end_time': '11:00:00',
          'capacity': 2, 'days_of_week': [1, 2], 'is_active': true,
        }),
      );
      await AvailabilityRepository(AvailabilityApiService(api.client)).createSlot(
        start: const ClockTime(9, 0),
        end: const ClockTime(11, 0),
        capacity: 2,
        daysOfWeek: [1, 2],
      );
      expect(api.last.path, '/admin/availability/slots');
      expect(api.last.body, containsPair('start_time', '09:00'));
      expect(api.last.body, containsPair('end_time', '11:00'));
    });

    test('exceptions and availability use inclusive date ranges', () async {
      final api = StubApi((_) => (200, <Object>[]));
      final repo = AvailabilityRepository(AvailabilityApiService(api.client));
      await repo.exceptions(DateTime(2026, 10, 1), DateTime(2026, 10, 31));
      expect(api.last.query, {'start_date': '2026-10-01', 'end_date': '2026-10-31'});
      await repo.availability(DateTime(2026, 10, 20));
      expect(api.last.query, {'start_date': '2026-10-20'});
      await repo.availability(DateTime(2026, 10, 20), DateTime(2026, 10, 26));
      expect(api.last.query, {'start_date': '2026-10-20', 'end_date': '2026-10-26'});
    });

    test('createException omits capacity unless opening a slot', () async {
      final api = StubApi(
        (_) => (201, {
          'id': 'e1', 'exception_date': '2026-11-08', 'time_slot_id': null,
          'is_open': false, 'capacity': null, 'reason': 'Diwali',
        }),
      );
      await AvailabilityRepository(AvailabilityApiService(api.client))
          .createException(date: DateTime(2026, 11, 8), reason: 'Diwali');
      expect(api.last.body, {
        'exception_date': '2026-11-08',
        'time_slot_id': null,
        'is_open': false,
        'capacity': null,
        'reason': 'Diwali',
      });
    });
  });
}
