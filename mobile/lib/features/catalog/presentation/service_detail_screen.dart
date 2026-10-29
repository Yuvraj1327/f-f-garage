import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/catalog.dart';
import '../../booking/presentation/cart_bar.dart';
import '../../booking/providers/booking_providers.dart';
import '../../support/providers/support_providers.dart';
import '../../vehicles/providers/vehicle_providers.dart';
import '../providers/catalog_providers.dart';
import 'service_card.dart';

/// One service in full: banner, price, duration, warranty, description, then
/// each package with what it includes (services and parts), what it does not,
/// the parts policy and extra charges. "Add" puts it in the cart.
class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(browseServiceProvider(serviceId));
    return Scaffold(
      appBar: AppBar(
        title: Text(value.valueOrNull?.name ?? 'Service'),
        actions: const [CartIconButton()],
      ),
      bottomNavigationBar: const CartBar(),
      body: SafeArea(
        child: AsyncView<GarageService>(
          value: value,
          onRetry: () => ref.invalidate(browseServiceProvider(serviceId)),
          builder: (service) => ServiceDetailView(service: service),
        ),
      ),
    );
  }
}

/// The body of the details screen. The admin's "Preview as customer" shows the
/// same widget; with [preview] set the Add buttons do nothing.
class ServiceDetailView extends ConsumerWidget {
  const ServiceDetailView({super.key, required this.service, this.preview = false});

