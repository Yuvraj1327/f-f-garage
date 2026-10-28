import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/vehicle_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the list has the brands the garage asked for', () {
    final makes = vehicleMakes();
    for (final make in [
      'Hero', 'Honda', 'TVS', 'Bajaj', 'Suzuki', 'Yamaha', 'Royal Enfield',
      'KTM', 'BMW Motorrad', 'Triumph', 'Vespa', 'Aprilia', 'Ather',
      'Ola Electric',
    ]) {
      expect(makes, contains(make));
    }
    expect(makes, orderedEquals([...makes]..sort()));
  });

  test('every make has at least one model and no duplicate models', () {
    vehicleCatalog.forEach((make, models) {
      expect(models, isNotEmpty, reason: make);
      final names = models.map((m) => m.name).toList();
      expect(names.toSet().length, names.length, reason: make);
    });
  });

  test('models are filtered by vehicle type, with a fallback', () {
    expect(vehicleModels('Honda', VehicleType.scooter), contains('Activa 6G'));
    expect(vehicleModels('Honda', VehicleType.scooter), isNot(contains('Shine')));
    expect(vehicleModels('Honda', VehicleType.bike), contains('Shine'));
    // Vespa only makes scooters: a bike owner still sees them.
    expect(vehicleModels('Vespa', VehicleType.bike), isNotEmpty);
    expect(vehicleModels('Nobody', VehicleType.bike), isEmpty);
  });

  test('a make typed by hand is matched to the list ignoring case', () {
    expect(knownMake(' honda '), 'Honda');
    expect(knownMake('Lohia'), isNull);
  });
}
