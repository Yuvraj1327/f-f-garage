import 'enums.dart';
import 'json_reader.dart';

/// One of the customer's saved two-wheelers (`/vehicles`).
class Vehicle {
  const Vehicle({
    required this.id,
    required this.type,
    required this.registration,
    required this.make,
    required this.model,
    this.nickname,
  });

  /// Throws [FormatException] when a field is missing or has the wrong type.
  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: JsonReader.string(json, 'id'),
        type: VehicleType.fromApiValue(JsonReader.string(json, 'vehicle_type')),
        registration: JsonReader.string(json, 'registration_number'),
        make: JsonReader.string(json, 'make'),
        model: JsonReader.string(json, 'model'),
        nickname: JsonReader.optionalString(json, 'nickname'),
      );

  final String id;
  final VehicleType type;

  /// Upper-case, no spaces (MH12AB1234).
  final String registration;
  final String make;
  final String model;
  final String? nickname;

  /// What the lists show as the title: the nickname, else "Make Model".
  String get title =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : '$make $model';

  /// "MH12 AB 1234" style, for reading.
  String get registrationPretty {
    final match =
        RegExp(r'^([A-Z]{2}\d{1,2})([A-Z]{0,3})(\d{4})$').firstMatch(registration);
    if (match == null) return registration;
    return [match[1], if (match[2]!.isNotEmpty) match[2], match[3]].join(' ');
  }
}

/// Plate shapes the server accepts (same rule, so mistakes are caught before a
/// round trip): MH12AB1234, DL1CAB1234 and the Bharat series 22BH1234AA.
String? normalizeRegistration(String raw) {
  final value = raw.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
  final ok = RegExp(r'^[A-Z]{2}\d{1,2}[A-Z]{0,3}\d{4}$').hasMatch(value) ||
      RegExp(r'^\d{2}BH\d{4}[A-Z]{1,2}$').hasMatch(value);
  return ok ? value : null;
}
