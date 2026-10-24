import 'json_reader.dart';

/// The garage's contact details from `GET /support/contact`. An empty string
/// means the operator has not configured that item, so the screen hides it.
class SupportContact {
  const SupportContact({
    required this.name,
    required this.phone,
    required this.whatsapp,
    required this.email,
    required this.address,
    required this.hours,
  });

  /// Throws [FormatException] when a field is missing or has the wrong type.
  factory SupportContact.fromJson(Map<String, dynamic> json) {
    String read(String key) => JsonReader.optionalString(json, key) ?? '';
    return SupportContact(
      name: read('name'),
      phone: read('phone'),
      whatsapp: read('whatsapp'),
      email: read('email'),
      address: read('address'),
      hours: read('hours'),
    );
  }

  final String name;
  final String phone;
  final String whatsapp;
  final String email;
  final String address;
  final String hours;

  bool get hasPhone => phone.isNotEmpty;
  bool get hasWhatsapp => whatsapp.isNotEmpty;
  bool get hasEmail => email.isNotEmpty;
  bool get hasAddress => address.isNotEmpty;
  bool get hasHours => hours.isNotEmpty;

  /// True when there is at least one way to reach the garage.
  bool get hasAnyContact => hasPhone || hasWhatsapp || hasEmail || hasAddress;
}
