import '../../data/models/enums.dart';

/// "₹499" or "₹499.50" (whole rupees drop the decimals).
String formatMoney(double amount) {
  final whole = amount == amount.roundToDouble();
  final text = whole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  return '₹$text';
}

String vehicleLabel(VehicleType type) {
  switch (type) {
    case VehicleType.bike:
      return 'Bike';
    case VehicleType.scooter:
      return 'Scooter';
  }
}

String chargeTypeLabel(ExtraChargeType type) {
  switch (type) {
    case ExtraChargeType.sparePart:
      return 'Spare part';
    case ExtraChargeType.engineOil:
      return 'Engine oil';
    case ExtraChargeType.other:
      return 'Other';
  }
}

String formatDuration(int minutes) {
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours hr' : '$hours hr $rest min';
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Tue, 20 Oct 2026".
String formatDate(DateTime date) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]} '
      '${date.year}';
}

/// "20 Oct 2026, 4:05 PM" in the phone's own time zone.
String formatDateTime(DateTime value) {
  final local = value.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '${local.day} ${_months[local.month - 1]} ${local.year}, '
      '$hour12:$minute $period';
}
