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
    this.refundPolicy = '',
    this.advancePercent = 20,
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
      refundPolicy: read('refund_policy'),
      advancePercent: _percent(json['advance_percent']),
    );
  }

  final String name;
  final String phone;
  final String whatsapp;
  final String email;
  final String address;
  final String hours;

  /// The garage's own refund policy text (empty = none configured).
  final String refundPolicy;

  /// Share of the price paid when booking (a service can set its own).
  final double advancePercent;

  bool get hasRefundPolicy => refundPolicy.isNotEmpty;
  bool get hasPhone => phone.isNotEmpty;
  bool get hasWhatsapp => whatsapp.isNotEmpty;
  bool get hasEmail => email.isNotEmpty;
  bool get hasAddress => address.isNotEmpty;
  bool get hasHours => hours.isNotEmpty;

  /// True when there is at least one way to reach the garage.
  bool get hasAnyContact => hasPhone || hasWhatsapp || hasEmail || hasAddress;
}

double _percent(Object? value) {
  final parsed = switch (value) {
    num n => n.toDouble(),
    String t => double.tryParse(t),
    _ => null,
  };
  return parsed != null && parsed > 0 && parsed <= 100 ? parsed : 20;
}
