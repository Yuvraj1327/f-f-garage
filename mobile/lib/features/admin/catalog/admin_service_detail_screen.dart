import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// One service with its packages and extra charges, and the buttons to manage
/// them.
class AdminServiceDetailScreen extends ConsumerWidget {
  const AdminServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminServiceProvider(serviceId));

    return Scaffold(
      appBar: AppBar(
        title: Text(value.valueOrNull?.name ?? 'Service'),
        actions: [
          if (value.hasValue)
            IconButton(
              tooltip: 'Edit service',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  context.push(AppRoutes.adminServiceEdit(serviceId)),
            ),
        ],
      ),
      body: SafeArea(
        child: AsyncView<GarageService>(
          value: value,
          onRetry: () => ref.invalidate(adminServiceProvider(serviceId)),
          builder: (service) => RefreshIndicator(
            onRefresh: () => ref.refresh(adminServiceProvider(serviceId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Header(service: service),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: 'Packages',
                  addLabel: 'Add package',
                  onAdd: () => context.push(
                    AppRoutes.adminPackage(service.id, AppRoutes.newItem),
                  ),
                ),
                if (service.packages.isEmpty)
                  const _Hint('No packages yet. Customers can only book a '
                      'service that has an active package.'),
                for (final package in service.packages)
                  _PackageCard(service: service, package: package),
                const SizedBox(height: 16),
                _SectionTitle(
                  title: 'Extra charges for every package',
                  addLabel: 'Add charge',
                  onAdd: () => context.push(
                    AppRoutes.adminCharge(service.id, AppRoutes.newItem),
                  ),
                ),
                if (service.extraCharges.isEmpty)
                  const _Hint('None. Charges for one package are added from '
                      'that package.'),
                for (final charge in service.extraCharges)
                  _ChargeTile(serviceId: service.id, charge: charge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.service});

  final GarageService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vehicleLabel(service.vehicleType)} - ${service.category}',
              style: textTheme.labelLarge,
            ),
            if (service.description != null) ...[
              const SizedBox(height: 8),
              Text(service.description!),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Visible to customers')),
                ActiveSwitch(
                  value: service.isActive,
                  semanticLabel: 'Service active',
                  onChanged: (value) async {
                    await ref
                        .read(catalogRepositoryProvider)
                        .updateService(service.id, {'is_active': value});
                    refreshCatalog(ref);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.addLabel,
    required this.onAdd,
  });

  final String title;
  final String addLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
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
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(package.name, style: textTheme.titleSmall),
                      if (!package.isActive) const InactiveBadge(),
                    ],
                  ),
                ),
                Text(formatMoney(package.price), style: textTheme.titleSmall),
                IconButton(
                  tooltip: 'Edit package',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push(
                    AppRoutes.adminPackage(service.id, package.id),
                  ),
                ),
                ActiveSwitch(
                  value: package.isActive,
                  semanticLabel: '${package.name} active',
                  onChanged: (value) async {
                    await ref
                        .read(catalogRepositoryProvider)
                        .updatePackage(package.id, {'is_active': value});
                    refreshCatalog(ref);
                  },
                ),
              ],
            ),
            if (duration != null)
              Text('About ${formatDuration(duration)}', style: textTheme.bodySmall),
            if (package.inclusions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in package.inclusions)
                    Chip(
                      label: Text(item),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (package.extraCharges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Extra charges for this package', style: textTheme.labelMedium),
              for (final charge in package.extraCharges)
                _ChargeTile(serviceId: service.id, charge: charge, dense: true),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.push(
                  '${AppRoutes.adminCharge(service.id, AppRoutes.newItem)}'
                  '?package=${package.id}',
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add charge for this package'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChargeTile extends StatelessWidget {
  const _ChargeTile({
    required this.serviceId,
    required this.charge,
    this.dense = false,
  });

  final String serviceId;
  final ExtraCharge charge;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final amount = charge.amount;
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          Flexible(child: Text(charge.name)),
          if (!charge.isActive) ...[
            const SizedBox(width: 8),
            const InactiveBadge(),
          ],
        ],
      ),
      subtitle: Text(chargeTypeLabel(charge.chargeType)),
      trailing: Text(amount == null ? 'At actuals' : formatMoney(amount)),
      onTap: () => context.push(AppRoutes.adminCharge(serviceId, charge.id)),
    );
  }
}
