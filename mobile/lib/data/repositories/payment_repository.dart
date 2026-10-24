import '../../core/network/api_exception.dart';
import '../models/payment.dart';
import '../services/payment_api_service.dart';

/// Payments for the signed-in customer. Throws [ApiException] only.
///
/// The app never sends an amount: the server prices the payment from the booking.
class PaymentRepository {
  PaymentRepository(this._service);

  final PaymentApiService _service;

  /// Starts (or resumes) the payment for a booking.
  Future<PaymentInitiated> start(String bookingId) async =>
      _parse(await _service.start(bookingId), PaymentInitiated.fromJson);

  /// Hands the checkout result to the server. The server recomputes the signature
  /// and asks the gateway before marking anything paid.
  Future<PaymentResult> verify(String paymentId, CheckoutSuccess result) async =>
      _parse(
        await _service.verify(paymentId, {
          'razorpay_order_id': result.orderId,
          'razorpay_payment_id': result.paymentId,
          'razorpay_signature': result.signature,
        }),
        PaymentResult.fromJson,
      );

  /// The customer closed the checkout without paying.
  Future<Payment> cancel(String paymentId) async =>
      _parse(await _service.cancel(paymentId), Payment.fromJson);

  Future<Payment> get(String paymentId) async =>
      _parse(await _service.get(paymentId), Payment.fromJson);

  /// Attempts for a booking, newest first.
  Future<List<Payment>> forBooking(String bookingId) async {
    final rows = await _service.forBooking(bookingId);
    try {
      return rows.map(Payment.fromJson).toList();
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
