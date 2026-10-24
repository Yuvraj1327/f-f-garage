import 'enums.dart';
import 'json_reader.dart';

/// A payment attempt. Used both inside a booking (where the server sends only the
/// summary fields) and for the payment endpoints.
class Payment {
  const Payment({
    required this.id,
    required this.status,
    required this.amount,
    required this.currency,
    required this.livemode,
    required this.createdAt,
    this.bookingId,
    this.gatewayOrderId,
    this.method,
    this.transactionId,
    this.paidAt,
    this.failureReason,
  });

  factory Payment.fromJson(Map<String, dynamic> json) => Payment(
        id: JsonReader.string(json, 'id'),
        bookingId: JsonReader.optionalString(json, 'booking_id'),
        gatewayOrderId: JsonReader.optionalString(json, 'gateway_order_id'),
        status: PaymentStatus.fromApiValue(JsonReader.string(json, 'status')),
        amount: JsonReader.money(json, 'amount'),
        currency: JsonReader.string(json, 'currency'),
        method: JsonReader.optionalString(json, 'method'),
        transactionId: JsonReader.optionalString(json, 'transaction_id'),
        paidAt: json['paid_at'] == null
            ? null
            : DateTime.parse(JsonReader.string(json, 'paid_at')),
        failureReason: JsonReader.optionalString(json, 'failure_reason'),
        livemode: JsonReader.boolean(json, 'livemode'),
        createdAt: DateTime.parse(JsonReader.string(json, 'created_at')),
      );

  final String id;
  final String? bookingId;
  final String? gatewayOrderId;
  final PaymentStatus status;
  final double amount;
  final String currency;
  final String? method;

  /// The gateway's payment reference (shown to the customer as the transaction ID).
  final String? transactionId;
  final DateTime? paidAt;
  final String? failureReason;

  /// False for sandbox (test) payments.
  final bool livemode;
  final DateTime createdAt;

  bool get isSuccessful => status == PaymentStatus.successful;
}

/// What the Razorpay checkout needs. Built by the server: the amount in it is the
/// server's own and the app never changes it.
class CheckoutOptions {
  const CheckoutOptions({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
    required this.name,
    required this.description,
    required this.mode,
    this.prefillName,
    this.prefillContact,
    this.prefillEmail,
  });

  factory CheckoutOptions.fromJson(Map<String, dynamic> json) => CheckoutOptions(
        keyId: JsonReader.string(json, 'key_id'),
        orderId: JsonReader.string(json, 'order_id'),
        amountPaise: JsonReader.integer(json, 'amount_paise'),
        currency: JsonReader.string(json, 'currency'),
        name: JsonReader.string(json, 'name'),
        description: JsonReader.string(json, 'description'),
        prefillName: JsonReader.optionalString(json, 'prefill_name'),
        prefillContact: JsonReader.optionalString(json, 'prefill_contact'),
        prefillEmail: JsonReader.optionalString(json, 'prefill_email'),
        mode: JsonReader.string(json, 'mode'),
      );

  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currency;
  final String name;
  final String description;
  final String? prefillName;
  final String? prefillContact;
  final String? prefillEmail;

  /// 'test' (sandbox, no real money) or 'live'.
  final String mode;

  bool get isTestMode => mode != 'live';

  /// The options map the Razorpay SDK expects.
  Map<String, dynamic> toRazorpayOptions() {
    final prefill = <String, String>{
      if (prefillName != null) 'name': prefillName!,
      if (prefillContact != null) 'contact': prefillContact!,
      if (prefillEmail != null) 'email': prefillEmail!,
    };
    return {
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': currency,
      'name': name,
      'description': description,
      if (prefill.isNotEmpty) 'prefill': prefill,
    };
  }
}

class PaymentInitiated {
  const PaymentInitiated({required this.payment, required this.checkout});

  factory PaymentInitiated.fromJson(Map<String, dynamic> json) =>
      PaymentInitiated(
        payment: Payment.fromJson(_object(json, 'payment')),
        checkout: CheckoutOptions.fromJson(_object(json, 'checkout')),
      );

  final Payment payment;
  final CheckoutOptions checkout;
}

/// The server's verdict after it checked a checkout result itself.
class PaymentResult {
  const PaymentResult({
    required this.payment,
    required this.bookingStatus,
    required this.outcome,
    required this.paid,
  });

  factory PaymentResult.fromJson(Map<String, dynamic> json) => PaymentResult(
        payment: Payment.fromJson(_object(json, 'payment')),
        bookingStatus:
            BookingStatus.fromApiValue(JsonReader.string(json, 'booking_status')),
        outcome: JsonReader.string(json, 'outcome'),
        paid: JsonReader.boolean(json, 'paid'),
      );

  final Payment payment;
  final BookingStatus bookingStatus;

  /// paid, already_processed, pending, failed, amount_mismatch, ...
  final String outcome;
  final bool paid;
}

Map<String, dynamic> _object(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) {
    return value;
  }
  throw FormatException('Expected "$key" to be an object, got $value');
}

/// What the checkout window reported to the app. Never believed on its own: a
/// success is sent to the server, which verifies it.
sealed class CheckoutResult {
  const CheckoutResult();
}

class CheckoutSuccess extends CheckoutResult {
  const CheckoutSuccess({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });

  final String orderId;
  final String paymentId;
  final String signature;
}

/// The payment failed inside the checkout (declined card, network, ...).
class CheckoutFailure extends CheckoutResult {
  const CheckoutFailure(this.message);

  final String message;
}

/// The customer closed the checkout without paying.
class CheckoutDismissed extends CheckoutResult {
  const CheckoutDismissed();
}

/// The customer went to an external wallet app; the result is not known yet.
class CheckoutPending extends CheckoutResult {
  const CheckoutPending();
}
