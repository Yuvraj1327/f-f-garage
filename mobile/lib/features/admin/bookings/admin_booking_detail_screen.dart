import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/driver.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../booking/presentation/booking_widgets.dart';
import '../../payment/presentation/payment_widgets.dart';
import '../providers/admin_providers.dart';

/// One booking for an admin: details, payment, who is assigned, and the
/// buttons to assign, change or remove the driver (offered only when the
/// server says it is allowed).
class AdminBookingDetailScreen extends ConsumerStatefulWidget {
  const AdminBookingDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<AdminBookingDetailScreen> createState() =>
      _AdminBookingDetailScreenState();
}

class _AdminBookingDetailScreenState
    extends ConsumerState<AdminBookingDetailScreen> {
  bool _busy = false;

  Future<void> _assign(Booking booking) async {
    final driver = await showModalBottomSheet<DriverAccount>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _DriverPicker(
        currentDriverId: booking.assignment?.driverId,
      ),
    );
    if (driver == null || !mounted) return;
    await _run(
      () => ref
          .read(adminBookingRepositoryProvider)
          .assign(booking.id, driver.id),
      booking.assignment == null
          ? '${driver.label} assigned'
          : 'Driver changed to ${driver.label}',
    );
  }

  Future<void> _unassign(Booking booking) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove driver?',
      message: 'The booking goes back to "Needs driver" and the customer '
          'will no longer see a driver.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(adminBookingRepositoryProvider).unassign(booking.id),
      'Driver removed',
    );
  }

  Future<void> _run(Future<Booking> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showSnack(context, success);
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } finally {
      // Whatever happened, show what the server has now.
      if (mounted) {
        refreshAdminBooking(ref, widget.bookingId);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminBookingProvider(widget.bookingId));
    return Scaffold(
      appBar: AppBar(title: Text(value.valueOrNull?.code ?? 'Booking')),
      body: SafeArea(
        child: AsyncView<Booking>(
          value: value,
          onRetry: () => ref.invalidate(adminBookingProvider(widget.bookingId)),
          builder: (booking) => RefreshIndicator(
            onRefresh: () async {
              refreshAdminBooking(ref, widget.bookingId);
              await ref.read(adminBookingProvider(widget.bookingId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Summary(booking: booking),
                _AssignmentCard(
                  booking: booking,
                  busy: _busy,
                  onAssign: () => _assign(booking),
                  onUnassign: () => _unassign(booking),
                ),
                _History(bookingId: booking.id),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Booking',
      children: [
        Row(
          children: [
            Expanded(child: Text('${booking.code} - ${booking.serviceName}')),
            BookingStatusChip(status: booking.status),
          ],
        ),
        SummaryRow(label: 'Package', value: booking.packageName),
        SummaryRow(
          label: 'When',
          value: '${formatDate(booking.date)}, ${booking.timeLabel}',
        ),
        SummaryRow(label: 'Customer', value: booking.customerName),
        SummaryRow(label: 'Mobile', value: booking.customerPhone),
        SummaryRow(
          label: 'Address',
          value: [
            booking.addressLine,
            if (booking.landmark != null) booking.landmark!,
            '${booking.city} ${booking.pincode}',
          ].join(', '),
        ),
        SummaryRow(label: 'Total', value: formatMoney(booking.totalAmount)),
        SummaryRow(
          label: 'Payment',
          value: booking.payment == null
              ? 'Not paid yet'
              : paymentSummaryLine(booking.payment!),
        ),
        if (booking.notes != null)
          SummaryRow(label: 'Notes', value: booking.notes!),
        if (booking.cancellationReason != null)
          SummaryRow(label: 'Cancelled', value: booking.cancellationReason!),
      ],
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.booking,
    required this.busy,
    required this.onAssign,
    required this.onUnassign,
  });

  final Booking booking;
  final bool busy;
  final VoidCallback onAssign;
  final VoidCallback onUnassign;

  @override
  Widget build(BuildContext context) {
    final assignment = booking.assignment;
    return SectionCard(
      title: 'Driver',
      children: [
        if (assignment == null)
          Text(
            booking.isCancelled
                ? 'This booking was cancelled and has no driver.'
                : 'No driver assigned yet.',
            key: const ValueKey('no-driver'),
          )
        else ...[
          SummaryRow(label: 'Name', value: assignment.label),
          if (assignment.driverLoginId != null)
            SummaryRow(label: 'Driver ID', value: assignment.driverLoginId!),
          if (assignment.driverPhone != null)
            SummaryRow(label: 'Mobile', value: assignment.driverPhone!),
          SummaryRow(
            label: 'Assigned',
            value: formatDateTime(assignment.assignedAt),
          ),
          if (!assignment.driverIsActive && !booking.isCancelled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: MessageBanner(
                message: 'This driver is switched off and cannot see the '
                    'booking. Assign another driver.',
              ),
            ),
        ],
        if (booking.status == BookingStatus.pendingPayment)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'A driver can be assigned once the booking is paid.',
              key: ValueKey('needs-payment'),
            ),
          ),
        if (booking.canAssign || booking.canUnassign)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (booking.canAssign)
                  FilledButton.icon(
                    key: const ValueKey('assign-driver'),
                    onPressed: busy ? null : onAssign,
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(
                      assignment == null ? 'Assign driver' : 'Change driver',
                    ),
                  ),
                if (booking.canUnassign)
                  OutlinedButton.icon(
                    key: const ValueKey('unassign-driver'),
                    onPressed: busy ? null : onUnassign,
                    icon: const Icon(Icons.person_remove_outlined),
                    label: const Text('Remove driver'),
                  ),
              ],
            ),
          ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminAssignmentHistoryProvider(bookingId));
    return SectionCard(
      title: 'Assignment history',
      children: [
        value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Column(
            children: [
              Text(errorMessage(error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(adminAssignmentHistoryProvider(bookingId)),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (items) {
            if (items.isEmpty) return const Text('No driver has held this booking.');
            return Column(
              children: [
                for (final item in items)
                  ListTile(
                    key: ValueKey('history-${item.id}'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(item.label),
                    subtitle: Text(
                      '${formatDateTime(item.assignedAt)}'
                      '${item.assignedByName == null ? '' : ' by ${item.assignedByName}'}'
                      '${item.unassignedAt == null ? '' : '\nUntil ${formatDateTime(item.unassignedAt!)}'}',
                    ),
                    trailing: item.isActive ? const Text('Current') : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Active drivers with their open-booking counts; pops with the chosen one.
class _DriverPicker extends ConsumerWidget {
  const _DriverPicker({this.currentDriverId});

  final String? currentDriverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDriversProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Choose a driver'),
            ),
            Flexible(
              child: AsyncView<List<DriverAccount>>(
                value: value,
                onRetry: () => ref.invalidate(adminDriversProvider),
                builder: (drivers) {
                  final active = drivers.where((d) => d.isActive).toList();
                  if (active.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'There are no active drivers. Add or switch on a '
                        'driver first.',
                        key: ValueKey('no-active-drivers'),
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      for (final driver in active)
                        ListTile(
                          key: ValueKey('pick-${driver.id}'),
                          title: Text(driver.label),
                          subtitle: Text(
                            '${driver.loginId} - '
                            '${driver.openBookings} open booking'
                            '${driver.openBookings == 1 ? '' : 's'}',
                          ),
                          trailing: driver.id == currentDriverId
                              ? const Text('Current')
                              : null,
                          onTap: () => Navigator.of(context).pop(driver),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
