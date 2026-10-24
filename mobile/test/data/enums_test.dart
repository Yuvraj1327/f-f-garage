import 'package:ff_garage/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every value round-trips through its API string', () {
    for (final v in UserRole.values) {
      expect(UserRole.fromApiValue(v.apiValue), v);
    }
    for (final v in VehicleType.values) {
      expect(VehicleType.fromApiValue(v.apiValue), v);
    }
    for (final v in ExtraChargeType.values) {
      expect(ExtraChargeType.fromApiValue(v.apiValue), v);
    }
    for (final v in BookingStatus.values) {
      expect(BookingStatus.fromApiValue(v.apiValue), v);
    }
    for (final v in PaymentStatus.values) {
      expect(PaymentStatus.fromApiValue(v.apiValue), v);
    }
  });

  test('snake_case database values map to camelCase members', () {
    expect(BookingStatus.fromApiValue('pending_payment'),
        BookingStatus.pendingPayment);
    expect(BookingStatus.onTheWay.apiValue, 'on_the_way');
    expect(ExtraChargeType.engineOil.apiValue, 'engine_oil');
  });

  test('an unknown value throws a FormatException', () {
    expect(() => UserRole.fromApiValue('superuser'), throwsFormatException);
    expect(() => BookingStatus.fromApiValue(''), throwsFormatException);
  });
}
