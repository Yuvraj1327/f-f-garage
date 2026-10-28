import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/billing.dart';
import '../../../data/providers/data_providers.dart';
import '../../booking/presentation/booking_widgets.dart';
import '../../payment/presentation/payment_widgets.dart' show methodLabel;

final adminBillProvider = FutureProvider.autoDispose.family<Bill, String>(
  (ref, bookingId) => ref.watch(billingRepositoryProvider).adminBill(bookingId),
);

/// The bill as the customer sees it, plus "Record refund" on each payment.
/// Refunds are decided by an admin and made in the payment gateway's
/// dashboard; recording one here only updates the customer's receipt.
class AdminBillCard extends ConsumerWidget {
  const AdminBillCard({super.key, required this.bookingId});

  final String bookingId;

  Future<void> _refund(
    BuildContext context,
    WidgetRef ref,
    BillPayment payment,
    double refundable,
  ) async {
    final input = await showDialog<(double, String?)>(
      context: context,
      builder: (_) => _RefundDialog(max: refundable),
    );
    if (input == null || !context.mounted) return;
    try {
      await ref.read(billingRepositoryProvider).recordRefund(
            payment.id,
            amount: input.$1,
            note: input.$2,
          );
      ref.invalidate(adminBillProvider(bookingId));
      if (context.mounted) showSuccessSnack(context, 'Refund recorded.');
    } catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminBillProvider(bookingId));
    return value.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => SectionCard(
        title: 'Bill',
        children: [
          Text(errorMessage(error)),
          TextButton(
            onPressed: () => ref.invalidate(adminBillProvider(bookingId)),
            child: const Text('Retry'),
          ),
        ],
      ),
      data: (bill) {
        final textTheme = Theme.of(context).textTheme;
        double refundedFor(BillPayment p) => bill.refunds
            .where((r) => r.paymentId == p.id)
            .fold<double>(0, (sum, r) => sum + r.amount);
        return SectionCard(
          title: bill.isFinal ? 'Final bill' : 'Bill so far',
          children: [
            SummaryRow(
              label: 'Estimated total',
              value: formatMoney(bill.estimatedTotal),
            ),
            if (bill.discountAmount > 0)
              SummaryRow(
                label: 'Coupon ${bill.couponCode ?? ''}'.trim(),
                value: '- ${formatMoney(bill.discountAmount)}',
              ),
            for (final extra in bill.approvedExtras)
              SummaryRow(
                label: 'Approved: ${extra.name}',
                value: formatMoney(extra.amount),
              ),
            if (bill.pendingExtras.isNotEmpty)
              SummaryRow(
                label: 'Waiting for the customer',
                value: formatMoney(bill.pendingExtrasTotal),
              ),
            const Divider(),
            SummaryRow(
              key: const ValueKey('admin-final'),
              label: 'Final total',
              value: formatMoney(bill.finalTotal),
              bold: true,
            ),
            SummaryRow(label: 'Paid', value: formatMoney(bill.amountPaid)),
            SummaryRow(
              key: const ValueKey('admin-balance'),
              label: 'Balance',
              value: formatMoney(bill.balanceDue),
              bold: true,
            ),
            if (bill.refundedTotal > 0)
              SummaryRow(
                label: 'Refunded',
                value: formatMoney(bill.refundedTotal),
              ),
            if (bill.successfulPayments.isNotEmpty) ...[
              const Divider(),
              Text('Payments', style: textTheme.labelLarge),
              for (final payment in bill.successfulPayments)
                Builder(
                  builder: (context) {
                    final refundable = payment.amount - refundedFor(payment);
                    return Padding(
                      key: ValueKey('admin-payment-${payment.id}'),
                      padding: const EdgeInsets.only(top: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${payment.kind.label} - '
                                  '${formatMoney(payment.amount)}',
                                ),
                                Text(
                                  [
                                    if (payment.method != null)
                                      methodLabel(payment.method!),
                                    if (payment.transactionId != null)
                                      payment.transactionId!,
                                  ].join(' - '),
                                  style: textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (refundable > 0)
                            TextButton(
                              key: ValueKey('refund-${payment.id}'),
                              onPressed: () =>
                                  _refund(context, ref, payment, refundable),
                              child: const Text('Record refund'),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 6),
              Text(
                'Refund in the payment gateway dashboard first, then record '
                'it here. Nothing is refunded automatically.',
                style: textTheme.bodySmall,
              ),
            ],
            for (final refund in bill.refunds)
              SummaryRow(
                label: 'Refund${refund.note == null ? '' : ' (${refund.note})'}',
                value: formatMoney(refund.amount),
              ),
          ],
        );
      },
    );
  }
}

class _RefundDialog extends StatefulWidget {
  const _RefundDialog({required this.max});

  final double max;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.max.toStringAsFixed(2));
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record a refund'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Only record a refund you have already made in the payment '
              'gateway. You can record up to ${formatMoney(widget.max)}.',
            ),
            TextFormField(
              key: const ValueKey('refund-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final value = double.tryParse((v ?? '').trim());
                if (value == null || value <= 0) return 'Enter the amount';
                if (value > widget.max + 0.004) {
                  return 'At most ${formatMoney(widget.max)}';
                }
                return null;
              },
              decoration: const InputDecoration(
                labelText: 'Amount refunded',
                prefixText: '₹ ',
              ),
            ),
            TextFormField(
              key: const ValueKey('refund-note'),
              controller: _note,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('refund-submit'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final note = _note.text.trim();
            Navigator.of(context).pop(
              (double.parse(_amount.text.trim()), note.isEmpty ? null : note),
            );
          },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
