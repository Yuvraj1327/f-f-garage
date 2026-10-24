import 'json_reader.dart';

/// What a customer sees about their driver.
class DriverSummary {
  const DriverSummary({this.name, this.phone});

  factory DriverSummary.fromJson(Map<String, dynamic> json) => DriverSummary(
        name: JsonReader.optionalString(json, 'name'),
        phone: JsonReader.optionalString(json, 'phone'),
      );

  final String? name;
  final String? phone;

  String get label => name ?? 'Your driver';
}

/// Who a booking is assigned to, as an admin sees it.
class AdminAssignment {
  const AdminAssignment({
    required this.driverId,
    required this.driverIsActive,
    required this.assignedAt,
    this.driverName,
    this.driverLoginId,
    this.driverPhone,
  });

  factory AdminAssignment.fromJson(Map<String, dynamic> json) =>
      AdminAssignment(
        driverId: JsonReader.string(json, 'driver_id'),
        driverName: JsonReader.optionalString(json, 'driver_name'),
        driverLoginId: JsonReader.optionalString(json, 'driver_login_id'),
        driverPhone: JsonReader.optionalString(json, 'driver_phone'),
        driverIsActive: json['driver_is_active'] == null
            ? true
            : JsonReader.boolean(json, 'driver_is_active'),
        assignedAt: DateTime.parse(JsonReader.string(json, 'assigned_at')),
      );

  final String driverId;
  final String? driverName;
  final String? driverLoginId;
  final String? driverPhone;
  final bool driverIsActive;
  final DateTime assignedAt;

  String get label => driverName ?? driverLoginId ?? 'Driver';
}

/// One entry in a booking's assignment history.
class AssignmentHistoryItem {
  const AssignmentHistoryItem({
    required this.id,
    required this.driverId,
    required this.assignedAt,
    required this.isActive,
    this.driverName,
    this.driverLoginId,
    this.assignedByName,
    this.unassignedAt,
  });

  factory AssignmentHistoryItem.fromJson(Map<String, dynamic> json) =>
      AssignmentHistoryItem(
        id: JsonReader.string(json, 'id'),
        driverId: JsonReader.string(json, 'driver_id'),
        driverName: JsonReader.optionalString(json, 'driver_name'),
        driverLoginId: JsonReader.optionalString(json, 'driver_login_id'),
        assignedByName: JsonReader.optionalString(json, 'assigned_by_name'),
        assignedAt: DateTime.parse(JsonReader.string(json, 'assigned_at')),
        unassignedAt: json['unassigned_at'] == null
            ? null
            : DateTime.parse(JsonReader.string(json, 'unassigned_at')),
        isActive: JsonReader.boolean(json, 'is_active'),
      );

  final String id;
  final String driverId;
  final String? driverName;
  final String? driverLoginId;
  final String? assignedByName;
  final DateTime assignedAt;
  final DateTime? unassignedAt;
  final bool isActive;

  String get label => driverName ?? driverLoginId ?? 'Driver';
}

/// A driver account as an admin sees it.
class DriverAccount {
  const DriverAccount({
    required this.id,
    required this.loginId,
    required this.isActive,
    required this.openBookings,
    required this.createdAt,
    this.fullName,
    this.phone,
  });

  factory DriverAccount.fromJson(Map<String, dynamic> json) => DriverAccount(
        id: JsonReader.string(json, 'id'),
        loginId: JsonReader.string(json, 'driver_login_id'),
        fullName: JsonReader.optionalString(json, 'full_name'),
        phone: JsonReader.optionalString(json, 'phone'),
        isActive: JsonReader.boolean(json, 'is_active'),
        openBookings: json['open_bookings'] == null
            ? 0
            : JsonReader.integer(json, 'open_bookings'),
        createdAt: DateTime.parse(JsonReader.string(json, 'created_at')),
      );

  final String id;
  final String loginId;
  final String? fullName;
  final String? phone;
  final bool isActive;

  /// Bookings this driver still has to do.
  final int openBookings;
  final DateTime createdAt;

  String get label => fullName ?? loginId;
}
