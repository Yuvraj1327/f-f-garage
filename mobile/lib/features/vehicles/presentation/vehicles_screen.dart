import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/vehicle.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/vehicle_providers.dart';

/// The customer's saved two-wheelers: pick the one to service, add, edit or
/// remove. Tapping a vehicle selects it (it is then used for new bookings).
class VehiclesScreen extends ConsumerWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(vehiclesProvider);
    final selected = ref.watch(selectedVehicleProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My vehicles')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-vehicle'),
        onPressed: () => context.push(AppRoutes.vehicleNew),
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
      body: SafeArea(
        child: AsyncView<List<Vehicle>>(
          value: vehicles,
          loading: const ListSkeleton(count: 2),
          onRetry: () => ref.invalidate(vehiclesProvider),
          builder: (items) {
            if (items.isEmpty) {
              return RefreshIndicator(
                onRefresh: () => ref.refresh(vehiclesProvider.future),
                child: ListView(
                  children: const [
                    SizedBox(height: 80),
                    EmptyView(
                      icon: Icons.two_wheeler,
                      message: 'No vehicles saved yet.\n'
                          'Add your bike or scooter to book faster.',
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(vehiclesProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final vehicle in items)
                    _VehicleCard(
                      vehicle: vehicle,
                      selected: vehicle.id == selected?.id,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VehicleCard extends ConsumerWidget {
  const _VehicleCard({required this.vehicle, required this.selected});

  final Vehicle vehicle;
  final bool selected;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove vehicle?',
      message: '${vehicle.title} (${vehicle.registrationPretty}) will be '
          'removed from your saved vehicles. Past bookings keep their details.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(vehicleRepositoryProvider).delete(vehicle.id);
      ref.invalidate(vehiclesProvider);
      if (context.mounted) showSuccessSnack(context, 'Vehicle removed.');
    } catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      key: ValueKey('vehicle-${vehicle.id}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            ref.read(selectedVehicleIdProvider.notifier).select(vehicle.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                child: Icon(vehicle.type == VehicleType.bike
                    ? Icons.sports_motorsports_outlined
                    : Icons.electric_scooter_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vehicle.title, style: textTheme.titleMedium),
                    Text(
                      '${vehicle.make} ${vehicle.model} - '
                      '${vehicleLabel(vehicle.type)}',
                      style: textTheme.bodySmall,
                    ),
                    Text(vehicle.registrationPretty,
                        style: textTheme.labelLarge),
                  ],
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.check_circle,
                      color: scheme.primary, semanticLabel: 'Selected'),
                ),
              PopupMenuButton<String>(
                key: ValueKey('vehicle-menu-${vehicle.id}'),
                tooltip: 'Vehicle options',
                onSelected: (value) {
                  if (value == 'edit') {
                    context.push(AppRoutes.vehicleEdit(vehicle.id));
                  } else {
                    _remove(context, ref);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
