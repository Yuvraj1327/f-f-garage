import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/payment.dart';
import '../../booking/presentation/booking_widgets.dart';

String paymentStatusLabel(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.successful:
      return 'Paid';
    case PaymentStatus.pending:
      return 'Payment pending';
    case PaymentStatus.failed:
      return 'Payment failed';
    case PaymentStatus.cancelled:
      return 'Payment cancelled';
  }
}

String methodLabel(String method) {
  switch (method) {
    case 'upi':
      return 'UPI';
    case 'card':
      return 'Card';
    case 'netbanking':
      return 'Net banking';
    case 'wallet':
      return 'Wallet';
    default:
      return method.isEmpty
          ? method
          : '${method[0].toUpperCase()}${method.substring(1)}';
  }
}

/// One word for the payment's state: "Paid", "Pending", "Failed", "Cancelled".
String paymentStateWord(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.successful:
      return 'Paid';
    case PaymentStatus.pending:
      return 'Pending';
    case PaymentStatus.failed:
      return 'Failed';
    case PaymentStatus.cancelled:
      return 'Cancelled';
  }
}

/// One line for the history list: "Paid via UPI - pay_XYZ", "Payment failed", ...
String paymentSummaryLine(Payment payment) {
  if (!payment.isSuccessful) {
    return paymentStatusLabel(payment.status);
  }
  final method = payment.method == null ? '' : ' via ${methodLabel(payment.method!)}';
  final reference =
      payment.transactionId == null ? '' : ' - ${payment.transactionId}';
  return 'Paid$method$reference';
}

/// The payment's details: status, amount, method, transaction ID, date.
class PaymentDetails extends StatelessWidget {
  const PaymentDetails({super.key, required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final paidAt = payment.paidAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SummaryRow(
          label: 'Status',
          value: paymentStatusLabel(payment.status),
          bold: payment.isSuccessful,
        ),
        SummaryRow(label: 'Amount', value: formatMoney(payment.amount)),
        if (payment.method != null)
          SummaryRow(label: 'Method', value: methodLabel(payment.method!)),
        if (payment.transactionId != null)
          SummaryRow(label: 'Transaction ID', value: payment.transactionId!),
        if (paidAt != null)
          SummaryRow(label: 'Paid on', value: formatDateTime(paidAt)),
        if (!payment.isSuccessful && payment.failureReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(payment.failureReason!),
          ),
        if (!payment.livemode)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Test payment - no real money was charged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
