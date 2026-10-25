import 'availability.dart' show ClockTime;
import 'driver.dart';
import 'enums.dart';
import 'json_reader.dart';
import 'payment.dart';

/// An extra charge as it was shown when the booking was made.
class BookingCharge {
  const BookingCharge({
    required this.id,
    required this.chargeType,
    required this.name,
    required this.includedInTotal,
    this.amount,
  });

  factory BookingCharge.fromJson(Map<String, dynamic> json) => BookingCharge(
        id: JsonReader.string(json, 'id'),
        chargeType: ExtraChargeType.fromApiValue(
          JsonReader.string(json, 'charge_type'),
        ),
        name: JsonReader.string(json, 'name'),
        amount: JsonReader.optionalMoney(json, 'amount'),
        includedInTotal: JsonReader.boolean(json, 'included_in_total'),
      );

  final String id;
  final ExtraChargeType chargeType;
  final String name;

  /// Null = charged at actuals on the day.
  final double? amount;

  /// True when the customer chose it and it is part of the total.
  final bool includedInTotal;
}

/// The booking entered [status] at [at] (one step of its history).
class TimelineEvent {
  const TimelineEvent({required this.status, required this.at});

  factory TimelineEvent.fromJson(Map<String, dynamic> json) => TimelineEvent(
        status: BookingStatus.fromApiValue(JsonReader.string(json, 'status')),
        at: DateTime.parse(JsonReader.string(json, 'at')),
      );

  final BookingStatus status;
  final DateTime at;
}

