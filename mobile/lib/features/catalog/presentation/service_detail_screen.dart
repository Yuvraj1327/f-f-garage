import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/catalog.dart';
import '../../booking/providers/booking_providers.dart';
import '../providers/catalog_providers.dart';

/// One service with its packages, what each includes, and the extra charges
/// that may apply, and starts a booking.
class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(browseServiceProvider(serviceId));
    return Scaffold(
      appBar: AppBar(title: Text(value.valueOrNull?.name ?? 'Service')),
      body: SafeArea(
        child: AsyncView<GarageService>(
          value: value,
          onRetry: () => ref.invalidate(browseServiceProvider(serviceId)),
          builder: (service) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${vehicleLabel(service.vehicleType)} - ${service.category}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (service.description != null) ...[
                const SizedBox(height: 8),
                Text(service.description!),
              ],
              const SizedBox(height: 16),
              for (final package in service.packages)
                _PackageCard(service: service, package: package),
              if (service.extraCharges.isNotEmpty) ...[
                const SizedBox(height: 8),
                _ChargesBlock(
                  title: 'Extra charges that may apply',
                  charges: service.extraCharges,
                ),
              ],
            ],
          ),
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
    final duration = package.estimatedDurationMinutes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(package.name, style: textTheme.titleMedium)),
                Text(formatMoney(package.price), style: textTheme.titleMedium),
              ],
            ),
            if (duration != null)
              Text('About ${formatDuration(duration)}', style: textTheme.bodySmall),
            if (package.description != null) ...[
              const SizedBox(height: 8),
              Text(package.description!),
            ],
            if (package.inclusions.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in package.inclusions)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item)),
                    ],
                  ),
                ),
            ],
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
              child: FilledButton(
                key: ValueKey('book-${package.id}'),
                onPressed: () {
                  ref.read(bookingFlowProvider.notifier).start(service, package);
                  context.push(AppRoutes.bookAddress);
                },
                child: const Text('Book this package'),
              ),
            ),
          ],
        ),
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
