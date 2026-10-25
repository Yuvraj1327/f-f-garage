import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/dialogs.dart';
import '../../data/models/place.dart';
import '../../data/providers/data_providers.dart';
import 'map_providers.dart';
import 'map_view.dart';

/// A small map with a pin at [point], plus "Open in Maps" and (optionally)
/// "Directions" buttons. Without a Maps key for this platform the map is left
/// out and the coordinates are shown, so the buttons still work: nothing breaks
/// because maps are not configured.
class LocationMapCard extends ConsumerWidget {
  const LocationMapCard({
    super.key,
    required this.point,
    this.height = 160,
    this.showDirections = false,
  });

  final MapPoint point;
  final double height;

  /// True for the driver, who needs turn-by-turn directions.
  final bool showDirections;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(mapsAvailableProvider);
    final launcher = ref.read(contactLauncherProvider);
    final scheme = Theme.of(context).colorScheme;

    Future<void> open(Future<bool> Function() action) async {
      final opened = await action();
      if (!opened && context.mounted) {
        showSnack(
          context,
          "Couldn't open maps on this device. Location: ${point.asQuery}",
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available)
          Semantics(
            label: 'Map showing the service location',
            child: ClipRRect(
              key: const ValueKey('map-preview'),
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: height,
                child: ref.watch(mapViewBuilderProvider)(
                  context,
                  MapViewSpec(
                    center: point,
                    zoom: 16,
                    interactive: false,
                    marker: point,
                  ),
                ),
              ),
            ),
          )
        else
          Container(
            key: const ValueKey('map-fallback'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('Pinned location: ${point.asQuery}')),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('open-in-maps'),
              onPressed: () => open(() => launcher.map(point.asQuery)),
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open in Maps'),
            ),
            if (showDirections)
              TextButton.icon(
                key: const ValueKey('directions'),
                onPressed: () => open(() => launcher.directions(point.asQuery)),
                icon: const Icon(Icons.directions_outlined),
                label: const Text('Directions'),
              ),
          ],
        ),
      ],
    );
  }
}
