import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/booking_journey.dart';
import '../support/fakes_booking.dart';
import '../support/fakes_payment.dart';
import '../support/pump_app.dart';

Future<AppHarness> _open(
  WidgetTester tester, {
  FakePaymentRepository Function(FakeBookingRepository)? payments,
  FakeCheckoutLauncher? launcher,
  bool canPay = true,
  String path = '/home/bookings/b1/pay',
}) async {
  useTallScreen(tester);
  final bookings = FakeBookingRepository(
    bookings: [booking(canPay: canPay)],
  );
  final harness = customerHarness(
    bookings: bookings,
    payments: payments?.call(bookings),
    launcher: launcher,
  );
  await harness.pump(tester);
  goTo(tester, path);
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  group('paying', () {
    testWidgets('shows the amount from the booking and the test-mode note',
        (tester) async {
      await _open(tester);
      expect(find.text('Pay ₹499'), findsOneWidget);
      expect(find.text('Amount to pay'), findsOneWidget);
    });

    testWidgets('a verified payment confirms the booking', (tester) async {
      final harness = await _open(tester);
      await tapKey(tester, 'pay-now');

      expect(harness.paymentRepo.starts, ['b1']);
      expect(harness.launcher.opened, hasLength(1));
      expect(harness.launcher.opened.single.amountPaise, 49900);
      // The device's report went to the server, which decided.
      expect(harness.paymentRepo.verifies, hasLength(1));
      expect(harness.paymentRepo.verifies.single.result.signature,
          'sig_from_device');
      expect(find.text('Advance received. Your booking is confirmed.'),
          findsOneWidget);
      expect(find.text('pay_TEST123'), findsOneWidget);
      expect(find.text('Test payment - no real money was charged.'),
          findsOneWidget);
    });

    testWidgets('View booking shows the booking as confirmed and paid',
        (tester) async {
      await _open(tester);
      await tapKey(tester, 'pay-now');
      await tapKey(tester, 'view-booking');

      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
    });

    testWidgets('closing the checkout cancels the attempt and says so',
        (tester) async {
      final harness = await _open(
        tester,
        launcher: FakeCheckoutLauncher(result: const CheckoutDismissed()),
      );
      await tapKey(tester, 'pay-now');

      expect(harness.paymentRepo.verifies, isEmpty);
      expect(harness.paymentRepo.cancels, ['pay-1']);
      expect(
        find.textContaining('If money was deducted, it will be matched'),
        findsOneWidget,
      );
      expect(find.textContaining('Try again'), findsOneWidget);
    });

    testWidgets('a failed payment shows the reason and can be retried',
        (tester) async {
      final launcher = FakeCheckoutLauncher(
        result: const CheckoutFailure('Your card was declined.'),
      );
      final harness = await _open(tester, launcher: launcher);
      await tapKey(tester, 'pay-now');

      expect(find.text('Your card was declined.'), findsOneWidget);
      expect(harness.paymentRepo.verifies, isEmpty);

      launcher.result = null;
      await tapKey(tester, 'pay-now');
      expect(harness.paymentRepo.starts, hasLength(2));
      expect(find.text('Advance received. Your booking is confirmed.'),
          findsOneWidget);
    });

    testWidgets('a server that cannot confirm keeps the result and never '
        'opens the checkout again', (tester) async {
      final harness = await _open(tester);
      harness.paymentRepo.verifyError = offline;
      await tapKey(tester, 'pay-now');

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(find.textContaining('Do not pay again'), findsOneWidget);

      harness.paymentRepo.verifyError = null;
      await tapKey(tester, 'check-again');

      expect(harness.launcher.opened, hasLength(1));
      expect(harness.paymentRepo.starts, hasLength(1));
      expect(harness.paymentRepo.verifies, hasLength(2));
      expect(find.text('Advance received. Your booking is confirmed.'),
          findsOneWidget);
    });

    testWidgets('a payment the bank has not settled yet is not shown as paid',
        (tester) async {
      final harness = await _open(tester);
      harness.paymentRepo.verifyResult = PaymentResult(
        payment: payment(
          status: PaymentStatus.pending,
          method: null,
          transactionId: null,
        ),
        bookingStatus: BookingStatus.pendingPayment,
        outcome: 'pending',
        paid: false,
      );
      await tapKey(tester, 'pay-now');

      expect(find.text('Your payment is still being confirmed by the bank.'),
          findsOneWidget);
      expect(find.text('Advance received. Your booking is confirmed.'),
          findsNothing);
    });

    testWidgets('a payment the server rejects is shown as failed',
        (tester) async {
      final harness = await _open(tester);
      harness.paymentRepo.verifyResult = PaymentResult(
        payment: payment(
          status: PaymentStatus.failed,
          failureReason: 'Payment amount did not match the booking',
          method: null,
          transactionId: null,
        ),
        bookingStatus: BookingStatus.pendingPayment,
        outcome: 'amount_mismatch',
        paid: false,
      );
      await tapKey(tester, 'pay-now');

      expect(find.text('Payment amount did not match the booking'),
          findsOneWidget);
      expect(find.text('Advance received. Your booking is confirmed.'),
          findsNothing);
    });

    testWidgets('a start error is shown and nothing is opened',
        (tester) async {
      final harness = await _open(tester);
      harness.paymentRepo.startError = offline;
      await tapKey(tester, 'pay-now');

      expect(find.text('No internet connection.'), findsOneWidget);
      expect(harness.launcher.opened, isEmpty);
    });

    testWidgets('a booking that cannot be paid has no pay button',
        (tester) async {
      await _open(tester, canPay: false);
      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
      expect(find.text('Online payment is not available right now. Please '
          'try again later.'), findsOneWidget);
    });

    testWidgets('an already paid booking shows the receipt, not a button',
        (tester) async {
      useTallScreen(tester);
      final bookings = FakeBookingRepository(bookings: [
        booking(
          status: BookingStatus.confirmed,
          payment: payment(),
          isPaid: true,
        ),
      ]);
      final harness = customerHarness(bookings: bookings);
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1/pay');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
      expect(find.text('pay_TEST123'), findsOneWidget);
      expect(harness.paymentRepo.starts, isEmpty);
    });

    testWidgets('a cancelled booking cannot be paid', (tester) async {
      useTallScreen(tester);
      final bookings = FakeBookingRepository(bookings: [
        booking(status: BookingStatus.cancelled),
      ]);
      final harness = customerHarness(bookings: bookings);
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1/pay');
      await tester.pumpAndSettle();

      expect(find.text('This booking was cancelled, so it cannot be paid.'),
          findsOneWidget);
    });
  });

  group('booking detail and history', () {
    testWidgets('detail offers Pay now when the server allows it',
        (tester) async {
      await _open(tester, path: '/home/bookings/b1');
      expect(find.byKey(const ValueKey('pay-now')), findsOneWidget);
      await tapKey(tester, 'pay-now');
      expect(find.text('Amount to pay'), findsOneWidget);
    });

    testWidgets('detail says when online payment is unavailable',
        (tester) async {
      await _open(tester, canPay: false, path: '/home/bookings/b1');
      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
      expect(find.text('Online payment is not available right now.'),
          findsOneWidget);
    });

    testWidgets('detail shows the transaction details of a paid booking',
        (tester) async {
      useTallScreen(tester);
      final bookings = FakeBookingRepository(bookings: [
        booking(
          status: BookingStatus.confirmed,
          payment: payment(),
          isPaid: true,
        ),
      ]);
      final harness = customerHarness(bookings: bookings);
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();

      expect(find.text('Payment'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('UPI'), findsOneWidget);
      expect(find.text('pay_TEST123'), findsOneWidget);
      expect(find.text('Transaction ID'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-now')), findsNothing);
    });

    testWidgets('detail shows a failed attempt with its reason',
        (tester) async {
      useTallScreen(tester);
      final bookings = FakeBookingRepository(bookings: [
        booking(
          canPay: true,
          payment: payment(
            status: PaymentStatus.failed,
            failureReason: 'Card declined',
            method: null,
            transactionId: null,
          ),
        ),
      ]);
      final harness = customerHarness(bookings: bookings);
      await harness.pump(tester);
      goTo(tester, '/home/bookings/b1');
      await tester.pumpAndSettle();

      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.text('Card declined'), findsOneWidget);
      expect(find.byKey(const ValueKey('pay-now')), findsOneWidget);
    });

    testWidgets('history shows a payment line per booking', (tester) async {
      useTallScreen(tester);
      final bookings = FakeBookingRepository(bookings: [
        booking(
          id: 'b2',
          number: 2,
          status: BookingStatus.confirmed,
          payment: payment(id: 'p2', bookingId: 'b2'),
          isPaid: true,
        ),
        booking(
          id: 'b1',
          number: 1,
          payment: payment(
            status: PaymentStatus.failed,
            method: null,
            transactionId: null,
          ),
        ),
        booking(id: 'b3', number: 3),
      ]);
      final harness = customerHarness(bookings: bookings);
      await harness.pump(tester);
      goTo(tester, '/home/bookings');
      await tester.pumpAndSettle();

      expect(find.text('Paid via UPI - pay_TEST123'), findsOneWidget);
      expect(find.text('Payment failed'), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-line-b3')), findsNothing);
    });
  });
}
