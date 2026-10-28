import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/payment.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart' show MessageBanner;
import '../../booking/presentation/booking_widgets.dart';
import '../../booking/providers/booking_providers.dart';
import 'payment_widgets.dart';

const String cancelledMessage =
    'Payment cancelled. If money was deducted, it will be matched automatically.';

enum _Phase { idle, working, confirming, paid, failed, cancelled }

/// Pays for one booking. The screen only reports what the checkout window said; the
/// server verifies it, and only the server's answer marks the booking paid.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _Phase _phase = _Phase.idle;
  String? _message;
  bool _testMode = false;
  Payment? _paid;

  // A checkout success waiting for the server to confirm it. Kept so "Check again"
  // re-asks the server without opening the checkout (and charging) a second time.
  String? _attemptId;
  CheckoutSuccess? _unconfirmed;

  void _set(_Phase phase, [String? message]) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  Future<void> _pay() async {
    _set(_Phase.working);
    try {
      final started =
          await ref.read(paymentRepositoryProvider).start(widget.bookingId);
      if (!mounted) return;
      _testMode = started.checkout.isTestMode;
      _attemptId = started.payment.id;
      final result =
          await ref.read(checkoutLauncherProvider).open(started.checkout);
      if (!mounted) return;
      switch (result) {
        case CheckoutSuccess():
          _unconfirmed = result;
          await _confirm();
        case CheckoutDismissed():
          await _cancelAttempt();
        case CheckoutPending():
          _set(
            _Phase.failed,
            'Complete the payment in your wallet app, then open this booking '
            'again to see its status.',
          );
          _refresh();
        case CheckoutFailure(:final message):
          _set(_Phase.failed, message);
          _refresh();
      }
    } catch (error) {
      _set(_Phase.failed, errorMessage(error));
    }
  }

  Future<void> _confirm() async {
    final success = _unconfirmed;
    final attempt = _attemptId;
    if (success == null || attempt == null) return;
    _set(_Phase.confirming);
    try {
      final verdict =
          await ref.read(paymentRepositoryProvider).verify(attempt, success);
      if (!mounted) return;
      _refresh();
      if (verdict.payment.isSuccessful &&
          verdict.bookingStatus != BookingStatus.cancelled) {
        _unconfirmed = null;
        _paid = verdict.payment;
        _set(_Phase.paid);
      } else if (verdict.payment.isSuccessful) {
        _unconfirmed = null;
        _set(
          _Phase.failed,
          'Your payment was received but this booking is cancelled. '
          'Our team will look into it.',
        );
      } else if (verdict.payment.status == PaymentStatus.pending) {
        _set(
          _Phase.confirming,
          'Your payment is still being confirmed by the bank.',
        );
      } else {
        _unconfirmed = null;
        _set(
          _Phase.failed,
          verdict.payment.failureReason ?? 'The payment did not go through.',
        );
      }
    } catch (error) {
      // Could not reach the server: money may have moved, so keep the result and
      // let the customer ask again instead of paying twice.
      _set(_Phase.confirming, errorMessage(error));
    }
  }

  Future<void> _cancelAttempt() async {
    final attempt = _attemptId;
    if (attempt != null) {
      try {
        await ref.read(paymentRepositoryProvider).cancel(attempt);
      } catch (_) {
        // The server closes stale attempts itself; nothing for the customer to do.
      }
    }
    _refresh();
    _set(_Phase.cancelled, cancelledMessage);
  }

  void _refresh() {
    if (!mounted) return;
    refreshBookings(ref, bookingId: widget.bookingId);
  }

  void _viewBooking() => context.go(AppRoutes.booking(widget.bookingId));

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(bookingProvider(widget.bookingId));
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SafeArea(
        child: AsyncView<Booking>(
          value: value,
          onRetry: () => ref.invalidate(bookingProvider(widget.bookingId)),
          builder: _body,
        ),
      ),
    );
  }

  Widget _body(Booking booking) {
    if (_phase == _Phase.paid) {
      return _Paid(
        payment: _paid!,
        onDone: _viewBooking,
        balance: _paid!.kind == PaymentKind.balance,
      );
    }
    if (_phase == _Phase.confirming) {
      return _Confirming(
        message: _message,
        onCheckAgain: _confirm,
        onBack: _viewBooking,
      );
    }
    if (booking.isPaid && booking.payment != null && !booking.canPayBalance) {
      return _Paid(
        payment: booking.payment!,
        onDone: _viewBooking,
        balance: false,
      );
    }
    if (!(booking.canPay || booking.canPayBalance) && _phase != _Phase.working) {
      return _Unavailable(booking: booking, onBack: _viewBooking);
    }
    final working = _phase == _Phase.working;
    // The server prices the payment; this is only what it will ask for.
    final isBalance = booking.canPayBalance;
    final amount = isBalance
        ? booking.balanceDue
        : (booking.advanceAmount > 0 ? booking.advanceAmount : booking.totalAmount);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_testMode)
          const MessageBanner(
            isError: false,
            message: 'Test mode: no real money will be charged.',
          ),
        if (_message != null)
          MessageBanner(
            isError: _phase == _Phase.failed,
            message: _message!,
          ),
        SectionCard(
          title: booking.code,
          children: [
            Text('${booking.serviceName} - ${booking.packageName}'),
            Text('${formatDate(booking.date)}, ${booking.timeLabel}'),
            const Divider(),
            if (isBalance) ...[
              SummaryRow(
                label: 'Final bill',
                value: formatMoney(booking.finalTotal),
              ),
              SummaryRow(
                label: 'Already paid',
                value: '- ${formatMoney(booking.amountPaid)}',
              ),
            ] else if (booking.advanceAmount > 0) ...[
              SummaryRow(
                label: 'Estimated total',
                value: formatMoney(booking.totalAmount),
              ),
            ],
            SummaryRow(
              label: isBalance
                  ? 'Balance to pay'
                  : (booking.advanceAmount > 0
                      ? 'Advance to pay now'
                      : 'Amount to pay'),
              value: formatMoney(amount),
              bold: true,
            ),
            if (!isBalance && booking.advanceAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'The rest is paid after the service. Any extra parts or '
                  'repairs are added only if you approve them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('pay-now'),
          onPressed: working ? null : _pay,
          child: working
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _phase == _Phase.failed || _phase == _Phase.cancelled
                      ? 'Try again - ${formatMoney(amount)}'
                      : 'Pay ${formatMoney(amount)}',
                ),
        ),
        const SizedBox(height: 8),
        Text(
          'Payments are processed securely by Razorpay. Your booking is '
          'confirmed once the payment is verified.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Paid extends StatelessWidget {
  const _Paid({
    required this.payment,
    required this.onDone,
    required this.balance,
  });

  final Payment payment;
  final VoidCallback onDone;

  /// The balance after the service (otherwise the advance when booking).
  final bool balance;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Icon(
            Icons.check_circle,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        MessageBanner(
          isError: false,
          message: balance
              ? 'Payment received. Your bill is settled. Thank you!'
              : 'Advance received. Your booking is confirmed.',
        ),
        SectionCard(
          title: 'Payment',
          children: [PaymentDetails(payment: payment)],
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('view-booking'),
          onPressed: onDone,
          child: const Text('View booking'),
        ),
      ],
    );
  }
}

