import 'json_reader.dart';

/// The garage's own details, from `GET/PUT /admin/garage-settings`.
class GarageSettings {
  const GarageSettings({
    required this.name,
    required this.phone,
    required this.whatsapp,
    required this.email,
    required this.address,
    required this.hours,
    required this.fromDatabase,
    this.refundPolicy = '',
  });

  /// Throws [FormatException] when a field is missing or has the wrong type.
  factory GarageSettings.fromJson(Map<String, dynamic> json) {
    String read(String key) => JsonReader.optionalString(json, key) ?? '';
    return GarageSettings(
      name: JsonReader.string(json, 'name'),
      phone: read('phone'),
      whatsapp: read('whatsapp'),
      email: read('email'),
      address: read('address'),
      hours: read('hours'),
      fromDatabase: json['source'] == 'database',
      refundPolicy: read('refund_policy'),
    );
  }

  final String name;
  final String phone;
  final String whatsapp;
  final String email;
  final String address;
  final String hours;

  /// Shown to customers on the checkout and receipts. Refunds are decided by an
  /// admin one by one; this text only tells customers how.
  final String refundPolicy;

  /// False while the values still come from the server's `.env` defaults (an
  /// administrator has not saved anything yet).
  final bool fromDatabase;
}
