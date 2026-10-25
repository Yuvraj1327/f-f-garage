import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/enums.dart';

/// Where one step of the progress timeline stands.
enum StepState { done, active, upcoming, cancelled }

class TimelineStep {
  const TimelineStep({
    required this.label,
    required this.state,
    this.at,
    this.hint,
  });

  final String label;
  final StepState state;

  /// When the booking reached this step (done, active and cancelled steps).
  final DateTime? at;

  /// One line of context for the step that is happening or about to happen.
  final String? hint;
}

/// The steps a booking normally goes through, in order.
const List<BookingStatus> bookingFlow = [
  BookingStatus.pendingPayment,
  BookingStatus.confirmed,
  BookingStatus.assigned,
  BookingStatus.onTheWay,
  BookingStatus.inProgress,
  BookingStatus.completed,
];

String timelineLabel(BookingStatus status) {
  switch (status) {
    case BookingStatus.pendingPayment:
      return 'Booking placed';
    case BookingStatus.confirmed:
      return 'Booking confirmed';
    case BookingStatus.assigned:
      return 'Driver assigned';
    case BookingStatus.onTheWay:
      return 'Driver on the way';
    case BookingStatus.inProgress:
      return 'Service in progress';
    case BookingStatus.completed:
      return 'Service completed';
    case BookingStatus.cancelled:
      return 'Booking cancelled';
  }
}

/// Builds the customer's progress timeline from what the server reported.
///
/// - A booking that is still going shows every step: those it has passed are
///   done, the one it is in is active (while a driver is on it), the rest are
///   upcoming. The server's history supplies the times.
/// - A cancelled booking shows only the steps it reached, then "Booking
///   cancelled"; later steps are never shown as if they could still happen.
/// - A driver who was removed puts the booking back to "confirmed", so the
///   driver step goes back to upcoming rather than staying ticked.
List<TimelineStep> buildTimeline(Booking booking) {
  DateTime? timeOf(BookingStatus status) {
    for (final event in booking.timeline.reversed) {
      if (event.status == status) return event.at;
    }
    switch (status) {
      case BookingStatus.pendingPayment:
        return booking.createdAt;
      case BookingStatus.confirmed:
        return booking.confirmedAt;
      case BookingStatus.completed:
        return booking.completedAt;
      case BookingStatus.cancelled:
        return booking.cancelledAt;
      default:
        return null;
    }
  }

  if (booking.status == BookingStatus.cancelled) {
    var reached = booking.confirmedAt != null ? 1 : 0;
    for (final event in booking.timeline.reversed) {
      final index = bookingFlow.indexOf(event.status);
      if (index >= 0) {
        reached = index;
        break;
      }
    }
    return [
      for (var i = 0; i <= reached; i++)
        TimelineStep(
          label: timelineLabel(bookingFlow[i]),
          state: StepState.done,
          at: timeOf(bookingFlow[i]),
        ),
      TimelineStep(
        label: timelineLabel(BookingStatus.cancelled),
        state: StepState.cancelled,
        at: timeOf(BookingStatus.cancelled),
      ),
    ];
  }

  final current = bookingFlow.indexOf(booking.status);
  final inFlight = booking.status == BookingStatus.assigned ||
      booking.status == BookingStatus.onTheWay ||
      booking.status == BookingStatus.inProgress;
  final paymentFailed = booking.payment != null &&
      booking.payment!.status == PaymentStatus.failed;

  String? hintFor(int index) {
    final status = bookingFlow[index];
    if (index == current && inFlight) {
      final name = booking.driver?.name;
      switch (status) {
        case BookingStatus.assigned:
          return name == null ? null : '$name will do your service';
        case BookingStatus.onTheWay:
          return 'Your driver is on the way';
        case BookingStatus.inProgress:
          return 'Work is under way';
        default:
          return null;
      }
    }
    if (index == current + 1) {
      if (booking.status == BookingStatus.pendingPayment) {
        return paymentFailed
            ? 'Your last payment failed. You can try again.'
            : 'Waiting for payment';
      }
      if (booking.status == BookingStatus.confirmed) {
        return 'We will assign a driver soon';
      }
    }
    return null;
  }

  return [
    for (var i = 0; i < bookingFlow.length; i++)
      TimelineStep(
        label: timelineLabel(bookingFlow[i]),
        state: i < current
            ? StepState.done
            : i == current
                ? (inFlight ? StepState.active : StepState.done)
                : StepState.upcoming,
        at: i <= current ? timeOf(bookingFlow[i]) : null,
        hint: hintFor(i),
      ),
  ];
}

/// The progress timeline as a vertical list of steps.
class BookingTimeline extends StatelessWidget {
  const BookingTimeline({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final steps = buildTimeline(booking);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(
            key: ValueKey('timeline-step-$i'),
            step: steps[i],
            isLast: i == steps.length - 1,
          ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({super.key, required this.step, required this.isLast});

  final TimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final IconData icon;
    final Color color;
    switch (step.state) {
      case StepState.done:
        icon = Icons.check_circle;
        color = scheme.secondary;
      case StepState.active:
        icon = Icons.radio_button_checked;
        color = scheme.primary;
      case StepState.upcoming:
        icon = Icons.radio_button_unchecked;
        color = scheme.outline;
      case StepState.cancelled:
        icon = Icons.cancel;
        color = scheme.error;
    }
    final muted = step.state == StepState.upcoming;
    return Semantics(
      label: '${step.label}, ${_stateWord(step.state)}'
          '${step.at == null ? '' : ', ${formatDateTime(step.at!)}'}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Icon(icon, size: 22, color: color),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: muted ? scheme.outlineVariant : color,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: textTheme.titleSmall?.copyWith(
                        color: muted ? scheme.outline : null,
                        fontWeight: step.state == StepState.active
                            ? FontWeight.w700
                            : null,
                      ),
                    ),
                    if (step.at != null)
                      Text(formatDateTime(step.at!), style: textTheme.bodySmall),
                    if (step.hint != null)
                      Text(step.hint!, style: textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _stateWord(StepState state) {
  switch (state) {
    case StepState.done:
      return 'done';
    case StepState.active:
      return 'in progress';
    case StepState.upcoming:
      return 'not yet';
    case StepState.cancelled:
      return 'cancelled';
  }
}
