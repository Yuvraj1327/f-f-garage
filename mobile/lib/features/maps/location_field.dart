import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_routes.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/models/place.dart';
import '../../data/providers/data_providers.dart';
import '../../data/services/location_service.dart';
import 'location_map_card.dart';
import 'map_providers.dart';

/// The "where exactly?" part of an address form: shows the pinned spot, and
/// offers "Pick on map" and "Use my current location".
///
/// Where maps are not configured the map is left out; "Use my current location"
/// then fills the address straight from the backend's lookup. If that is
/// unavailable too, the customer simply types the address as before.
class LocationField extends ConsumerStatefulWidget {
  const LocationField({
    super.key,
    required this.point,
    required this.onPicked,
    required this.onCleared,
    this.enabled = true,
  });

  final MapPoint? point;
  final ValueChanged<PickedLocation> onPicked;
  final VoidCallback onCleared;
  final bool enabled;

  @override
  ConsumerState<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends ConsumerState<LocationField> {
  bool _locating = false;
  String? _message;
  LocationProblem? _problem;

  Future<void> _pickOnMap([MapPoint? start]) async {
    final picked = await context.push<PickedLocation>(
      AppRoutes.pickLocation,
      extra: start ?? widget.point,
    );
    if (picked != null && mounted) {
      setState(() => _message = null);
      widget.onPicked(picked);
    }
  }

  Future<void> _useMyLocation() async {
    if (_locating) {
      return;
    }
    setState(() {
      _locating = true;
      _message = null;
      _problem = null;
    });
    final result = await ref.read(locationServiceProvider).currentLocation();
    if (!mounted) return;
    switch (result) {
      case LocationFailed(:final problem):
        setState(() {
          _locating = false;
          _problem = problem;
          _message = locationProblemMessage(problem);
        });
      case LocationFound(:final point):
        if (ref.read(mapsAvailableProvider)) {
          // Let the customer check and nudge the pin.
          setState(() => _locating = false);
          await _pickOnMap(point);
        } else {
          await _fillWithoutMap(point);
        }
    }
  }

  /// No map in this build: look the address up for the position and use it.
  Future<void> _fillWithoutMap(MapPoint point) async {
    Place? place;
    try {
      final found = await ref.read(mapsRepositoryProvider).reverse(point);
      place = found.isEmpty ? null : found.first;
    } catch (_) {
      // Lookup unavailable: keep the position, the customer types the address.
    }
    if (!mounted) return;
    setState(() => _locating = false);
    widget.onPicked(PickedLocation(point: point, place: place));
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(mapsAvailableProvider);
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final point = widget.point;
    final enabled = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pin your exact spot (optional)', style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Helps our driver find you.',
          style: textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        if (point != null) ...[
          LocationMapCard(point: point),
          const SizedBox(height: 4),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (available)
              FilledButton.tonalIcon(
                key: const ValueKey('pick-on-map'),
                onPressed: enabled ? () => _pickOnMap() : null,
                icon: const Icon(Icons.map_outlined),
                label: Text(point == null ? 'Pick on map' : 'Change on map'),
              ),
            OutlinedButton.icon(
              key: const ValueKey('use-my-location'),
              onPressed: enabled && !_locating ? _useMyLocation : null,
              icon: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Use my current location'),
            ),
            if (point != null)
              TextButton(
                key: const ValueKey('remove-pin'),
                onPressed: enabled ? widget.onCleared : null,
                child: const Text('Remove pin'),
              ),
          ],
        ),
        if (!available)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Maps are not switched on in this version of the app. You can '
              'still type your address.',
              style: textTheme.bodySmall?.copyWith(color: muted),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _message!,
                    key: const ValueKey('location-message'),
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                if (_problem == LocationProblem.deniedForever ||
                    _problem == LocationProblem.servicesOff)
                  TextButton(
                    key: const ValueKey('open-location-settings'),
                    onPressed: () async {
                      final opened = await ref
                          .read(locationServiceProvider)
                          .openSettings(_problem!);
                      if (!opened && context.mounted) {
                        showSnack(
                          context,
                          'Open your device settings and allow location '
                          'for this app.',
                        );
                      }
                    },
                    child: const Text('Settings'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
