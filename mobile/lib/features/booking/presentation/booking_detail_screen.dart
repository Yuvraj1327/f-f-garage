import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart' show MessageBanner;
import '../../payment/presentation/payment_widgets.dart';
import '../../notifications/providers/notification_providers.dart';
import '../providers/booking_providers.dart';
import 'booking_timeline.dart';
import 'booking_widgets.dart';

/// One booking: status, what was booked, where and when, the price, and the
/// actions the server says are allowed right now (change, cancel).
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.justCreated = false,
  });

  final String bookingId;

  /// True right after the booking was made: shows a confirmation banner.
  final bool justCreated;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(
      ref.read(trackingPollIntervalProvider),
      (_) => _checkForUpdates(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// While a booking is still going, asks the server whether it changed (payment
  /// confirmed, driver assigned, a step taken, cancelled) and reloads the screen
  /// only if it did. A failed check is ignored; the next one tries again.
  Future<void> _checkForUpdates() async {
    final shown = ref.read(bookingProvider(widget.bookingId)).valueOrNull;
    if (shown == null ||
        shown.status == BookingStatus.completed ||
        shown.status == BookingStatus.cancelled) {
      return;
    }
    try {
      final fresh =
          await ref.read(bookingRepositoryProvider).get(widget.bookingId);
      if (!mounted) return;
      if (fresh.status != shown.status ||
          fresh.timeline.length != shown.timeline.length ||
          fresh.driver?.name != shown.driver?.name ||
          fresh.driver?.phone != shown.driver?.phone ||
          fresh.payment?.status != shown.payment?.status ||
          fresh.canPay != shown.canPay ||
          fresh.canCancel != shown.canCancel) {
        ref.invalidate(bookingProvider(widget.bookingId));
      }
    } catch (_) {
      // Try again at the next check.
    }
  }

  Future<void> _cancel(Booking booking) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${booking.code} - ${booking.serviceName}'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep booking'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(bookingRepositoryProvider)
          .cancel(booking.id, reason: text);
      if (!mounted) return;
      refreshBookings(ref, bookingId: booking.id);
      showSuccessSnack(context, 'Booking cancelled');
    } catch (error) {
      if (!mounted) return;
      // Reload so the buttons match what the server now allows.
      refreshBookings(ref, bookingId: booking.id);
      showSnack(context, errorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // A notification arrived or another screen changed this booking: reload.
    ref.listen<int>(
      bookingsRefreshProvider,
      (_, __) => ref.invalidate(bookingProvider(widget.bookingId)),
    );
    final value = ref.watch(bookingProvider(widget.bookingId));
    return Scaffold(
      appBar: AppBar(
        title: Text(value.valueOrNull?.code ?? 'Booking'),
        leading: widget.justCreated
            ? IconButton(
                tooltip: 'Back to home',
                icon: const Icon(Icons.close),
                onPressed: () => context.go(AppRoutes.customerHome),
              )
            : null,
      ),
      body: SafeArea(
        child: AsyncView<Booking>(
          value: value,
          onRetry: () => ref.invalidate(bookingProvider(widget.bookingId)),
          builder: (booking) => RefreshIndicator(
            onRefresh: () =>
                ref.refresh(bookingProvider(widget.bookingId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.justCreated)
                  MessageBanner(
                    isError: false,
                    message: 'Your booking ${booking.code} has been placed. '
                        'Its status is "${bookingStatusLabel(booking.status)}".',
                  ),
                _Body(booking: booking),
                const SizedBox(height: 8),
                if (booking.canPay)
                  FilledButton.icon(
                    key: const ValueKey('pay-now'),
                    onPressed: _busy
                        ? null
                        : () => context.push(AppRoutes.bookingPay(booking.id)),
                    icon: const Icon(Icons.payment),
                    label: Text('Pay ${formatMoney(booking.totalAmount)}'),
                  ),
                if (booking.canModify) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => context.push(AppRoutes.bookingEdit(booking.id)),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Change address or time'),
                  ),
                ],
                if (booking.canCancel) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _cancel(booking),
                    icon: _busy
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel booking'),
                  ),
                ] else if (booking.cancelBlockedReason != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    booking.cancelBlockedReason!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context
                      .push(AppRoutes.supportForBooking(booking.code)),
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Help with this booking'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The driver's number with a one-tap call button (falls back to a message
/// when the device cannot place calls, e.g. a tablet or the web).
class _DriverPhone extends ConsumerWidget {
  const _DriverPhone({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(child: Text(phone, key: const ValueKey('driver-phone'))),
        IconButton(
          tooltip: 'Call driver',
          icon: const Icon(Icons.call_outlined),
          onPressed: () async {
            final opened = await ref.read(contactLauncherProvider).call(phone);
            if (!opened && context.mounted) {
              showSnack(context, "Couldn't place the call. Driver: $phone");
            }
          },
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final duration = booking.durationMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              BookingStatusChip(status: booking.status),
            ],
          ),
        ),
        if (booking.payment != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Payment: ${paymentStateWord(booking.payment!.status)}',
              key: const ValueKey('payment-line'),
            ),
          )
        else if (booking.status == BookingStatus.pendingPayment)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Payment: Not paid yet', key: ValueKey('payment-line')),
          ),
        if (booking.isCancelled && booking.cancellationReason != null)
          SectionCard(
            title: 'Cancelled',
            children: [Text(booking.cancellationReason!)],
          ),
        SectionCard(
          title: 'Progress',
          children: [BookingTimeline(booking: booking)],
        ),
        if (booking.driver != null && !booking.isCancelled)
          SectionCard(
            title: 'Your driver',
            children: [
              Text(
                booking.driver!.label,
                key: const ValueKey('driver-name'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (booking.driver!.phone != null)
                _DriverPhone(phone: booking.driver!.phone!),
            ],
          ),
        SectionCard(
          title: 'Service',
          children: [
            Text(
              '${booking.serviceName} - ${booking.packageName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${vehicleLabel(booking.vehicleType)}'
              '${duration == null ? '' : ' - about ${formatDuration(duration)}'}',
            ),
            if (booking.inclusions.isNotEmpty) ...[
              const SizedBox(height: 8),
              InclusionList(items: booking.inclusions),
            ],
          ],
        ),
        SectionCard(
          title: 'Visit',
          children: [
            Text(formatDate(booking.date)),
            Text(booking.timeLabel),
            const SizedBox(height: 8),
            Text(addressText(booking)),
            if (booking.notes != null) ...[
              const SizedBox(height: 8),
              Text('Notes: ${booking.notes}'),
            ],
          ],
        ),
        SectionCard(
          title: 'Contact',
          children: [Text(booking.customerName), Text(booking.customerPhone)],
        ),
        if (booking.payment != null)
          SectionCard(
            title: 'Payment',
            children: [PaymentDetails(payment: booking.payment!)],
          )
        else if (booking.status == BookingStatus.pendingPayment &&
            !booking.canPay)
          const SectionCard(
            title: 'Payment',
            children: [Text('Online payment is not available right now.')],
          ),
        SectionCard(
          title: 'Price',
          children: [
            SummaryRow(
              label: booking.packageName,
              value: formatMoney(booking.packagePrice),
            ),
            for (final charge in booking.chosenCharges)
              SummaryRow(
                label: charge.name,
                value: chargeAmountText(charge.amount),
              ),
            const Divider(),
            SummaryRow(
              label: 'Total',
              value: formatMoney(booking.totalAmount),
              bold: true,
            ),
            if (booking.possibleCharges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'May apply on the day (not in the total)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              for (final charge in booking.possibleCharges)
                SummaryRow(
                  label: charge.name,
                  value: chargeAmountText(charge.amount),
                ),
            ],
          ],
        ),
      ],
    );
  }
}