/// A booking as the customer sees it.
class Booking {
  const Booking({
    required this.id,
    required this.number,
    required this.code,
    required this.status,
    required this.vehicleType,
    required this.serviceId,
    required this.packageId,
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
    required this.packagePrice,
    required this.extraChargesTotal,
    required this.totalAmount,
    required this.charges,
    required this.createdAt,
    required this.canCancel,
    required this.canModify,
    this.payment,
    this.isPaid = false,
    this.canPay = false,
    this.driver,
    this.assignment,
    this.canAssign = false,
    this.canUnassign = false,
    this.timeline = const [],
    this.confirmedAt,
    this.completedAt,
    this.cancelledAt,
    this.durationMinutes,
    this.landmark,
    this.latitude,
    this.longitude,
    this.state,
    this.notes,
    this.cancellationReason,
    this.cancelBlockedReason,
  });

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: JsonReader.string(json, 'id'),
        number: JsonReader.integer(json, 'booking_number'),
        code: JsonReader.string(json, 'booking_code'),
        status: BookingStatus.fromApiValue(JsonReader.string(json, 'status')),
        vehicleType: VehicleType.fromApiValue(
          JsonReader.string(json, 'vehicle_type'),
        ),
        serviceId: JsonReader.string(json, 'service_id'),
        packageId: JsonReader.string(json, 'package_id'),
        serviceName: JsonReader.string(json, 'service_name'),
        packageName: JsonReader.string(json, 'package_name'),
        inclusions: JsonReader.stringList(json, 'package_inclusions'),
        durationMinutes:
            JsonReader.optionalInteger(json, 'estimated_duration_minutes'),
        customerName: JsonReader.string(json, 'customer_name'),
        customerPhone: JsonReader.string(json, 'customer_phone'),
        addressLine: JsonReader.string(json, 'address_line'),
        landmark: JsonReader.optionalString(json, 'landmark'),
        latitude: JsonReader.optionalDouble(json, 'latitude'),
        longitude: JsonReader.optionalDouble(json, 'longitude'),
        city: JsonReader.string(json, 'city'),
        state: JsonReader.optionalString(json, 'state'),
        pincode: JsonReader.string(json, 'pincode'),
        date: JsonReader.date(json, 'scheduled_date'),
        slotStart: ClockTime.parse(JsonReader.string(json, 'slot_start')),
        slotEnd: ClockTime.parse(JsonReader.string(json, 'slot_end')),
        packagePrice: JsonReader.money(json, 'package_price'),
        extraChargesTotal: JsonReader.money(json, 'extra_charges_total'),
        totalAmount: JsonReader.money(json, 'total_amount'),
        charges: JsonReader.objectList(
          json,
          'extra_charges',
          BookingCharge.fromJson,
        ),
        notes: JsonReader.optionalString(json, 'customer_notes'),
        cancellationReason:
            JsonReader.optionalString(json, 'cancellation_reason'),
        createdAt: DateTime.parse(JsonReader.string(json, 'created_at')),
        confirmedAt: _optionalDateTime(json, 'confirmed_at'),
        completedAt: _optionalDateTime(json, 'completed_at'),
        cancelledAt: _optionalDateTime(json, 'cancelled_at'),
        canCancel: JsonReader.boolean(json, 'can_cancel'),
        canModify: JsonReader.boolean(json, 'can_modify'),
        cancelBlockedReason:
            JsonReader.optionalString(json, 'cancel_blocked_reason'),
        payment: json['payment'] == null
            ? null
            : Payment.fromJson(_paymentJson(json['payment'])),
        isPaid: json['is_paid'] == null
            ? false
            : JsonReader.boolean(json, 'is_paid'),
        canPay: json['can_pay'] == null
            ? false
            : JsonReader.boolean(json, 'can_pay'),
        driver: json['driver'] == null
            ? null
            : DriverSummary.fromJson(_object(json, 'driver')),
        assignment: json['assignment'] == null
            ? null
            : AdminAssignment.fromJson(_object(json, 'assignment')),
        canAssign: json['can_assign'] == null
            ? false
            : JsonReader.boolean(json, 'can_assign'),
        canUnassign: json['can_unassign'] == null
            ? false
            : JsonReader.boolean(json, 'can_unassign'),
        timeline: json['timeline'] == null
            ? const []
            : JsonReader.objectList(json, 'timeline', TimelineEvent.fromJson),
      );

  final String id;
  final int number;

  /// The reference the customer quotes, e.g. FF-000123.
  final String code;
  final BookingStatus status;
  final VehicleType vehicleType;
  final String serviceId;
  final String packageId;
  final String serviceName;
  final String packageName;
  final List<String> inclusions;
  final int? durationMinutes;
  final String customerName;
  final String customerPhone;
  final String addressLine;
  final String? landmark;

  /// Where on the map the customer put the pin; null when they only typed an
  /// address. Always both or neither.
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;
  final String city;
  final String? state;
  final String pincode;
  final DateTime date;
  final ClockTime slotStart;
  final ClockTime slotEnd;
  final double packagePrice;
  final double extraChargesTotal;
  final double totalAmount;
  final List<BookingCharge> charges;
  final String? notes;
  final String? cancellationReason;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  /// What the customer may do right now; decided by the server.
  final bool canCancel;
  final bool canModify;
  final String? cancelBlockedReason;

  /// The successful payment if there is one, otherwise the latest attempt.
  final Payment? payment;

  /// True only after the server has verified a payment.
  final bool isPaid;

  /// The server says a payment can be started now.
  final bool canPay;

  /// The driver, once one is assigned (customer view; null when cancelled).
  final DriverSummary? driver;

  /// Admin view only: who holds the booking, and whether a driver can be set
  /// or removed right now.
  final AdminAssignment? assignment;
  final bool canAssign;
  final bool canUnassign;

  /// Every status the booking has been in, oldest first. Empty in list views.
  final List<TimelineEvent> timeline;

  String get timeLabel => '${slotStart.format()} - ${slotEnd.format()}';

  bool get isCancelled => status == BookingStatus.cancelled;

  /// Charges the customer chose (part of the total).
  List<BookingCharge> get chosenCharges =>
      charges.where((c) => c.includedInTotal).toList();

  /// Charges shown for information only.
  List<BookingCharge> get possibleCharges =>
      charges.where((c) => !c.includedInTotal).toList();
}

Map<String, dynamic> _paymentJson(Object? value) => _asObject('payment', value);

Map<String, dynamic> _object(Map<String, dynamic> json, String key) =>
    _asObject(key, json[key]);

Map<String, dynamic> _asObject(String key, Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Expected "$key" to be an object, got $value');
}

