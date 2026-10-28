import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/async_view.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/status_badge.dart';
import '../../data/models/place.dart';
import '../../data/providers/data_providers.dart';
import '../../data/services/location_service.dart';
import 'map_providers.dart';
import 'map_view.dart';

/// Where the map starts when there is no pin yet: the middle of India.
const MapPoint _indiaCentre = MapPoint(20.5937, 78.9629);

/// Full-screen map for choosing the service location.
///
/// The customer moves the map under a fixed pin (or searches an address, or
/// taps "my location"); the address and PIN code at the pin are looked up
/// through the backend. Returns a [PickedLocation] with "Use this location".
/// A lookup that fails never blocks the pin: the customer can still use it and
/// type the address themselves.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({super.key, this.initial});

  /// The pin to start from (an existing booking's, or the phone's position).
  final MapPoint? initial;

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

enum _Lookup { idle, loading, found, empty, failed }

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  final _query = TextEditingController();
  late MapPoint _center = widget.initial ?? _indiaCentre;
  late bool _hasPoint = widget.initial != null;
  MapViewController? _map;

  Place? _place;
  _Lookup _lookup = _Lookup.idle;
  String? _lookupError;
  int _lookupGeneration = 0;

  List<Place> _results = const [];
  bool _searching = false;
  String? _searchMessage;
  int _searchGeneration = 0;

  bool _locating = false;
  String? _locationMessage;
  LocationProblem? _problem;

  /// True right after the camera was moved to an address we already know, so
  /// the "camera stopped" event that follows does not look it up again.
  bool _skipNextIdle = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reverse(widget.initial!);
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static bool _same(MapPoint a, MapPoint b) =>
      (a.latitude - b.latitude).abs() < 1e-6 &&
      (a.longitude - b.longitude).abs() < 1e-6;

  void _onCenterChanged(MapPoint point) {
    if (_skipNextIdle) {
      _skipNextIdle = false;
      _center = point;
      return;
    }
    // The map reports its starting position once it has loaded: not a choice.
    if (_same(point, _center)) {
      return;
    }
    setState(() {
      _center = point;
      _hasPoint = true;
      _results = const [];
    });
    _reverse(point);
  }

  Future<void> _reverse(MapPoint point) async {
    final generation = ++_lookupGeneration;
    setState(() {
      _lookup = _Lookup.loading;
      _lookupError = null;
    });
    try {
      final places = await ref.read(mapsRepositoryProvider).reverse(point);
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _place = places.isEmpty ? null : places.first;
        _lookup = places.isEmpty ? _Lookup.empty : _Lookup.found;
      });
    } catch (error) {
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _place = null;
        _lookup = _Lookup.failed;
        _lookupError = errorMessage(error);
      });
    }
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    FocusScope.of(context).unfocus();
    if (text.length < 3) {
      setState(() => _searchMessage = 'Type at least 3 characters to search.');
      return;
    }
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _searchMessage = null;
      _results = const [];
    });
    try {
      final places = await ref.read(mapsRepositoryProvider).search(text);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searching = false;
        _results = places;
        _searchMessage = places.isEmpty
            ? 'No matching address found. Try a nearby landmark or the area name.'
            : null;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searching = false;
        _searchMessage = errorMessage(error);
      });
    }
  }

  void _choose(Place place) {
    _lookupGeneration++; // a lookup still running for the old spot is stale
    setState(() {
      _center = place.point;
      _hasPoint = true;
      _place = place;
      _lookup = _Lookup.found;
      _lookupError = null;
      _results = const [];
      _searchMessage = null;
      _skipNextIdle = true;
    });
    _map?.animateTo(place.point, zoom: 17);
  }

  MapPoint? _myLocation;

  Future<void> _locate() async {
    if (_locating) {
      return;
    }
    setState(() {
      _locating = true;
      _locationMessage = null;
      _problem = null;
    });
    final result = await ref.read(locationServiceProvider).currentLocation();
    if (!mounted) return;
    switch (result) {
      case LocationFailed(:final problem):
        setState(() {
          _locating = false;
          _problem = problem;
          _locationMessage = locationProblemMessage(problem);
        });
      case LocationFound(:final point):
        setState(() {
          _locating = false;
          _center = point;
          _hasPoint = true;
          _myLocation = point;
          _results = const [];
          _skipNextIdle = true;
        });
        _map?.animateTo(point, zoom: 17);
        _reverse(point);
    }
  }

  void _confirm() => context.pop(PickedLocation(point: _center, place: _place));

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(mapsAvailableProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose location')),
      body: SafeArea(
        child: available ? _buildMap(context) : const _NoMaps(),
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final build = ref.watch(mapViewBuilderProvider);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: build(
            context,
            MapViewSpec(
              center: _center,
              zoom: _hasPoint ? 17 : 5,
              myLocation: _myLocation,
              onCenterChanged: _onCenterChanged,
              onCreated: (controller) => _map = controller,
            ),
          ),
        ),
        // The fixed pin. Its tip (bottom) is the chosen point, so it is lifted
        // by half its height to sit exactly on the map centre.
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Icon(
                Icons.location_on,
                key: const ValueKey('center-pin'),
                size: 48,
                color: scheme.error,
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 12,
          right: 12,
          child: _SearchBar(
            controller: _query,
            searching: _searching,
            onSearch: _search,
            message: _searchMessage,
            results: _results,
            onChoose: _choose,
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: _BottomPanel(
            hasPoint: _hasPoint,
            lookup: _lookup,
            place: _place,
            lookupError: _lookupError,
            locating: _locating,
            locationMessage: _locationMessage,
            problem: _problem,
            onLocate: _locate,
            onOpenSettings: () async {
              final opened =
                  await ref.read(locationServiceProvider).openSettings(_problem!);
              if (!opened && mounted) {
                showSnack(
                  context,
                  'Open your device settings and allow location for this app.',
                );
              }
            },
            onConfirm: _confirm,
          ),
        ),
      ],
    );
  }
}

