import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/data/models/catalog.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/json_reader.dart';
import 'package:ff_garage/data/models/service_area.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _charge({String? packageId, Object? amount = '350.00'}) => {
      'id': 'c1',
      'service_id': 's1',
      'package_id': packageId,
      'charge_type': 'engine_oil',
      'name': 'Engine oil',
      'description': null,
      'amount': amount,
      'is_active': true,
    };

Map<String, dynamic> _package({List<Map<String, dynamic>>? charges}) => {
      'id': 'p1',
      'service_id': 's1',
      'name': 'Basic',
      'description': null,
      'price': '499.00',
      'inclusions': ['Wash', 'Oil top-up'],
      'estimated_duration_minutes': 90,
      'display_order': 0,
      'is_active': true,
      if (charges != null) 'extra_charges': charges,
    };

Map<String, dynamic> _service() => {
      'id': 's1',
      'name': 'General Service',
      'vehicle_type': 'scooter',
      'category': 'Maintenance',
      'description': 'Routine',
      'display_order': 1,
      'is_active': true,
      'packages': [
        _package(charges: [_charge(packageId: 'p1')]),
        {..._package(), 'id': 'p2', 'price': 299, 'is_active': false},
      ],
      'extra_charges': [_charge()],
    };

void main() {
  group('catalogue models', () {
    test('parse a full service with money as strings or numbers', () {
      final s = GarageService.fromJson(_service());
      expect(s.vehicleType, VehicleType.scooter);
      expect(s.packages.first.price, 499.0);
      expect(s.packages.last.price, 299.0);
      expect(s.packages.first.inclusions, ['Wash', 'Oil top-up']);
      expect(s.extraCharges.single.amount, 350.0);
      expect(s.extraCharges.single.packageId, isNull);
      expect(s.packages.first.extraCharges.single.packageId, 'p1');
    });

    test('starting price ignores inactive packages', () {
      expect(GarageService.fromJson(_service()).startingPrice, 499.0);
    });

    test('chargesFor combines service-wide and package charges', () {
      final s = GarageService.fromJson(_service());
      expect(s.chargesFor(s.packages.first), hasLength(2));
      expect(s.chargesFor(s.packages.last), hasLength(1));
    });

    test('an amount of null means "at actuals"', () {
      expect(ExtraCharge.fromJson(_charge(amount: null)).amount, isNull);
    });

    test('malformed data throws FormatException (never a silent default)', () {
      expect(
        () => GarageService.fromJson({..._service(), 'vehicle_type': 'car'}),
        throwsFormatException,
      );
      expect(
        () => GarageService.fromJson({..._service(), 'packages': 'x'}),
        throwsFormatException,
      );
      expect(
        () => ServicePackage.fromJson({..._package(), 'price': 'free'}),
        throwsFormatException,
      );
      expect(
        () => ServicePackage.fromJson({..._package(), 'price': null}),
        throwsFormatException,
      );
      expect(
        () => ServicePackage.fromJson({..._package(), 'inclusions': [1]}),
        throwsFormatException,
      );
      expect(
        () => ExtraCharge.fromJson({..._charge(), 'charge_type': 'tax'}),
        throwsFormatException,
      );
    });
  });

  group('service areas', () {
    test('area and pincode check', () {
      final a = ServiceArea.fromJson({
        'id': 'a1', 'pincode': '462001', 'area_name': 'New Market',
        'city': 'Bhopal', 'state': 'MP', 'is_active': true,
      });
      expect(a.pincode, '462001');
      final no = PincodeCheck.fromJson({'pincode': '999999', 'serviceable': false});
      expect(no.serviceable, isFalse);
      expect(no.city, isNull);
      expect(() => PincodeCheck.fromJson({'pincode': '1'}), throwsFormatException);
    });
  });

  group('availability models', () {
    test('ClockTime parses, formats and compares', () {
      expect(ClockTime.parse('09:30:00'), const ClockTime(9, 30));
      expect(ClockTime.parse('09:30').toApi(), '09:30');
      expect(const ClockTime(9, 5).format(), '9:05 AM');
      expect(const ClockTime(0, 0).format(), '12:00 AM');
      expect(const ClockTime(12, 0).format(), '12:00 PM');
      expect(const ClockTime(15, 45).format(), '3:45 PM');
      expect(const ClockTime(9, 0).compareTo(const ClockTime(10, 0)), lessThan(0));
      for (final bad in ['9:30', '25:00', '09:61', 'noon', '']) {
        expect(() => ClockTime.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('weekday descriptions', () {
      expect(describeWeekdays([1, 2, 3, 4, 5, 6, 7]), 'Every day');
      expect(describeWeekdays([1, 2, 3, 4, 5]), 'Mon - Fri');
      expect(describeWeekdays([1, 3, 6]), 'Mon, Wed, Sat');
      expect(describeWeekdays([6, 7]), 'Sat, Sun');
      expect(describeWeekdays([5, 1, 1]), 'Mon, Fri');
    });

    test('time slot, exception and day availability parse', () {
      final slot = TimeSlot.fromJson({
        'id': 'sl1', 'start_time': '09:00:00', 'end_time': '11:00:00',
        'capacity': 2, 'days_of_week': [1, 2, 3], 'is_active': true,
      });
      expect(slot.label, '9:00 AM - 11:00 AM');
      final e = AvailabilityException.fromJson({
        'id': 'e1', 'exception_date': '2026-11-08', 'time_slot_id': null,
        'is_open': false, 'capacity': null, 'reason': 'Diwali',
      });
      expect(e.date, DateTime(2026, 11, 8));
      expect(e.isWholeDay, isTrue);
      final day = DayAvailability.fromJson({
        'date': '2026-10-20', 'is_open': true, 'closed_reason': null, 'note': null,
        'slots': [
          {
            'slot_id': 'sl1', 'start_time': '09:00:00', 'end_time': '11:00:00',
            'available': false, 'reason': 'fully_booked', 'spots_left': 0,
          },
        ],
      });
      expect(day.slots.single.reason, 'fully_booked');
    });

    test('dates are calendar dates, formatted back without shifting', () {
      final d = JsonReader.date({'d': '2026-01-05'}, 'd');
      expect(d, DateTime(2026, 1, 5));
      expect(formatApiDate(d), '2026-01-05');
    });
  });
}
