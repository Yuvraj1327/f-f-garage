import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../data/models/place.dart';
import '../../../data/services/location_service.dart';
import '../../maps/map_providers.dart';
import '../../maps/map_view.dart';
import '../providers/home_location.dart';

/// The location-first part of Home: why we want the location (first visit), the
/// current address on a map with a pin, whether the garage services it, and a
/// way to choose another place. Without location the customer picks on the map
/// or uses the PIN-code check below; nothing forces GPS on.
class HomeLocationCard extends ConsumerWidget {
  const HomeLocationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(homeLocationProvider);
    switch (state.phase) {
      case HomeLocationPhase.ask:
        return const _AskCard();
      case HomeLocationPhase.loading:
        return const _Frame(
          child: ListTile(
            leading: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            title: Text('Finding your location...'),
          ),
        );
      case HomeLocationPhase.found:
        return _FoundCard(state: state);
      case HomeLocationPhase.declined:
        return _DeclinedCard(problem: state.problem);
    }
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        key: const ValueKey('home-location'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _AskCard extends ConsumerWidget {
  const _AskCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = ref.read(homeLocationProvider.notifier);
    return _Frame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.primary,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Find service near you',
                      style: textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Allow location so we can show your address on the map and check '
              'that our mechanics can reach you. It is used only while you use '
              'the app, and you can choose a place on the map or enter a PIN '
              'code instead.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('allow-location'),
                    onPressed: controller.allow,
                    child: const Text('Allow location'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey('skip-location'),
                  onPressed: controller.skip,
                  child: const Text('Not now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeclinedCard extends ConsumerWidget {
  const _DeclinedCard({this.problem});

  final LocationProblem? problem;

  String get _message {
    switch (problem) {
      case LocationProblem.servicesOff:
        return 'Location is switched off on this phone.';
      case LocationProblem.denied:
      case LocationProblem.deniedForever:
        return 'Location access is off for this app.';
      case LocationProblem.timeout:
        return "We couldn't get a location fix.";
      case LocationProblem.unavailable:
        return 'Location is not available here.';
      case null:
        return 'Tell us where to service your vehicle.';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return _Frame(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_off_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(_message, style: textTheme.titleSmall)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a place on the map or enter your PIN code below. '
              'You can turn location on whenever you like.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  key: const ValueKey('choose-on-map'),
                  onPressed: () => _pick(context, ref, null),
                  child: const Text('Choose on map'),
                ),
                OutlinedButton(
                  key: const ValueKey('use-current-location'),
                  onPressed: () =>
                      ref.read(homeLocationProvider.notifier).useCurrent(),
                  child: const Text('Use my location'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pick(BuildContext context, WidgetRef ref, MapPoint? from) async {
  final picked = await context.push<PickedLocation>(
    AppRoutes.pickLocation,
    extra: from,
  );
  if (picked != null) {
    ref.read(homeLocationProvider.notifier).picked(picked);
  }
}

class _FoundCard extends ConsumerWidget {
  const _FoundCard({required this.state});

  final HomeLocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final point = state.point!;
    final place = state.place;
    final mapsOn = ref.watch(mapsAvailableProvider);
    final serviceable = place?.serviceable;
    return _Frame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mapsOn)
            // A preview: tapping opens the full map, where the pin can be moved.
            // (A pannable map inside a scrolling page would trap the scroll.)
            GestureDetector(
              key: const ValueKey('home-map'),
              onTap: () => _pick(context, ref, point),
              child: SizedBox(
                height: 150,
                child: IgnorePointer(
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
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(Icons.location_on, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place?.formattedAddress ??
                            'Pinned location (${point.asQuery})',
                        key: const ValueKey('home-address'),
                        style: textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (serviceable != null)
                        Text(
                          serviceable
                              ? 'We service this area'
                              : "We don't service this area yet"
                                  '${place?.pincode == null ? '' : ' (${place!.pincode})'}',
                          key: const ValueKey('home-serviceable'),
                          style: textTheme.bodySmall?.copyWith(
                            color: serviceable
                                ? scheme.secondary
                                : scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  key: const ValueKey('change-location'),
                  onPressed: () => _pick(context, ref, point),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
