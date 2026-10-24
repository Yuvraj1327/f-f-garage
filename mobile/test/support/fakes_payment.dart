import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/booking.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/payment.dart';
import 'package:ff_garage/data/repositories/payment_repository.dart';
import 'package:ff_garage/data/services/checkout_launcher.dart';

import 'fakes_booking.dart';

Payment payment({
  String id = 'pay-1',
  String bookingId = 'b1',
  PaymentStatus status = PaymentStatus.successful,
  double amount = 499,
  String? method = 'upi',
  String? transactionId = 'pay_TEST123',
  DateTime? paidAt,
  String? failureReason,
  bool livemode = false,
}) =>
    Payment(
      id: id,
      bookingId: bookingId,
      gatewayOrderId: 'order_TEST1',
      status: status,
      amount: amount,
      currency: 'INR',
      method: method,
      transactionId: transactionId,
      paidAt: status == PaymentStatus.successful
          ? (paidAt ?? DateTime.utc(2026, 10, 20, 10, 35))
          : null,
      failureReason: failureReason,
      livemode: livemode,
      createdAt: DateTime.utc(2026, 10, 20, 10, 30),
    );

CheckoutOptions checkoutOptions({
  String mode = 'test',
  int amountPaise = 49900,
}) =>
    CheckoutOptions(
      keyId: 'rzp_test_abc123',
      orderId: 'order_TEST1',
      amountPaise: amountPaise,
      currency: 'INR',
      name: 'F&F Two Wheeler Garage',
      description: 'FF-000001',
      mode: mode,
    );

const ApiException offline = ApiException(
  type: ApiErrorType.network,
  message: 'No internet connection.',
);

/// In-memory payments tied to a [FakeBookingRepository]. A verified payment makes the
/// booking confirmed and paid, like the real server; nothing else does.
class FakePaymentRepository implements PaymentRepository {
  FakePaymentRepository(this.bookings);

  final FakeBookingRepository bookings;

  ApiException? startError;
  ApiException? verifyError;

  /// What the "server" answers to a verify. Null = verified, booking paid.
  PaymentResult? verifyResult;

  final List<String> starts = [];
  final List<({String paymentId, CheckoutSuccess result})> verifies = [];
  final List<String> cancels = [];
  final Map<String, String> _bookingOf = {};

  @override
  Future<PaymentInitiated> start(String bookingId) async {
    starts.add(bookingId);
    if (startError != null) throw startError!;
    final booking = await bookings.get(bookingId);
    _bookingOf['pay-1'] = bookingId;
    return PaymentInitiated(
      payment: payment(
        bookingId: bookingId,
        status: PaymentStatus.pending,
        amount: booking.totalAmount,
        method: null,
        transactionId: null,
      ),
      checkout: checkoutOptions(
        amountPaise: (booking.totalAmount * 100).round(),
      ),
    );
  }

  @override
  Future<PaymentResult> verify(String paymentId, CheckoutSuccess result) async {
    verifies.add((paymentId: paymentId, result: result));
    if (verifyError != null) throw verifyError!;
    final forced = verifyResult;
    if (forced != null) return forced;
    final old = await bookings.get(_bookingOf[paymentId]!);
    final paid = payment(
      bookingId: old.id,
      amount: old.totalAmount,
      transactionId: result.paymentId,
    );
    final confirmed = _confirmed(old, paid);
    bookings.bookings = [
      for (final b in bookings.bookings) b.id == old.id ? confirmed : b,
    ];
    return PaymentResult(
      payment: paid,
      bookingStatus: BookingStatus.confirmed,
      outcome: 'paid',
      paid: true,
    );
  }

  @override
  Future<Payment> cancel(String paymentId) async {
    cancels.add(paymentId);
    return payment(status: PaymentStatus.cancelled);
  }

  @override
  Future<Payment> get(String paymentId) async => payment(id: paymentId);

  @override
  Future<List<Payment>> forBooking(String bookingId) async => const [];
}

Booking _confirmed(Booking old, Payment paid) => booking(
      id: old.id,
      number: old.number,
      status: BookingStatus.confirmed,
      price: old.packagePrice,
      extras: old.extraChargesTotal,
      payment: paid,
      isPaid: true,
    );

/// Stands in for the Razorpay window.
class FakeCheckoutLauncher implements CheckoutLauncher {
  FakeCheckoutLauncher({this.result});

  /// What the "window" reports. Null = a successful payment.
  CheckoutResult? result;

  final List<CheckoutOptions> opened = [];

  @override
  Future<CheckoutResult> open(CheckoutOptions options) async {
    opened.add(options);
    return result ??
        CheckoutSuccess(
          orderId: options.orderId,
          paymentId: 'pay_TEST123',
          signature: 'sig_from_device',
        );
  }
}
