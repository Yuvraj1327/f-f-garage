import 'enums.dart';

/// Response of `GET /api/v1/profiles/me`.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.role,
    required this.isActive,
    this.fullName,
    this.phone,
    this.email,
    this.driverLoginId,
  });

  /// Throws [FormatException] when a required field is missing or malformed.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final isActive = json['is_active'];
    if (isActive is! bool) {
      throw FormatException('Expected "is_active" to be a bool, got $isActive');
    }
    return UserProfile(
      id: _requiredString(json, 'id'),
      role: UserRole.fromApiValue(_requiredString(json, 'role')),
      isActive: isActive,
      fullName: _optionalString(json, 'full_name'),
      phone: _optionalString(json, 'phone'),
      email: _optionalString(json, 'email'),
      driverLoginId: _optionalString(json, 'driver_login_id'),
    );
  }

  final String id;
  final UserRole role;
  final bool isActive;
  final String? fullName;
  final String? phone;
  final String? email;

  /// Only set for drivers.
  final String? driverLoginId;

  /// A name to greet the user with.
  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return driverLoginId ?? email ?? 'there';
  }

  UserProfile copyWith({String? fullName, String? phone}) {
    return UserProfile(
      id: id,
      role: role,
      isActive: isActive,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email,
      driverLoginId: driverLoginId,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('Expected "$key" to be a non-empty string, got $value');
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('Expected "$key" to be a string or null, got $value');
  }
}