class _Confirming extends StatelessWidget {
  const _Confirming({
    required this.message,
    required this.onCheckAgain,
    required this.onBack,
  });

  final String? message;
  final VoidCallback onCheckAgain;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (message == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Confirming your payment...'),
              ],
            ),
          )
        else ...[
          MessageBanner(message: message!),
          const Text(
            'Do not pay again. Check again in a moment; if money was '
            'deducted, your booking will be confirmed automatically.',
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('check-again'),
            onPressed: onCheckAgain,
            child: const Text('Check again'),
          ),
          TextButton(
            key: const ValueKey('back-to-booking'),
            onPressed: onBack,
            child: const Text('Back to booking'),
          ),
          TextButton.icon(
            onPressed: () => context.push(AppRoutes.support),
            icon: const Icon(Icons.support_agent),
            label: const Text('Contact support'),
          ),
        ],
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.booking, required this.onBack});

  final Booking booking;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final String message;
    if (booking.isCancelled) {
      message = 'This booking was cancelled, so it cannot be paid.';
    } else if (booking.status == BookingStatus.pendingPayment) {
      message = 'Online payment is not available right now. Please try again '
          'later.';
    } else {
      message = 'There is nothing to pay for this booking.';
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        MessageBanner(isError: false, message: message),
        OutlinedButton(
          key: const ValueKey('back-to-booking'),
          onPressed: onBack,
          child: const Text('Back to booking'),
        ),
        TextButton.icon(
          onPressed: () =>
              context.push(AppRoutes.supportForBooking(booking.code)),
          icon: const Icon(Icons.support_agent),
          label: const Text('Contact support'),
        ),
      ],
    );
  }
}
