import 'enums.dart';
import 'json_reader.dart';

/// A part or repair found during the service. It is only billed once the
/// customer approves it.
class ExtraRequest {
  const ExtraRequest({
    required this.id,
    required this.bookingId,
    required this.chargeType,
    required this.name,
    required this.amount,
    required this.status,
    required this.requestedByRole,
    required this.createdAt,
    this.description,
    this.decidedAt,
  });

  factory ExtraRequest.fromJson(Map<String, dynamic> json) => ExtraRequest(
        id: JsonReader.string(json, 'id'),
        bookingId: JsonReader.string(json, 'booking_id'),
        chargeType: ExtraChargeType.fromApiValue(
          JsonReader.string(json, 'charge_type'),
        ),
        name: JsonReader.string(json, 'name'),
        description: JsonReader.optionalString(json, 'description'),
        amount: JsonReader.money(json, 'amount'),
        status: ExtraStatus.fromApiValue(JsonReader.string(json, 'status')),
        requestedByRole: JsonReader.string(json, 'requested_by_role'),
        decidedAt: JsonReader.optionalString(json, 'decided_at') == null
            ? null
            : DateTime.parse(JsonReader.string(json, 'decided_at')),
        createdAt: DateTime.parse(JsonReader.string(json, 'created_at')),
      );

  final String id;
  final String bookingId;
  final ExtraChargeType chargeType;
  final String name;
  final String? description;
  final double amount;
  final ExtraStatus status;
  final String requestedByRole;
  final DateTime? decidedAt;
  final DateTime createdAt;

  bool get isOpen => status == ExtraStatus.proposed;
}

/// One payment on the bill (advance or balance), with its receipt reference.
class BillPayment {
  const BillPayment({
    required this.id,
    required this.kind,
    required this.status,
    required this.amount,
    required this.createdAt,
    this.method,
    this.receipt,
    this.transactionId,
    this.paidAt,
  });

  factory BillPayment.fromJson(Map<String, dynamic> json) => BillPayment(
        id: JsonReader.string(json, 'id'),
        kind: PaymentKind.fromApiValue(JsonReader.string(json, 'kind')),
        status: PaymentStatus.fromApiValue(JsonReader.string(json, 'status')),
        amount: JsonReader.money(json, 'amount'),
        method: JsonReader.optionalString(json, 'method'),
        receipt: JsonReader.optionalString(json, 'receipt'),
        transactionId: JsonReader.optionalString(json, 'transaction_id'),
        paidAt: JsonReader.optionalString(json, 'paid_at') == null
            ? null
            : DateTime.parse(JsonReader.string(json, 'paid_at')),
        createdAt: DateTime.parse(JsonReader.string(json, 'created_at')),
      );

  final String id;
  final PaymentKind kind;
  final PaymentStatus status;
  final double amount;
  final String? method;
  final String? receipt;
  final String? transactionId;
  final DateTime? paidAt;
  final DateTime createdAt;

  bool get isSuccessful => status == PaymentStatus.successful;
}

/// A refund an admin recorded (made in the payment gateway's dashboard).
class Refund {
  const Refund({
    required this.id,
    required this.paymentId,
    required this.amount,
    required this.createdAt,
    this.note,
  });

  factory Refund.fromJson(Map<String, dynamic> json) => Refund(
        id: JsonReader.string(json, 'id'),
        paymentId: JsonReader.string(json, 'payment_id'),
        amount: JsonReader.money(json, 'amount'),
        note: JsonReader.optionalString(json, 'note'),
        createdAt: DateTime.parse(JsonReader.string(json, 'created_at')),
      );

  final String id;
  final String paymentId;
  final double amount;
  final String? note;
  final DateTime createdAt;
}

/// Everything about what a booking costs and what has been paid. Every figure
/// is the server's: the app only shows them.
class Bill {
  const Bill({
    required this.bookingId,
    required this.bookingCode,
    required this.status,
    required this.isFinal,
    required this.serviceName,
    required this.packageName,
    required this.packagePrice,
    required this.addonsTotal,
    required this.discountAmount,
    required this.estimatedTotal,
    required this.advancePercent,
    required this.advanceDue,
    required this.advancePaid,
    required this.approvedExtras,
    required this.approvedExtrasTotal,
    required this.pendingExtras,
    required this.pendingExtrasTotal,
    required this.finalTotal,
    required this.amountPaid,
    required this.balanceDue,
    required this.canPayBalance,
    required this.refundedTotal,
    required this.payments,
    required this.refunds,
    required this.refundPolicy,
    this.couponCode,
  });

  factory Bill.fromJson(Map<String, dynamic> json) => Bill(
        bookingId: JsonReader.string(json, 'booking_id'),
        bookingCode: JsonReader.string(json, 'booking_code'),
        status: BookingStatus.fromApiValue(JsonReader.string(json, 'status')),
        isFinal: JsonReader.boolean(json, 'is_final'),
        serviceName: JsonReader.string(json, 'service_name'),
        packageName: JsonReader.string(json, 'package_name'),
        packagePrice: JsonReader.money(json, 'package_price'),
        addonsTotal: JsonReader.money(json, 'addons_total'),
        couponCode: JsonReader.optionalString(json, 'coupon_code'),
        discountAmount: JsonReader.money(json, 'discount_amount'),
        estimatedTotal: JsonReader.money(json, 'estimated_total'),
        advancePercent: JsonReader.money(json, 'advance_percent'),
        advanceDue: JsonReader.money(json, 'advance_due'),
        advancePaid: JsonReader.money(json, 'advance_paid'),
        approvedExtras: JsonReader.objectList(
          json,
          'approved_extras',
          ExtraRequest.fromJson,
        ),
        approvedExtrasTotal: JsonReader.money(json, 'approved_extras_total'),
        pendingExtras: JsonReader.objectList(
          json,
          'pending_extras',
          ExtraRequest.fromJson,
        ),
        pendingExtrasTotal: JsonReader.money(json, 'pending_extras_total'),
        finalTotal: JsonReader.money(json, 'final_total'),
        amountPaid: JsonReader.money(json, 'amount_paid'),
        balanceDue: JsonReader.money(json, 'balance_due'),
        canPayBalance: JsonReader.boolean(json, 'can_pay_balance'),
        refundedTotal: JsonReader.money(json, 'refunded_total'),
        payments: JsonReader.objectList(
          json,
          'payments',
          BillPayment.fromJson,
        ),
        refunds: JsonReader.objectList(json, 'refunds', Refund.fromJson),
        refundPolicy: JsonReader.optionalString(json, 'refund_policy') ?? '',
      );

  final String bookingId;
  final String bookingCode;
  final BookingStatus status;

  /// True once the service is completed: the figures are then the final bill.
  final bool isFinal;
  final String serviceName;
  final String packageName;
  final double packagePrice;
  final double addonsTotal;
  final String? couponCode;
  final double discountAmount;
  final double estimatedTotal;
  final double advancePercent;
  final double advanceDue;
  final double advancePaid;
  final List<ExtraRequest> approvedExtras;
  final double approvedExtrasTotal;
  final List<ExtraRequest> pendingExtras;
  final double pendingExtrasTotal;
  final double finalTotal;
  final double amountPaid;
  final double balanceDue;
  final bool canPayBalance;
  final double refundedTotal;
  final List<BillPayment> payments;
  final List<Refund> refunds;

  /// The garage's own refund policy text (empty = none configured).
  final String refundPolicy;

  List<BillPayment> get successfulPayments =>
      payments.where((p) => p.isSuccessful).toList();
}
