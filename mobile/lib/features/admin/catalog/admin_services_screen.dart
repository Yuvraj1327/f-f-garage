import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/service_icon.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// All services (bike and scooter), including inactive ones.
class AdminServicesScreen extends ConsumerStatefulWidget {
  const AdminServicesScreen({super.key});

  @override
  ConsumerState<AdminServicesScreen> createState() =>
      _AdminServicesScreenState();
}

class _AdminServicesScreenState extends ConsumerState<AdminServicesScreen> {
  VehicleType? _filter;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(adminServicesProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Services')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.adminServiceNew),
        icon: const Icon(Icons.add),
        label: const Text('Add service'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<VehicleType?>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: null, label: Text('All')),
                  ButtonSegment(value: VehicleType.bike, label: Text('Bike')),
                  ButtonSegment(
                    value: VehicleType.scooter,
                    label: Text('Scooter'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.first),
              ),
            ),
            Expanded(
              child: AsyncView<List<GarageService>>(
                value: services,
                onRetry: () => ref.invalidate(adminServicesProvider(_filter)),
                builder: (items) {
                  if (items.isEmpty) {
                    return const EmptyView(
                      message: 'No services yet. Tap "Add service" to create one.',
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(adminServicesProvider(_filter).future),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: items.length,
                      itemBuilder: (context, index) =>
                          _ServiceTile(service: items[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  const _ServiceTile({required this.service});

  final GarageService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final packageCount = service.packages.length;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.adminService(service.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              ServiceThumb(category: service.category, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(service.name, style: textTheme.titleMedium),
                        ),
                        if (!service.isActive) ...[
                          const SizedBox(width: 8),
                          const InactiveBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vehicleLabel(service.vehicleType)} - '
                      '${service.category} - '
                      '$packageCount ${packageCount == 1 ? 'package' : 'packages'}',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              ActiveSwitch(
                value: service.isActive,
                semanticLabel: '${service.name} active',
                onChanged: (value) async {
                  await ref
                      .read(catalogRepositoryProvider)
                      .updateService(service.id, {'is_active': value});
                  refreshCatalog(ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