  final GarageService service;
  final bool preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packages = preview ? service.packages : activePackages(service);
    final cheapest = packages.isEmpty
        ? null
        : packages.reduce((a, b) => a.price <= b.price ? a : b);
    final duration = cheapest?.estimatedDurationMinutes;
    final warranty = cheapest?.warrantyLabel;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final vehicle = preview ? null : ref.watch(selectedVehicleProvider);
    final fits = vehicle == null || service.supports(vehicle.make, vehicle.model);
    return ListView(
      children: [
        ServiceBanner(service: service),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${vehicleLabel(service.vehicleType)} - ${service.category}',
                style: textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                service.name,
                key: const ValueKey('detail-name'),
                style: textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (cheapest != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    Text(
                      '${packages.length > 1 ? 'From ' : ''}'
                      '${formatMoney(cheapest.price)}',
                      key: const ValueKey('detail-price'),
                      style: textTheme.titleLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (cheapest.hasDiscount)
                      Text(
                        formatMoney(cheapest.originalPrice!),
                        style: textTheme.bodyMedium?.copyWith(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    if (cheapest.discountLabel != null)
                      Text(
                        cheapest.discountLabel!,
                        style: textTheme.labelLarge?.copyWith(
                          color: AppColors.secondaryOnSoft,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (duration != null)
                      _InfoTile(
                        key: const ValueKey('detail-duration'),
                        icon: Icons.schedule,
                        label: 'Takes about',
                        value: formatDuration(duration),
                      ),
                    if (warranty != null)
                      _InfoTile(
                        key: const ValueKey('detail-warranty'),
                        icon: Icons.verified_outlined,
                        label: 'Warranty',
                        value: warranty,
                      ),
                    if (cheapest.repeatIntervalDays != null)
                      _InfoTile(
                        key: const ValueKey('detail-repeat'),
                        icon: Icons.repeat,
                        label: 'Repeat',
                        value: cheapest.repeatLabel,
                      ),
                  ],
                ),
              ],
              if (!fits) ...[
                const SizedBox(height: 12),
                Text(
                  'Not available for your ${vehicle!.make} ${vehicle.model}.',
                  key: const ValueKey('detail-unsupported'),
                  style: textTheme.bodyMedium?.copyWith(color: scheme.error),
                ),
              ],
              if (service.description != null) ...[
                const SizedBox(height: 16),
                Text('About this service', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(service.description!),
              ],
              if (service.partImageUrls.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Parts', style: textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    key: const ValueKey('part-images'),
                    scrollDirection: Axis.horizontal,
                    itemCount: service.partImageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        service.partImageUrls[i],
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 84,
                          height: 84,
                          child: Icon(Icons.build_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (packages.length > 1)
                Text('Choose an option', style: textTheme.titleMedium),
              for (final package in packages)
                _PackageCard(
                  service: service,
                  package: package,
                  preview: preview,
                  canAdd: fits,
                ),
              if (service.extraCharges.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ChargesBlock(
                  title: 'Extra charges that may apply',
                  charges: service.extraCharges,
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primaryOnSoft),
            const SizedBox(height: 4),
            Text(label, style: textTheme.labelSmall),
            Text(
              value,
              style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageCard extends ConsumerWidget {
  const _PackageCard({
    required this.service,
    required this.package,
    required this.preview,
    required this.canAdd,
  });

  final GarageService service;
  final ServicePackage package;
  final bool preview;
  final bool canAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final duration = package.estimatedDurationMinutes;
    final warranty = package.warrantyLabel;
    final flow = ref.watch(bookingFlowProvider);
    final added = flow.package?.id == package.id;
    return Card(
      key: ValueKey('package-${package.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(package.name, style: textTheme.titleMedium)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(package.price),
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
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
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                if (duration != null)
                  Text('About ${formatDuration(duration)}',
                      style: textTheme.bodySmall),
                if (warranty != null)
                  Text('$warranty warranty', style: textTheme.bodySmall),
              ],
            ),
            if (package.description != null) ...[
              const SizedBox(height: 8),
              Text(package.description!),
            ],
            _Section(
              title: 'Included Services',
              count: package.inclusions.length,
              icon: Icons.check_circle_outline,
              color: scheme.primary,
              items: package.inclusions,
            ),
            _Section(
              title: 'Included Parts',
              count: package.includedParts.length,
              icon: Icons.settings_outlined,
              color: scheme.primary,
              items: package.includedParts,
            ),
            _Section(
              title: 'Not Included',
              count: package.exclusions.length,
              icon: Icons.cancel_outlined,
              color: scheme.error,
              items: package.exclusions,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      package.partsNote ?? package.partsPolicy.description,
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            if (package.extraCharges.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ChargesBlock(
                title: 'Extra charges for this package',
                charges: package.extraCharges,
              ),
            ],
            const SizedBox(height: 12),
            _PayNow(package: package),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: preview
                  ? const OutlinedButton(
                      onPressed: null,
                      child: Text('Add (preview)'),
                    )
                  : added
                  ? OutlinedButton.icon(
                      key: ValueKey('remove-${package.id}'),
                      onPressed: () =>
                          ref.read(bookingFlowProvider.notifier).reset(),
                      icon: const Icon(Icons.check),
                      label: const Text('Added - tap to remove'),
                    )
                  : FilledButton(
                      key: ValueKey('book-${package.id}'),
                      onPressed: !canAdd
                          ? null
                          : () {
                        ref
                            .read(bookingFlowProvider.notifier)
                            .start(service, package);
                      },
                      child: Text('Add - ${formatMoney(package.price)}'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Pay now ₹60 / ₹240 after service". Only for showing: the server works out
/// the real amounts.
class _PayNow extends ConsumerWidget {
  const _PayNow({required this.package});

  final ServicePackage package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent =
        ref.watch(supportContactProvider).valueOrNull?.advancePercent ?? 20;
    final now = package.advanceFor(percent);
    final later = ((package.price - now) * 100).round() / 100;
    return Text(
      'Pay now ${formatMoney(now)} / ${formatMoney(later)} after service',
      key: ValueKey('pay-now-${package.id}'),
      style: Theme.of(context).textTheme.labelLarge,
    );
  }
}

/// A titled list ("Included Services (3)"), hidden when it is empty.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.items,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      key: ValueKey('section-$title'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('$title ($count)', style: Theme.of(context).textTheme.labelLarge),
        for (final item in items) _Line(icon: icon, text: item, color: color),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ChargesBlock extends StatelessWidget {
  const _ChargesBlock({required this.title, required this.charges});

  final String title;
  final List<ExtraCharge> charges;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.labelLarge),
        const SizedBox(height: 4),
        for (final charge in charges)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text('${charge.name} (${chargeTypeLabel(charge.chargeType)})'),
                ),
                Text(
                  charge.amount == null
                      ? 'At actuals'
                      : formatMoney(charge.amount!),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
