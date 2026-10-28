import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/billing.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../payment/presentation/payment_widgets.dart' show methodLabel;
import '../providers/booking_providers.dart';
import 'booking_widgets.dart';

/// The price of a booking. Once the server's bill has loaded it shows the full
/// breakdown (estimate, approved extras, advance, balance, receipts and
/// refunds); until then, or if it cannot be loaded, the simple price card.
class BillSection extends ConsumerWidget {
  const BillSection({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bill = ref.watch(billProvider(booking.id)).valueOrNull;
    if (bill == null) return PriceCard(booking: booking);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BillCard(bill: bill),
        if (bill.successfulPayments.isNotEmpty || bill.refunds.isNotEmpty)
          _ReceiptsCard(bill: bill),
      ],
    );
  }
}

/// The estimate as it was at booking time (also the fallback view).
class PriceCard extends StatelessWidget {
  const PriceCard({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Price',
      children: [
        SummaryRow(
          label: booking.packageName,
          value: formatMoney(booking.packagePrice),
        ),
        for (final charge in booking.chosenCharges)
          SummaryRow(label: charge.name, value: chargeAmountText(charge.amount)),
        if (booking.discountAmount > 0)
          SummaryRow(
            label: 'Coupon ${booking.couponCode ?? ''}'.trim(),
            value: '- ${formatMoney(booking.discountAmount)}',
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
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: bill.isFinal ? 'Final bill' : 'Bill so far',
      children: [
        SummaryRow(
          label: bill.packageName,
          value: formatMoney(bill.packagePrice),
        ),
        if (bill.addonsTotal > 0)
          SummaryRow(
            label: 'Add-ons',
            value: formatMoney(bill.addonsTotal),
          ),
        if (bill.discountAmount > 0)
          SummaryRow(
            label: 'Coupon ${bill.couponCode ?? ''}'.trim(),
            value: '- ${formatMoney(bill.discountAmount)}',
          ),
        SummaryRow(
          key: const ValueKey('bill-estimated'),
          label: 'Estimated total',
          value: formatMoney(bill.estimatedTotal),
        ),
        if (bill.approvedExtras.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Extra work you approved', style: textTheme.labelMedium),
          for (final extra in bill.approvedExtras)
            SummaryRow(label: extra.name, value: formatMoney(extra.amount)),
        ],
        const Divider(),
        SummaryRow(
          key: const ValueKey('bill-final'),
          label: bill.isFinal ? 'Final bill' : 'Total so far',
          value: formatMoney(bill.finalTotal),
          bold: true,
        ),
        if (bill.amountPaid > 0)
          SummaryRow(
            key: const ValueKey('bill-paid'),
            label: 'Paid',
            value: '- ${formatMoney(bill.amountPaid)}',
          ),
        if (bill.advancePaid == 0 && bill.advanceDue > 0)
          SummaryRow(
            label: 'Advance due at booking (${_percent(bill.advancePercent)}%)',
            value: formatMoney(bill.advanceDue),
          ),
        if (bill.status != BookingStatus.cancelled)
          SummaryRow(
            key: const ValueKey('bill-balance'),
            label: 'Balance',
            value: formatMoney(bill.balanceDue),
            bold: true,
          ),
        if (bill.refundedTotal > 0)
          SummaryRow(
            key: const ValueKey('bill-refunded'),
            label: 'Refunded to you',
            value: formatMoney(bill.refundedTotal),
          ),
        if (!bill.isFinal && bill.status != BookingStatus.cancelled) ...[
          const SizedBox(height: 8),
          Text(
            'Extra parts or repairs are added only if you approve them. '
            'The balance is paid after the service.',
            style: textTheme.bodySmall,
          ),
        ],
        if (bill.refundPolicy.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Refund policy', style: textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(bill.refundPolicy, style: textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

String _percent(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);

class _ReceiptsCard extends StatelessWidget {
  const _ReceiptsCard({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Receipts',
      children: [
        for (final payment in bill.successfulPayments)
          Padding(
            key: ValueKey('receipt-${payment.id}'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SummaryRow(
                  label: '${payment.kind.label} payment',
                  value: formatMoney(payment.amount),
                ),
                Text(
                  [
                    if (payment.method != null) methodLabel(payment.method!),
                    if (payment.transactionId != null) payment.transactionId!,
                    if (payment.receipt != null) 'Receipt ${payment.receipt}',
                    if (payment.paidAt != null) formatDateTime(payment.paidAt!),
                  ].join(' - '),
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        for (final refund in bill.refunds)
          Padding(
            key: ValueKey('refund-${refund.id}'),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SummaryRow(
                  label: 'Refund',
                  value: formatMoney(refund.amount),
                ),
                Text(
                  [
                    formatDateTime(refund.createdAt),
                    if (refund.note != null) refund.note!,
                  ].join(' - '),
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Your mechanic found extra work": each request with Approve and Decline.
/// Nothing is added to the bill unless the customer approves it.
class ExtraApprovals extends ConsumerStatefulWidget {
  const ExtraApprovals({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<ExtraApprovals> createState() => _ExtraApprovalsState();
}

class _ExtraApprovalsState extends ConsumerState<ExtraApprovals> {
  String? _busyId;

  Future<void> _decide(ExtraRequest extra, {required bool approve}) async {
    if (_busyId != null) return;
    if (approve) {
      final ok = await confirmAction(
        context,
        title: 'Approve extra work?',
        message: '${extra.name} for ${formatMoney(extra.amount)} will be added '
            'to your final bill.',
        confirmLabel: 'Approve',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busyId = extra.id);
    try {
      final repo = ref.read(billingRepositoryProvider);
      if (approve) {
        await repo.approve(widget.bookingId, extra.id);
      } else {
        await repo.decline(widget.bookingId, extra.id);
      }
      if (!mounted) return;
      refreshBookings(ref, bookingId: widget.bookingId);
      showSuccessSnack(
        context,
        approve ? 'Approved. Added to your bill.' : 'Declined. Nothing added.',
      );
    } catch (error) {
      if (!mounted) return;
      refreshBookings(ref, bookingId: widget.bookingId);
      showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = ref.watch(billProvider(widget.bookingId)).valueOrNull;
    if (bill == null || bill.pendingExtras.isEmpty) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('extra-approvals'),
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build_circle_outlined,
                    color: scheme.onTertiaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Extra work needs your approval',
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Our mechanic found something during the service. It is added '
              'to your bill only if you approve it.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onTertiaryContainer,
              ),
            ),
            for (final extra in bill.pendingExtras) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(extra.name, style: textTheme.titleSmall),
                        if (extra.description != null)
                          Text(extra.description!, style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(extra.amount),
                    style: textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('decline-${extra.id}'),
                      onPressed: _busyId == null
                          ? () => _decide(extra, approve: false)
                          : null,
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: ValueKey('approve-${extra.id}'),
                      onPressed: _busyId == null
                          ? () => _decide(extra, approve: true)
                          : null,
                      child: _busyId == extra.id
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Approve'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
