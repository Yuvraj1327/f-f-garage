import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/catalog.dart';
import '../../booking/presentation/cart_bar.dart';
import '../../booking/providers/booking_providers.dart';
import '../providers/catalog_providers.dart';
import 'service_card.dart';

/// One service in full: description, then each package with its price,
/// duration, what is included and what is not, the parts policy, the warranty
/// and any extra charges that may apply. "Add" puts it in the cart.
class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(browseServiceProvider(serviceId));
    return Scaffold(
      appBar: AppBar(title: Text(value.valueOrNull?.name ?? 'Service')),
      bottomNavigationBar: const CartBar(),
      body: SafeArea(
        child: AsyncView<GarageService>(
          value: value,
          onRetry: () => ref.invalidate(browseServiceProvider(serviceId)),
          builder: (service) {
            final packages = activePackages(service);
            final cheapest = packages.isEmpty
                ? null
                : packages.reduce((a, b) => a.price <= b.price ? a : b);
            final duration = cheapest?.estimatedDurationMinutes;
            final textTheme = Theme.of(context).textTheme;
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
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (duration != null)
                              Text(
                                'About ${formatDuration(duration)}',
                                key: const ValueKey('detail-duration'),
                              ),
                          ],
                        ),
                      ],
                      if (service.description != null) ...[
                        const SizedBox(height: 12),
                        Text(service.description!),
                      ],
                      const SizedBox(height: 16),
                      if (packages.length > 1)
                        Text('Choose an option', style: textTheme.titleMedium),
                      for (final package in packages)
                        _PackageCard(service: service, package: package),
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
          },
        ),
      ),
    );
  }
}

class _PackageCard extends ConsumerWidget {
  const _PackageCard({required this.service, required this.package});

  final GarageService service;
  final ServicePackage package;

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
            if (package.inclusions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text("What's included", style: textTheme.labelLarge),
              for (final item in package.inclusions)
                _Line(icon: Icons.check_circle_outline, text: item, color: scheme.primary),
            ],
            if (package.exclusions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text("What's not included", style: textTheme.labelLarge),
              for (final item in package.exclusions)
                _Line(icon: Icons.cancel_outlined, text: item, color: scheme.error),
            ],
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
            SizedBox(
              width: double.infinity,
              child: added
                  ? OutlinedButton.icon(
                      key: ValueKey('remove-${package.id}'),
                      onPressed: () =>
                          ref.read(bookingFlowProvider.notifier).reset(),
                      icon: const Icon(Icons.check),
                      label: const Text('Added - tap to remove'),
                    )
                  : FilledButton(
                      key: ValueKey('book-${package.id}'),
                      onPressed: () {
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
