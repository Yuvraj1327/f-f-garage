import 'enums.dart';
import 'json_reader.dart';

/// The admin dashboard's figures from `GET /admin/dashboard`.
class AdminDashboard {
  const AdminDashboard({
    required this.total,
    required this.byStatus,
    required this.revenueCollected,
    required this.revenueRefunded,
    required this.revenueNet,
    required this.activeDrivers,
  });

  /// Throws [FormatException] when a field is missing or has the wrong type.
  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    final raw = json['by_status'];
    if (raw is! Map) throw const FormatException('by_status must be an object');
    final counts = <BookingStatus, int>{
      for (final status in BookingStatus.values) status: 0,
    };
    for (final entry in raw.entries) {
      final count = entry.value;
      if (count is! int) throw const FormatException('status count must be a number');
      // A status this app version does not know is still part of the total.
      for (final status in BookingStatus.values) {
        if (status.apiValue == entry.key) counts[status] = count;
      }
    }
    return AdminDashboard(
      total: JsonReader.integer(json, 'bookings_total'),
      byStatus: counts,
      revenueCollected: JsonReader.money(json, 'revenue_collected'),
      revenueRefunded: JsonReader.money(json, 'revenue_refunded'),
      revenueNet: JsonReader.money(json, 'revenue_net'),
      activeDrivers: JsonReader.integer(json, 'active_drivers'),
    );
  }

  final int total;
  final Map<BookingStatus, int> byStatus;
  final double revenueCollected;
  final double revenueRefunded;
  final double revenueNet;
  final int activeDrivers;

  int count(BookingStatus status) => byStatus[status] ?? 0;

  int get completed => count(BookingStatus.completed);
  int get cancelled => count(BookingStatus.cancelled);

  /// Waiting for payment or for a driver.
  int get pending =>
      count(BookingStatus.pendingPayment) + count(BookingStatus.confirmed);

  /// A driver is assigned, on the way or working.
  int get active =>
      count(BookingStatus.assigned) +
      count(BookingStatus.onTheWay) +
      count(BookingStatus.inProgress);
}
