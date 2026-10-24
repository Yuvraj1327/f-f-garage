import 'json_reader.dart';

/// A time of day without a date or time zone ("09:30").
class ClockTime implements Comparable<ClockTime> {
  const ClockTime(this.hour, this.minute);

  /// Parses "HH:mm" or "HH:mm:ss". Throws [FormatException] otherwise.
  factory ClockTime.parse(String text) {
    final match = RegExp(r'^(\d{2}):(\d{2})(?::\d{2})?$').firstMatch(text);
    if (match == null) {
      throw FormatException('Expected a time like 09:30, got $text');
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      throw FormatException('Not a valid time: $text');
    }
    return ClockTime(hour, minute);
  }

  final int hour;
  final int minute;

  int get totalMinutes => hour * 60 + minute;

  /// What the API expects: "09:30".
  String toApi() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// For people: "9:30 AM".
  String format() {
    final period = hour < 12 ? 'AM' : 'PM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} $period';
  }

  @override
  int compareTo(ClockTime other) => totalMinutes.compareTo(other.totalMinutes);

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.totalMinutes == totalMinutes;

  @override
  int get hashCode => totalMinutes;

  @override
  String toString() => toApi();
}

const List<String> weekdayShortNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// "Every day", "Mon - Fri" or "Mon, Wed, Sat" for ISO weekday numbers (1-7).
String describeWeekdays(List<int> days) {
  final sorted = (days.toSet().toList()..sort());
  if (sorted.length == 7) {
    return 'Every day';
  }
  final consecutive = sorted.length > 2 &&
      sorted.last - sorted.first == sorted.length - 1;
  if (consecutive) {
    return '${weekdayShortNames[sorted.first - 1]} - '
        '${weekdayShortNames[sorted.last - 1]}';
  }
  return sorted.map((d) => weekdayShortNames[d - 1]).join(', ');
}

class TimeSlot {
  const TimeSlot({
    required this.id,
    required this.start,
    required this.end,
    required this.capacity,
    required this.daysOfWeek,
    required this.isActive,
  });

  factory TimeSlot.fromJson(Map<String, dynamic> json) => TimeSlot(
        id: JsonReader.string(json, 'id'),
        start: ClockTime.parse(JsonReader.string(json, 'start_time')),
        end: ClockTime.parse(JsonReader.string(json, 'end_time')),
        capacity: JsonReader.integer(json, 'capacity'),
        daysOfWeek: JsonReader.intList(json, 'days_of_week'),
        isActive: JsonReader.boolean(json, 'is_active'),
      );

  final String id;
  final ClockTime start;
  final ClockTime end;
  final int capacity;

  /// ISO weekdays: 1 = Monday ... 7 = Sunday.
  final List<int> daysOfWeek;
  final bool isActive;

  String get label => '${start.format()} - ${end.format()}';
}

/// A date-specific change to the weekly routine.
class AvailabilityException {
  const AvailabilityException({
    required this.id,
    required this.date,
    required this.isOpen,
    this.timeSlotId,
    this.capacity,
    this.reason,
  });

  factory AvailabilityException.fromJson(Map<String, dynamic> json) =>
      AvailabilityException(
        id: JsonReader.string(json, 'id'),
        date: JsonReader.date(json, 'exception_date'),
        timeSlotId: JsonReader.optionalString(json, 'time_slot_id'),
        isOpen: JsonReader.boolean(json, 'is_open'),
        capacity: JsonReader.optionalInteger(json, 'capacity'),
        reason: JsonReader.optionalString(json, 'reason'),
      );

  final String id;
  final DateTime date;

  /// Null = the whole day.
  final String? timeSlotId;
  final bool isOpen;
  final int? capacity;
  final String? reason;

  bool get isWholeDay => timeSlotId == null;
}

class SlotAvailability {
  const SlotAvailability({
    required this.slotId,
    required this.start,
    required this.end,
    required this.available,
    required this.spotsLeft,
    this.reason,
  });

  factory SlotAvailability.fromJson(Map<String, dynamic> json) =>
      SlotAvailability(
        slotId: JsonReader.string(json, 'slot_id'),
        start: ClockTime.parse(JsonReader.string(json, 'start_time')),
        end: ClockTime.parse(JsonReader.string(json, 'end_time')),
        available: JsonReader.boolean(json, 'available'),
        reason: JsonReader.optionalString(json, 'reason'),
        spotsLeft: JsonReader.integer(json, 'spots_left'),
      );

  final String slotId;
  final ClockTime start;
  final ClockTime end;
  final bool available;
  final String? reason;
  final int spotsLeft;
}

class DayAvailability {
  const DayAvailability({
    required this.date,
    required this.isOpen,
    required this.slots,
    this.closedReason,
    this.note,
  });

  factory DayAvailability.fromJson(Map<String, dynamic> json) =>
      DayAvailability(
        date: JsonReader.date(json, 'date'),
        isOpen: JsonReader.boolean(json, 'is_open'),
        closedReason: JsonReader.optionalString(json, 'closed_reason'),
        note: JsonReader.optionalString(json, 'note'),
        slots: JsonReader.objectList(json, 'slots', SlotAvailability.fromJson),
      );

  final DateTime date;
  final bool isOpen;
  final String? closedReason;
  final String? note;
  final List<SlotAvailability> slots;
}
