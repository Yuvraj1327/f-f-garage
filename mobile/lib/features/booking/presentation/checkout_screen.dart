import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/booking.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart' show MessageBanner;
import '../../maps/location_map_card.dart';
import '../../support/providers/support_providers.dart';
import '../../vehicles/presentation/vehicle_switcher.dart';
import '../../vehicles/providers/vehicle_providers.dart';
import '../providers/booking_providers.dart';
import 'booking_widgets.dart';
import 'schedule_picker.dart';

/// Checkout, on one page: the service location (map and address), the vehicle,
/// doorstep service, when (as soon as possible or a chosen time), the item,
/// instructions, an optional coupon and the billing breakdown. The server
/// prices everything; the total shown here is sent back only as
/// `expected_total` so a changed price is refused rather than charged.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _busy = false;
  bool _applying = false;
  String? _error;
  String? _couponError;
  late final TextEditingController _notes;
  final TextEditingController _coupon = TextEditingController();

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: ref.read(bookingFlowProvider).notes);
  }

  @override
  void dispose() {
    _notes.dispose();
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _applyCoupon(BookingFlowState flow) async {
    final code = _coupon.text.trim();
    final package = flow.package;
    if (code.isEmpty || package == null || _applying) return;
    setState(() {
      _applying = true;
      _couponError = null;
    });
    try {
      final quote = await ref.read(bookingRepositoryProvider).quote(
            package.id,
            extraChargeIds: flow.extraChargeIds.toList()..sort(),
            couponCode: code,
          );
      if (!mounted) return;
      ref
          .read(bookingFlowProvider.notifier)
          .setCoupon(quote.couponCode ?? code.toUpperCase());
      _coupon.clear();
      setState(() => _applying = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _couponError = errorMessage(error);
      });
    }
  }

  Future<void> _confirm(BookingQuote quote, BookingFlowState flow) async {
    if (_busy) return;
    final address = flow.address;
    final schedule = flow.schedule;
    if (address == null || schedule == null) return;
    final vehicle = pickVehicle(
      ref.read(vehiclesProvider).valueOrNull ?? const [],
      ref.read(selectedVehicleProvider),
      quote.vehicleType,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final booking = await ref.read(bookingRepositoryProvider).create(
            NewBooking(
              packageId: quote.packageId,
              vehicleId: vehicle?.id,
              extraChargeIds: flow.extraChargeIds.toList()..sort(),
              couponCode: flow.couponCode,
              pincode: address.pincode,
              addressLine: address.addressLine,
              landmark: address.landmark,
              latitude: address.latitude,
              longitude: address.longitude,
              date: schedule.date,
              timeSlotId: schedule.slotId,
              notes: _notes.text,
              expectedTotal: quote.serverTotal,
              clientRequestId: flow.requestId,
            ),
          );
      if (!mounted) return;
      ref.read(bookingFlowProvider.notifier).reset();
      refreshBookings(ref);
      context.go('${AppRoutes.booking(booking.id)}?created=1');
    } catch (error) {
      if (!mounted) return;
      // A price or availability change: reload so the customer confirms the
      // up-to-date figures.
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
    if (!flow.hasPackage || package == null) {
      return const NothingSelectedView();
    }
    final key = QuoteKey(package.id, flow.extraChargeIds, flow.couponCode);
    // A coupon that stops working (used up, expired) is dropped with a note.
    ref.listen(checkoutQuoteProvider(key), (previous, next) {
      if (next.hasError && flow.couponCode != null) {
        ref.read(bookingFlowProvider.notifier).setCoupon(null);
        setState(() => _couponError = errorMessage(next.error!));
      }
    });
    // "Instant" follows the earliest open slot.
    final days = ref.watch(bookableDaysProvider).valueOrNull;
    if (flow.instant && days != null) {
      final earliest = earliestSlot(days);
      if (earliest != null &&
          (flow.schedule?.slotId != earliest.slotId ||
              flow.schedule?.date != earliest.date)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(bookingFlowProvider).instant) {
            ref.read(bookingFlowProvider.notifier).setSchedule(earliest);
          }
        });
      }
    }
    final quote = ref.watch(checkoutQuoteProvider(key));
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: AsyncView<BookingQuote>(
          value: quote,
          onRetry: () => ref.invalidate(checkoutQuoteProvider(key)),
          builder: (data) => _Content(
            quote: data,
            flow: flow,
            notes: _notes,
            coupon: _coupon,
            busy: _busy,
            applying: _applying,
            error: _error,
            couponError: _couponError,
            hasSlots: days == null ? null : earliestSlot(days) != null,
            onApplyCoupon: () => _applyCoupon(flow),
            onConfirm: () => _confirm(data, flow),
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
    required this.coupon,
    required this.busy,
    required this.applying,
    required this.error,
    required this.couponError,
    required this.hasSlots,
    required this.onApplyCoupon,
    required this.onConfirm,
  });

  final BookingQuote quote;
  final BookingFlowState flow;
  final TextEditingController notes;
  final TextEditingController coupon;
  final bool busy;
  final bool applying;
  final String? error;
  final String? couponError;

  /// Null while the availability loads.
  final bool? hasSlots;
  final VoidCallback onApplyCoupon;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final selectable = quote.charges.where((c) => c.selectable).toList();
    final atActuals = quote.charges.where((c) => !c.selectable).toList();
    final package = flow.package!;
    final service = flow.service!;
    final ready = flow.address != null && flow.schedule != null;
    final duration = quote.durationMinutes;
    final refundPolicy =
        ref.watch(supportContactProvider).valueOrNull?.refundPolicy ?? '';
    final advance = quote.serverAdvance;
    final total = quote.serverTotal;
    return Column(
      children: [
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null) MessageBanner(message: error!),
              _AddressCard(flow: flow, busy: busy),
              SectionCard(
                title: 'Your vehicle',
                children: const [VehicleSwitcher(showTypeToggle: false)],
              ),
              SectionCard(
                title: 'Service type',
                children: [
                  ListTile(
                    key: const ValueKey('doorstep'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.home_repair_service_outlined),
                    title: const Text('Doorstep service'),
                    subtitle: const Text(
                      'Our mechanic comes to your location.',
                    ),
                    trailing: Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              _WhenCard(flow: flow, busy: busy, hasSlots: hasSlots),
              SectionCard(
                title: 'Items',
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(service.name, style: textTheme.titleMedium),
                            Text(
                              '${package.name}'
                              '${duration == null ? '' : ' - about ${formatDuration(duration)}'}',
                              style: textTheme.bodySmall,
                            ),
                            if (package.warrantyLabel != null)
                              Text(
                                '${package.warrantyLabel} warranty',
                                style: textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatMoney(quote.packagePrice),
                            style: textTheme.titleMedium,
                          ),
                          if (package.hasDiscount)
                            Text(
                              formatMoney(package.originalPrice!),
                              style: textTheme.bodySmall?.copyWith(
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('remove-item'),
                      onPressed: busy
                          ? null
                          : () {
                              ref.read(bookingFlowProvider.notifier).reset();
                              context.go(AppRoutes.browseServices);
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove'),
                    ),
                  ),
                  if (package.inclusions.isNotEmpty) ...[
                    InclusionList(items: package.inclusions),
                  ],
                  if (selectable.isNotEmpty) ...[
                    const Divider(),
                    Text('Add-ons (optional)', style: textTheme.labelLarge),
                    for (final charge in selectable)
                      CheckboxListTile(
                        key: ValueKey('addon-${charge.id}'),
                        contentPadding: EdgeInsets.zero,
                        value: flow.extraChargeIds.contains(charge.id),
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
                  if (atActuals.isNotEmpty) ...[
                    const Divider(),
                    Text('May apply on the day', style: textTheme.labelLarge),
                    for (final charge in atActuals)
                      SummaryRow(
                        label: '${charge.name} (${chargeTypeLabel(charge.chargeType)})',
                        value: chargeAmountText(charge.amount),
                      ),
                    Text(
                      'Not in the total. Charged only if needed, and only '
                      'after you approve it.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              SectionCard(
                title: 'Instructions for the mechanic (optional)',
                children: [
                  TextField(
                    key: const ValueKey('checkout-notes'),
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
              _CouponCard(
                applied: flow.couponCode,
                discount: quote.discountAmount,
                controller: coupon,
                applying: applying,
                busy: busy,
                error: couponError,
                onApply: onApplyCoupon,
                onRemove: () =>
                    ref.read(bookingFlowProvider.notifier).setCoupon(null),
              ),
              SectionCard(
                title: 'Billing details',
                children: [
                  SummaryRow(
                    label: quote.packageName,
                    value: formatMoney(quote.packagePrice),
                  ),
                  for (final charge in selectable)
                    if (flow.extraChargeIds.contains(charge.id))
                      SummaryRow(
                        label: charge.name,
                        value: chargeAmountText(charge.amount),
                      ),
                  if (quote.discountAmount > 0)
                    SummaryRow(
                      label: 'Coupon ${quote.couponCode ?? ''}'.trim(),
                      value: '- ${formatMoney(quote.discountAmount)}',
                    ),
                  const Divider(),
                  SummaryRow(
                    key: const ValueKey('estimated-total'),
                    label: 'Estimated total',
                    value: formatMoney(total),
                    bold: true,
                  ),
                  if (advance > 0) ...[
                    SummaryRow(
                      key: const ValueKey('advance-now'),
                      label:
                          'Pay now (${quote.advancePercent.toStringAsFixed(0)}% advance)',
                      value: formatMoney(advance),
                    ),
                    SummaryRow(
                      label: 'Pay after the service',
                      value: formatMoney(total - advance),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Extra parts or repairs found during the service are '
                    'added only after you approve them. The final bill is '
                    'the estimate plus anything you approved.',
                    style: textTheme.bodySmall,
                  ),
                  if (package.partsNote != null ||
                      package.partsPolicy.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      package.partsNote ?? package.partsPolicy.description,
                      style: textTheme.bodySmall,
                    ),
                  ],
                  if (refundPolicy.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Refund policy', style: textTheme.labelMedium),
                    Text(refundPolicy, style: textTheme.bodySmall),
                  ],
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
              key: const ValueKey('confirm-booking'),
              onPressed: busy || !ready ? null : onConfirm,
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      !ready
                          ? (flow.address == null
                              ? 'Add your location to continue'
                              : 'Choose a time to continue')
                          : (advance > 0
                              ? 'Confirm and pay ${formatMoney(advance)}'
                              : 'Confirm booking - ${formatMoney(total)}'),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Where the mechanic will come: map with the pin, the address and a way to
/// confirm or change it.
class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.flow, required this.busy});

  final BookingFlowState flow;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final address = flow.address;
    final textTheme = Theme.of(context).textTheme;
    void change() => context.push('${AppRoutes.bookAddress}?pick=1');
    if (address == null) {
      return SectionCard(
        title: 'Service location',
        children: [
          const Text('Where should we come? Add the address and pin it on the map.'),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('add-address'),
            onPressed: busy ? null : change,
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Add location'),
          ),
        ],
      );
    }
    return SectionCard(
      title: 'Service location',
      children: [
        if (address.point != null) ...[
          LocationMapCard(point: address.point!, height: 150),
          const SizedBox(height: 8),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(address.addressLine, key: const ValueKey('checkout-address')),
                  if (address.landmark != null)
                    Text(address.landmark!, style: textTheme.bodySmall),
                  Text(
                    '${address.areaName.isEmpty ? '' : '${address.areaName}, '}'
                    '${address.city} ${address.pincode}',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              key: const ValueKey('change-address'),
              onPressed: busy ? null : change,
              child: const Text('Change'),
            ),
          ],
        ),
      ],
    );
  }
}

/// As soon as possible, or a date and time the customer picks.
class _WhenCard extends ConsumerWidget {
  const _WhenCard({
    required this.flow,
    required this.busy,
    required this.hasSlots,
  });

  final BookingFlowState flow;
  final bool busy;
  final bool? hasSlots;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(bookingFlowProvider.notifier);
    final schedule = flow.schedule;
    return SectionCard(
      title: 'When',
      children: [
        SegmentedButton<bool>(
          key: const ValueKey('when-toggle'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Instant'),
              icon: Icon(Icons.bolt),
            ),
            ButtonSegment(
              value: false,
              label: Text('Schedule'),
              icon: Icon(Icons.event),
            ),
          ],
          selected: {flow.instant},
          onSelectionChanged:
              busy ? null : (value) => controller.setInstant(value.first),
        ),
        const SizedBox(height: 12),
        if (flow.instant) ...[
          if (hasSlots == null)
            const Text('Finding the earliest available time...')
          else if (hasSlots == false)
            const Text(
              'No time is open right now. Try again later.',
              key: ValueKey('no-instant-slot'),
            )
          else if (schedule != null) ...[
            Text(
              'Earliest available: ${formatDate(schedule.date)}, '
              '${schedule.timeLabel}',
              key: const ValueKey('instant-slot'),
            ),
            const SizedBox(height: 4),
            Text(
              'The mechanic arrives within this time window.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ] else
          SchedulePicker(
            selected: schedule,
            onChanged: controller.setSchedule,
          ),
      ],
    );
  }
}

class _CouponCard extends StatelessWidget {
  const _CouponCard({
    required this.applied,
    required this.discount,
    required this.controller,
    required this.applying,
    required this.busy,
    required this.error,
    required this.onApply,
    required this.onRemove,
  });

  final String? applied;
  final double discount;
  final TextEditingController controller;
  final bool applying;
  final bool busy;
  final String? error;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: 'Coupon (optional)',
      children: [
        if (applied != null)
          ListTile(
            key: const ValueKey('coupon-applied'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.local_offer, color: scheme.primary),
            title: Text('$applied applied'),
            subtitle: Text('You save ${formatMoney(discount)}'),
            trailing: TextButton(
              key: const ValueKey('coupon-remove'),
              onPressed: busy ? null : onRemove,
              child: const Text('Remove'),
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('coupon-field'),
                  controller: controller,
                  enabled: !busy && !applying,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onApply(),
                  decoration: InputDecoration(
                    hintText: 'Enter coupon code',
                    errorText: error,
                    errorMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                  key: const ValueKey('coupon-apply'),
                  style: FilledButton.styleFrom(minimumSize: const Size(88, 48)),
                  onPressed: busy || applying ? null : onApply,
                  child: applying
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Apply'),
                ),
              ),
            ],
          ),
        if (applied != null && error != null)
          Text(error!, style: TextStyle(color: scheme.error)),
      ],
    );
  }
}
