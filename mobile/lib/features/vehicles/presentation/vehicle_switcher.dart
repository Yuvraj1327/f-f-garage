import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/vehicle.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../providers/vehicle_providers.dart';

/// "Your vehicle" as a dropdown: shows the selected vehicle and opens a sheet
/// to switch to another saved one or add a new one. Without any saved vehicle
/// it offers a Bike / Scooter toggle so services can still be browsed.
class VehicleSwitcher extends ConsumerWidget {
  const VehicleSwitcher({super.key, this.showTypeToggle = true});

  /// Show the Bike / Scooter toggle when there is no saved vehicle.
  final bool showTypeToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(vehiclesProvider);
    final selected = ref.watch(selectedVehicleProvider);
    final type = ref.watch(catalogVehicleTypeProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final loaded = vehicles.hasValue;
    final none = loaded && (vehicles.value ?? const []).isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            key: const ValueKey('vehicle-switcher'),
            borderRadius: BorderRadius.circular(14),
            onTap: () => _open(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.two_wheeler, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected != null
                              ? selected.title
                              : (none ? 'Add your vehicle' : 'Select vehicle'),
                          style: textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          selected != null
                              ? '${selected.registrationPretty} - '
                                  '${vehicleLabel(selected.type)}'
                              : (loaded
                                  ? 'Showing ${vehicleLabel(type).toLowerCase()} services'
                                  : 'Loading your vehicles...'),
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
        ),
        if (showTypeToggle && none) ...[
          const SizedBox(height: 8),
          SegmentedButton<VehicleType>(
            key: const ValueKey('vehicle-type-toggle'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: VehicleType.scooter,
                label: Text('Scooter'),
                icon: Icon(Icons.electric_scooter),
              ),
              ButtonSegment(
                value: VehicleType.bike,
                label: Text('Bike'),
                icon: Icon(Icons.two_wheeler),
              ),
            ],
            selected: {type},
            onSelectionChanged: (value) => ref
                .read(catalogTypeOverrideProvider.notifier)
                .state = value.first,
          ),
        ],
      ],
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => const _VehicleSheet(),
    );
  }
}

class _VehicleSheet extends ConsumerWidget {
  const _VehicleSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicles = ref.watch(vehiclesProvider).valueOrNull ?? const <Vehicle>[];
    final selected = ref.watch(selectedVehicleProvider);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Choose your vehicle',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final vehicle in vehicles)
              RadioListTile<String>(
                key: ValueKey('switch-${vehicle.id}'),
                contentPadding: EdgeInsets.zero,
                value: vehicle.id,
                groupValue: selected?.id,
                title: Text(vehicle.title),
                subtitle: Text(
                  '${vehicle.registrationPretty} - ${vehicleLabel(vehicle.type)}',
                ),
                secondary: const Icon(Icons.two_wheeler),
                onChanged: (_) async {
                  ref.read(catalogTypeOverrideProvider.notifier).state = null;
                  await ref
                      .read(selectedVehicleIdProvider.notifier)
                      .select(vehicle.id);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ListTile(
              key: const ValueKey('switcher-add-vehicle'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Add another vehicle'),
              onTap: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.vehicleNew);
              },
            ),
          ],
        ),
      ),
    );
  }
}