class _NoMaps extends StatelessWidget {
  const _NoMaps();

  @override
  Widget build(BuildContext context) {
    return const EmptyView(
      icon: Icons.map_outlined,
      message: 'Maps are not switched on in this version of the app.\n'
          'Go back and type your address instead.',
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.searching,
    required this.onSearch,
    required this.message,
    required this.results,
    required this.onChoose,
  });

  final TextEditingController controller;
  final bool searching;
  final VoidCallback onSearch;
  final String? message;
  final List<Place> results;
  final ValueChanged<Place> onChoose;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('map-search'),
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: 'Search address, area or landmark',
              prefixIcon: const Icon(Icons.search),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      key: const ValueKey('map-search-go'),
                      tooltip: 'Search',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: onSearch,
                    ),
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                message!,
                key: const ValueKey('search-message'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < results.length; i++)
                    ListTile(
                      key: ValueKey('search-result-$i'),
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        results[i].formattedAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: results[i].serviceable == false
                          ? const Text('We do not service this PIN code yet')
                          : null,
                      onTap: () => onChoose(results[i]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.hasPoint,
    required this.lookup,
    required this.place,
    required this.lookupError,
    required this.locating,
    required this.locationMessage,
    required this.problem,
    required this.onLocate,
    required this.onOpenSettings,
    required this.onConfirm,
  });

  final bool hasPoint;
  final _Lookup lookup;
  final Place? place;
  final String? lookupError;
  final bool locating;
  final String? locationMessage;
  final LocationProblem? problem;
  final VoidCallback onLocate;
  final VoidCallback onOpenSettings;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final blocked = place?.serviceable == false;
    final loading = lookup == _Lookup.loading;
    final canConfirm = hasPoint && !loading && !blocked;

    final Widget summary;
    if (!hasPoint) {
      summary = Text(
        'Move the map to put the pin on your doorstep, search for your '
        'address, or use your current location.',
        style: textTheme.bodyMedium,
      );
    } else if (loading) {
      summary = Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Finding the address...', style: textTheme.bodyMedium),
        ],
      );
    } else if (place != null) {
      final pin = place!.pincode;
      summary = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            place!.formattedAddress,
            key: const ValueKey('picked-address'),
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (pin != null)
                StatusBadge(label: 'PIN $pin', tone: BadgeTone.neutral),
              if (place!.serviceable == true)
                const StatusBadge(
                  label: 'We service this area',
                  tone: BadgeTone.success,
                  icon: Icons.check_circle_outline,
                )
              else if (place!.serviceable == false)
                const StatusBadge(
                  label: 'Not serviceable yet',
                  tone: BadgeTone.danger,
                  icon: Icons.block,
                ),
            ],
          ),
        ],
      );
    } else {
      summary = Text(
        lookup == _Lookup.failed
            ? '${lookupError ?? "Couldn't look up the address."}\n'
                'You can still use this pin and type the address yourself.'
            : 'No address found at this spot. You can still use this pin and '
                'type the address yourself.',
        key: const ValueKey('lookup-note'),
        style: textTheme.bodyMedium,
      );
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            summary,
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Move the pin to a spot we service, or search another address.',
                  key: const ValueKey('blocked-note'),
                  style: textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            if (locationMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        locationMessage!,
                        key: const ValueKey('location-message'),
                        style: textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ),
                    if (problem == LocationProblem.deniedForever ||
                        problem == LocationProblem.servicesOff)
                      TextButton(
                        key: const ValueKey('open-location-settings'),
                        onPressed: onOpenSettings,
                        child: const Text('Settings'),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('locate-me'),
                  onPressed: locating ? null : onLocate,
                  icon: locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: const Text('My location'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('use-this-location'),
                    onPressed: canConfirm ? onConfirm : null,
                    child: const Text('Use this location'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