class BookingPage {
  const BookingPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory BookingPage.fromJson(Map<String, dynamic> json) => BookingPage(
        items: JsonReader.objectList(json, 'items', Booking.fromJson),
        total: JsonReader.integer(json, 'total'),
        limit: JsonReader.integer(json, 'limit'),
        offset: JsonReader.integer(json, 'offset'),
      );

  final List<Booking> items;
  final int total;
  final int limit;
  final int offset;

  bool get hasMore => offset + items.length < total;
}

class QuoteCharge {
  const QuoteCharge({
    required this.id,
    required this.chargeType,
    required this.name,
    required this.selectable,
    this.amount,
  });

  factory QuoteCharge.fromJson(Map<String, dynamic> json) => QuoteCharge(
        id: JsonReader.string(json, 'extra_charge_id'),
        chargeType: ExtraChargeType.fromApiValue(
          JsonReader.string(json, 'charge_type'),
        ),
        name: JsonReader.string(json, 'name'),
        amount: JsonReader.optionalMoney(json, 'amount'),
        selectable: JsonReader.boolean(json, 'selectable'),
      );

  final String id;
  final ExtraChargeType chargeType;
  final String name;
  final double? amount;

  /// Only charges with a fixed amount can be added up front.
  final bool selectable;
}

/// The server's price summary for a package.
class BookingQuote {
  const BookingQuote({
    required this.serviceId,
    required this.serviceName,
    required this.vehicleType,
    required this.packageId,
    required this.packageName,
    required this.inclusions,
    required this.packagePrice,
    required this.charges,
    this.durationMinutes,
  });

  factory BookingQuote.fromJson(Map<String, dynamic> json) => BookingQuote(
        serviceId: JsonReader.string(json, 'service_id'),
        serviceName: JsonReader.string(json, 'service_name'),
        vehicleType: VehicleType.fromApiValue(
          JsonReader.string(json, 'vehicle_type'),
        ),
        packageId: JsonReader.string(json, 'package_id'),
        packageName: JsonReader.string(json, 'package_name'),
        inclusions: JsonReader.stringList(json, 'inclusions'),
        durationMinutes:
            JsonReader.optionalInteger(json, 'estimated_duration_minutes'),
        packagePrice: JsonReader.money(json, 'package_price'),
        charges: JsonReader.objectList(
          json,
          'extra_charges',
          QuoteCharge.fromJson,
        ),
      );

  final String serviceId;
  final String serviceName;
  final VehicleType vehicleType;
  final String packageId;
  final String packageName;
  final List<String> inclusions;
  final int? durationMinutes;
  final double packagePrice;
  final List<QuoteCharge> charges;

  /// Total for the chosen add-ons, in whole paise to avoid floating-point drift.
  double totalFor(Set<String> chosenIds) {
    var paise = (packagePrice * 100).round();
    for (final charge in charges) {
      final amount = charge.amount;
      if (chosenIds.contains(charge.id) && charge.selectable && amount != null) {
        paise += (amount * 100).round();
      }
    }
    return paise / 100;
  }

  double extrasFor(Set<String> chosenIds) =>
      totalFor(chosenIds) - packagePrice;
}

/// Everything the server needs to create a booking. Note what is NOT here: no
/// price. [expectedTotal] is the total the customer was shown; the server only
/// compares it with its own figure and refuses if the price has changed.
class NewBooking {
  const NewBooking({
    required this.packageId,
    required this.pincode,
    required this.addressLine,
    required this.date,
    required this.timeSlotId,
    required this.expectedTotal,
    required this.clientRequestId,
    this.extraChargeIds = const [],
    this.landmark,
    this.latitude,
    this.longitude,
    this.notes,
  });

  final String packageId;
  final List<String> extraChargeIds;
  final String pincode;
  final String addressLine;
  final String? landmark;

  /// The map pin, when the customer chose one (both or neither).
  final double? latitude;
  final double? longitude;
  final DateTime date;
  final String timeSlotId;
  final String? notes;
  final double expectedTotal;
  final String clientRequestId;
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final text = JsonReader.optionalString(json, key);
  return text == null ? null : DateTime.parse(text);
}
