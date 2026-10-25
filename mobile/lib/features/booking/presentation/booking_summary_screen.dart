import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/booking.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart' show MessageBanner;
import '../providers/booking_providers.dart';
import '../../maps/location_map_card.dart';
import 'booking_widgets.dart';

/// Step 3 of booking: review everything, tick optional add-ons, confirm.
///
/// Prices come from the server (`/bookings/quote`). The total shown here is
/// sent back only as `expected_total`; the server recomputes the price itself
/// and refuses the booking if it no longer matches.
class BookingSummaryScreen extends ConsumerStatefulWidget {
  const BookingSummaryScreen({super.key});

  @override
  ConsumerState<BookingSummaryScreen> createState() =>
      _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends ConsumerState<BookingSummaryScreen> {
  bool _busy = false;
  String? _error;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: ref.read(bookingFlowProvider).notes);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _confirm(BookingQuote quote) async {
    if (_busy) return;
    final flow = ref.read(bookingFlowProvider);
    final address = flow.address;
    final schedule = flow.schedule;
    if (address == null || schedule == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await ref.read(bookingRepositoryProvider).create(
            NewBooking(
              packageId: quote.packageId,
              extraChargeIds: flow.extraChargeIds.toList()..sort(),
              pincode: address.pincode,
              addressLine: address.addressLine,
              landmark: address.landmark,
              latitude: address.latitude,
              longitude: address.longitude,
              date: schedule.date,
              timeSlotId: schedule.slotId,
              notes: _notes.text,
              expectedTotal: quote.totalFor(flow.extraChargeIds),
              clientRequestId: flow.requestId,
            ),
          );
      if (!mounted) return;
      ref.read(bookingFlowProvider.notifier).reset();
      refreshBookings(ref);
      context.go('${AppRoutes.booking(booking.id)}?created=1');
    } catch (error) {
      if (!mounted) return;
      // A price or availability change: reload the summary so the customer
      // confirms the up-to-date figures.
      ref.invalidate(bookingQuoteProvider(quote.packageId));
      ref.invalidate(bookableDaysProvider);
      setState(() {
        _busy = false;
        _error = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(bookingFlowProvider);
    final package = flow.package;
    if (!flow.isComplete || package == null) {
      return const NothingSelectedView();
    }
    final quote = ref.watch(bookingQuoteProvider(package.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Review your booking')),
      body: SafeArea(
        child: AsyncView<BookingQuote>(
          value: quote,
          onRetry: () => ref.invalidate(bookingQuoteProvider(package.id)),
          builder: (data) => _Content(
            quote: data,
            flow: flow,
            notes: _notes,
            busy: _busy,
            error: _error,
            onConfirm: () => _confirm(data),
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.quote,
    required this.flow,
    required this.notes,
    required this.busy,
    required this.error,
    required this.onConfirm,
  });

  final BookingQuote quote;
  final BookingFlowState flow;
  final TextEditingController notes;
  final bool busy;
  final String? error;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = flow.address!;
    final schedule = flow.schedule!;
    final chosen = flow.extraChargeIds;
    final selectable = quote.charges.where((c) => c.selectable).toList();
    final atActuals = quote.charges.where((c) => !c.selectable).toList();
    final total = quote.totalFor(chosen);
    final duration = quote.durationMinutes;
    return Column(
      children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null) MessageBanner(message: error!),
              SectionCard(
                title: 'Service',
                children: [
                  Text(
                    '${quote.serviceName} - ${quote.packageName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${vehicleLabel(quote.vehicleType)}'
                    '${duration == null ? '' : ' - about ${formatDuration(duration)}'}',
                  ),
                  if (quote.inclusions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InclusionList(items: quote.inclusions),
                  ],
                ],
              ),
              SectionCard(
                title: 'Visit',
                children: [
                  Text(formatDate(schedule.date)),
                  Text(schedule.timeLabel),
                  const SizedBox(height: 8),
                  Text(address.addressLine),
                  if (address.landmark != null) Text(address.landmark!),
                  Text('${address.areaName}, ${address.city} ${address.pincode}'),
                  if (address.point != null) ...[
                    const SizedBox(height: 8),
                    LocationMapCard(point: address.point!, height: 140),
                  ],
                ],
              ),
              if (selectable.isNotEmpty)
                SectionCard(
                  title: 'Add-ons (optional)',
                  children: [
                    for (final charge in selectable)
                      CheckboxListTile(
                        key: ValueKey('addon-${charge.id}'),
                        contentPadding: EdgeInsets.zero,
                        value: chosen.contains(charge.id),
                        onChanged: busy
                            ? null
                            : (value) => ref
                                .read(bookingFlowProvider.notifier)
                                .setExtraCharge(charge.id, value ?? false),
                        title: Text(charge.name),
                        subtitle: Text(chargeTypeLabel(charge.chargeType)),
                        secondary: Text(chargeAmountText(charge.amount)),
                      ),
                  ],
                ),
              if (atActuals.isNotEmpty)
                SectionCard(
                  title: 'May apply on the day',
                  children: [
                    for (final charge in atActuals)
                      SummaryRow(
                        label: '${charge.name} (${chargeTypeLabel(charge.chargeType)})',
                        value: chargeAmountText(charge.amount),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Not included in the total. Charged only if needed, '
                      'at actual cost.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              SectionCard(
                title: 'Notes for the driver (optional)',
                children: [
                  TextField(
                    controller: notes,
                    enabled: !busy,
                    minLines: 1,
                    maxLines: 3,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (value) =>
                        ref.read(bookingFlowProvider.notifier).setNotes(value),
                    decoration: const InputDecoration(
                      hintText: 'Gate code, where the vehicle is parked...',
                    ),
                  ),
                ],
              ),
              SectionCard(
                title: 'Price',
                children: [
                  SummaryRow(
                    label: quote.packageName,
                    value: formatMoney(quote.packagePrice),
                  ),
                  for (final charge in selectable)
                    if (chosen.contains(charge.id))
                      SummaryRow(
                        label: charge.name,
                        value: chargeAmountText(charge.amount),
                      ),
                  const Divider(),
                  SummaryRow(label: 'Total', value: formatMoney(total), bold: true),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onConfirm,
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Confirm booking - ${formatMoney(total)}'),
            ),
          ),
        ),
      ],
    );
  }
}
