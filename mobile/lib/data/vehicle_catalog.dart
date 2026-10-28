import 'models/enums.dart';

/// A model in the pick list and whether it is a bike or a scooter.
class ModelEntry {
  const ModelEntry(this.name, this.type);

  final String name;
  final VehicleType type;
}

const VehicleType _b = VehicleType.bike;
const VehicleType _s = VehicleType.scooter;

/// Popular two-wheeler makes and their common models, for the pick lists on
/// the Add vehicle screen. It only saves typing: anything not listed can be
/// typed in by hand, and nothing here is checked against an RTO or any other
/// registry.
const Map<String, List<ModelEntry>> vehicleCatalog = {
  'Hero': [
    ModelEntry('Splendor Plus', _b),
    ModelEntry('HF Deluxe', _b),
    ModelEntry('Passion Pro', _b),
    ModelEntry('Glamour', _b),
    ModelEntry('Super Splendor', _b),
    ModelEntry('Xtreme 125R', _b),
    ModelEntry('Xtreme 160R', _b),
    ModelEntry('Xpulse 200', _b),
    ModelEntry('Karizma XMR', _b),
    ModelEntry('Pleasure Plus', _s),
    ModelEntry('Destini 125', _s),
    ModelEntry('Maestro Edge 125', _s),
    ModelEntry('Xoom 110', _s),
  ],
  'Honda': [
    ModelEntry('Shine', _b),
    ModelEntry('Shine 100', _b),
    ModelEntry('SP 125', _b),
    ModelEntry('Unicorn', _b),
    ModelEntry('Hornet 2.0', _b),
    ModelEntry('CB200X', _b),
    ModelEntry('CB350', _b),
    ModelEntry('Activa 6G', _s),
    ModelEntry('Activa 125', _s),
    ModelEntry('Dio', _s),
    ModelEntry('Dio 125', _s),
  ],
  'TVS': [
    ModelEntry('Apache RTR 160', _b),
    ModelEntry('Apache RTR 160 4V', _b),
    ModelEntry('Apache RTR 200 4V', _b),
    ModelEntry('Apache RR 310', _b),
    ModelEntry('Raider 125', _b),
    ModelEntry('Star City Plus', _b),
    ModelEntry('Sport', _b),
    ModelEntry('Radeon', _b),
    ModelEntry('Ronin', _b),
    ModelEntry('Jupiter', _s),
    ModelEntry('Jupiter 125', _s),
    ModelEntry('Ntorq 125', _s),
    ModelEntry('Zest', _s),
    ModelEntry('iQube', _s),
  ],
  'Bajaj': [
    ModelEntry('Pulsar 125', _b),
    ModelEntry('Pulsar 150', _b),
    ModelEntry('Pulsar N160', _b),
    ModelEntry('Pulsar NS200', _b),
    ModelEntry('Pulsar 220F', _b),
    ModelEntry('Platina', _b),
    ModelEntry('CT 110', _b),
    ModelEntry('Avenger Street 160', _b),
    ModelEntry('Dominar 250', _b),
    ModelEntry('Dominar 400', _b),
    ModelEntry('Freedom 125', _b),
    ModelEntry('Chetak', _s),
  ],
  'Suzuki': [
    ModelEntry('Gixxer', _b),
    ModelEntry('Gixxer SF', _b),
    ModelEntry('Gixxer 250', _b),
    ModelEntry('V-Strom SX', _b),
    ModelEntry('Hayabusa', _b),
    ModelEntry('Access 125', _s),
    ModelEntry('Burgman Street', _s),
    ModelEntry('Avenis', _s),
  ],
  'Yamaha': [
    ModelEntry('FZ-S Fi', _b),
    ModelEntry('FZ-X', _b),
    ModelEntry('MT-15', _b),
    ModelEntry('R15 V4', _b),
    ModelEntry('R3', _b),
    ModelEntry('MT-03', _b),
    ModelEntry('Fascino 125', _s),
    ModelEntry('RayZR 125', _s),
    ModelEntry('Aerox 155', _s),
  ],
  'Royal Enfield': [
    ModelEntry('Classic 350', _b),
    ModelEntry('Bullet 350', _b),
    ModelEntry('Hunter 350', _b),
    ModelEntry('Meteor 350', _b),
    ModelEntry('Himalayan 450', _b),
    ModelEntry('Scram 411', _b),
    ModelEntry('Interceptor 650', _b),
    ModelEntry('Continental GT 650', _b),
    ModelEntry('Super Meteor 650', _b),
    ModelEntry('Guerrilla 450', _b),
  ],
  'KTM': [
    ModelEntry('Duke 125', _b),
    ModelEntry('Duke 200', _b),
    ModelEntry('Duke 250', _b),
    ModelEntry('Duke 390', _b),
    ModelEntry('RC 200', _b),
    ModelEntry('RC 390', _b),
    ModelEntry('Adventure 250', _b),
    ModelEntry('Adventure 390', _b),
  ],
  'BMW Motorrad': [
    ModelEntry('G 310 R', _b),
    ModelEntry('G 310 GS', _b),
    ModelEntry('G 310 RR', _b),
    ModelEntry('F 850 GS', _b),
    ModelEntry('R 1250 GS', _b),
    ModelEntry('S 1000 RR', _b),
    ModelEntry('CE 04', _s),
  ],
  'Triumph': [
    ModelEntry('Speed 400', _b),
    ModelEntry('Scrambler 400 X', _b),
    ModelEntry('Trident 660', _b),
    ModelEntry('Street Triple', _b),
    ModelEntry('Bonneville T100', _b),
    ModelEntry('Tiger 900', _b),
  ],
  'Vespa': [
    ModelEntry('Vespa VXL 125', _s),
    ModelEntry('Vespa SXL 150', _s),
    ModelEntry('Vespa Elegante 150', _s),
    ModelEntry('Vespa ZX 125', _s),
  ],
  'Aprilia': [
    ModelEntry('SR 125', _s),
    ModelEntry('SR 160', _s),
    ModelEntry('SXR 160', _s),
    ModelEntry('Storm 125', _s),
    ModelEntry('RS 457', _b),
    ModelEntry('Tuono 457', _b),
  ],
  'Ather': [
    ModelEntry('450X', _s),
    ModelEntry('450S', _s),
    ModelEntry('450 Apex', _s),
    ModelEntry('Rizta', _s),
  ],
  'Ola Electric': [
    ModelEntry('S1 Pro', _s),
    ModelEntry('S1 Air', _s),
    ModelEntry('S1 X', _s),
    ModelEntry('Roadster', _b),
  ],
  'Kawasaki': [
    ModelEntry('Ninja 300', _b),
    ModelEntry('Ninja 400', _b),
    ModelEntry('Ninja 650', _b),
    ModelEntry('Z650', _b),
    ModelEntry('Z900', _b),
    ModelEntry('Versys 650', _b),
  ],
  'Harley-Davidson': [
    ModelEntry('X440', _b),
    ModelEntry('Street 750', _b),
    ModelEntry('Iron 883', _b),
    ModelEntry('Fat Boy', _b),
  ],
  'Ducati': [
    ModelEntry('Scrambler Icon', _b),
    ModelEntry('Monster', _b),
    ModelEntry('Panigale V2', _b),
    ModelEntry('Multistrada V2', _b),
  ],
  'Jawa': [
    ModelEntry('Jawa 42', _b),
    ModelEntry('Jawa 350', _b),
    ModelEntry('Perak', _b),
  ],
  'Yezdi': [
    ModelEntry('Roadster', _b),
    ModelEntry('Scrambler', _b),
    ModelEntry('Adventure', _b),
  ],
  'Mahindra': [
    ModelEntry('Mojo', _b),
    ModelEntry('Gusto', _s),
  ],
  'Husqvarna': [
    ModelEntry('Svartpilen 250', _b),
    ModelEntry('Vitpilen 250', _b),
    ModelEntry('Svartpilen 401', _b),
  ],
  'Benelli': [
    ModelEntry('TNT 300', _b),
    ModelEntry('Imperiale 400', _b),
    ModelEntry('Leoncino 500', _b),
    ModelEntry('TRK 502', _b),
  ],
  'Revolt': [
    ModelEntry('RV400', _b),
    ModelEntry('RV1', _b),
  ],
  'Bounce': [
    ModelEntry('Infinity E1', _s),
  ],
  'Simple Energy': [
    ModelEntry('Simple One', _s),
  ],
  'Okinawa': [
    ModelEntry('Praise Pro', _s),
    ModelEntry('iPraise+', _s),
  ],
};

/// Makes in the list, A to Z.
List<String> vehicleMakes() => vehicleCatalog.keys.toList()..sort();

/// The listed models of [make] for a [type], A to Z. Empty for a make that is
/// not in the list. Only the chosen type is listed, so a bike owner is not
/// offered scooters.
List<String> vehicleModels(String make, VehicleType type) {
  final entries = vehicleCatalog[make] ?? const <ModelEntry>[];
  final ofType = [
    for (final e in entries)
      if (e.type == type) e.name,
  ];
  // A brand with nothing of this type (a scooter-only brand for a bike) shows
  // all its models rather than an empty list.
  final names = ofType.isNotEmpty ? ofType : [for (final e in entries) e.name];
  return names..sort();
}

/// The make as spelled in the list when [typed] matches one ignoring case
/// (otherwise null), so "honda" saved by hand and "Honda" picked are one brand.
String? knownMake(String typed) {
  final t = typed.trim().toLowerCase();
  for (final make in vehicleCatalog.keys) {
    if (make.toLowerCase() == t) return make;
  }
  return null;
}
