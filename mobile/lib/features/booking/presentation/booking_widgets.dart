import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/enums.dart';

String bookingStatusLabel(BookingStatus status) {
  switch (status) {
    case BookingStatus.pendingPayment:
      return 'Awaiting payment';
    case BookingStatus.confirmed:
      return 'Confirmed';
    case BookingStatus.assigned:
      return 'Driver assigned';
    case BookingStatus.onTheWay:
      return 'On the way';
    case BookingStatus.inProgress:
      return 'In progress';
    case BookingStatus.completed:
      return 'Completed';
    case BookingStatus.cancelled:
      return 'Cancelled';
  }
}

class BookingStatusChip extends StatelessWidget {
  const BookingStatusChip({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color foreground;
    switch (status) {
      case BookingStatus.cancelled:
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
      case BookingStatus.completed:
      case BookingStatus.confirmed:
        background = scheme.primaryContainer;
        foreground = scheme.onPrimaryContainer;
      default:
        background = scheme.secondaryContainer;
        foreground = scheme.onSecondaryContainer;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The icon means the status is not conveyed by colour alone.
          Icon(_statusIcon(status), size: 16, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              bookingStatusLabel(status),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _statusIcon(BookingStatus status) {
  switch (status) {
    case BookingStatus.pendingPayment:
      return Icons.hourglass_empty;
    case BookingStatus.confirmed:
      return Icons.check_circle_outline;
    case BookingStatus.assigned:
      return Icons.person_outline;
    case BookingStatus.onTheWay:
      return Icons.two_wheeler;
    case BookingStatus.inProgress:
      return Icons.build_outlined;
    case BookingStatus.completed:
      return Icons.verified_outlined;
    case BookingStatus.cancelled:
      return Icons.cancel_outlined;
  }
}

/// One "label ........ value" row for summaries.
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context)
            .textTheme
            .titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// A titled block used by the summary and details screens.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// "12 MG Road, Near the temple, Bhopal 462001"
String addressText(Booking booking) {
  final landmark = booking.landmark;
  return [
    booking.addressLine,
    if (landmark != null && landmark.isNotEmpty) landmark,
    '${booking.city} ${booking.pincode}',
  ].join(', ');
}

/// The inclusions as a bullet list.
class InclusionList extends StatelessWidget {
  const InclusionList({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(Icons.check, size: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          ),
      ],
    );
  }
}

/// How an unfixed charge is described.
String chargeAmountText(double? amount) =>
    amount == null ? 'At actuals' : formatMoney(amount);

/// Shown when a booking screen is opened without choosing a package first
/// (for example from a stale link).
class NothingSelectedView extends StatelessWidget {
  const NothingSelectedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Book a service')),
      body: EmptyView(
        message: 'Choose a service and package to book first.',
        action: FilledButton(
          onPressed: () => context.go(AppRoutes.browseServices),
          child: const Text('Browse services'),
        ),
      ),
    );
  }
}

/// A short, human line about where the booking stands, for the history list:
/// "Waiting for payment", "Ravi Kumar is on the way", "Completed 21 Oct 2026".
String bookingProgressLine(Booking booking) {
  final driver = booking.driver?.name;
  switch (booking.status) {
    case BookingStatus.pendingPayment:
      return booking.payment?.status == PaymentStatus.failed
          ? 'Payment failed - tap to try again'
          : 'Waiting for payment';
    case BookingStatus.confirmed:
      return 'Paid - waiting for a driver';
    case BookingStatus.assigned:
      return driver == null ? 'Driver assigned' : 'Driver: $driver';
    case BookingStatus.onTheWay:
      return driver == null ? 'Driver on the way' : '$driver is on the way';
    case BookingStatus.inProgress:
      return 'Service in progress';
    case BookingStatus.completed:
      final at = booking.completedAt;
      return at == null ? 'Completed' : 'Completed ${formatDate(at.toLocal())}';
    case BookingStatus.cancelled:
      final at = booking.cancelledAt;
      return at == null ? 'Cancelled' : 'Cancelled ${formatDate(at.toLocal())}';
  }
}
