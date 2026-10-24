import 'availability.dart' show ClockTime;
import 'booking.dart' show BookingCharge;
import 'enums.dart';
import 'json_reader.dart';

/// A booking as its driver sees it: what to do, where and when. No prices or
/// payments.
class DriverJob {
  const DriverJob({
    required this.id,
    required this.code,
    required this.status,
    required this.vehicleType,
    required this.serviceName,
    required this.packageName,
    required this.inclusions,
    required this.customerName,
    required this.customerPhone,
    required this.addressLine,
    required this.city,
    required this.pincode,
    required this.date,
    required this.slotStart,
    required this.slotEnd,
    required this.charges,
    this.durationMinutes,
    this.landmark,
    this.state,
    this.latitude,
    this.longitude,
    this.notes,
    this.nextStatus,
  });

  factory DriverJob.fromJson(Map<String, dynamic> json) => DriverJob(
        id: JsonReader.string(json, 'id'),
        code: JsonReader.string(json, 'booking_code'),
        status: BookingStatus.fromApiValue(JsonReader.string(json, 'status')),
        vehicleType:
            VehicleType.fromApiValue(JsonReader.string(json, 'vehicle_type')),
        serviceName: JsonReader.string(json, 'service_name'),
        packageName: JsonReader.string(json, 'package_name'),
        inclusions: JsonReader.stringList(json, 'package_inclusions'),
        durationMinutes:
            JsonReader.optionalInteger(json, 'estimated_duration_minutes'),
        customerName: JsonReader.string(json, 'customer_name'),
        customerPhone: JsonReader.string(json, 'customer_phone'),
        addressLine: JsonReader.string(json, 'address_line'),
        landmark: JsonReader.optionalString(json, 'landmark'),
        city: JsonReader.string(json, 'city'),
        state: JsonReader.optionalString(json, 'state'),
        pincode: JsonReader.string(json, 'pincode'),
        latitude: _optionalDouble(json, 'latitude'),
        longitude: _optionalDouble(json, 'longitude'),
        date: JsonReader.date(json, 'scheduled_date'),
        slotStart: ClockTime.parse(JsonReader.string(json, 'slot_start')),
        slotEnd: ClockTime.parse(JsonReader.string(json, 'slot_end')),
        notes: JsonReader.optionalString(json, 'customer_notes'),
        charges: JsonReader.objectList(
          json,
          'extra_charges',
          BookingCharge.fromJson,
        ),
        nextStatus: json['next_status'] == null
            ? null
            : BookingStatus.fromApiValue(
                JsonReader.string(json, 'next_status'),
              ),
      );

  final String id;
  final String code;
  final BookingStatus status;
  final VehicleType vehicleType;
  final String serviceName;
  final String packageName;
  final List<String> inclusions;
  final int? durationMinutes;
  final String customerName;
  final String customerPhone;
  final String addressLine;
  final String? landmark;
  final String city;
  final String? state;
  final String pincode;
  final double? latitude;
  final double? longitude;
  final DateTime date;
  final ClockTime slotStart;
  final ClockTime slotEnd;
  final String? notes;
  final List<BookingCharge> charges;

  /// The one step the driver may take now; null when there is none.
  final BookingStatus? nextStatus;

  String get timeLabel => '${slotStart.format()} - ${slotEnd.format()}';

  bool get isFinished =>
      status == BookingStatus.completed || status == BookingStatus.cancelled;
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('Expected "$key" to be a number or null, got $value');
}

class DriverJobPage {
  const DriverJobPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory DriverJobPage.fromJson(Map<String, dynamic> json) => DriverJobPage(
        items: JsonReader.objectList(json, 'items', DriverJob.fromJson),
        total: JsonReader.integer(json, 'total'),
        limit: JsonReader.integer(json, 'limit'),
        offset: JsonReader.integer(json, 'offset'),
      );

  final List<DriverJob> items;
  final int total;
  final int limit;
  final int offset;
}
