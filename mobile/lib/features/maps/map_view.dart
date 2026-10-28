import 'package:flutter/widgets.dart';

import '../../data/models/place.dart';

/// What a map screen needs from a map, without naming any map plugin: tests
/// replace [mapViewBuilderProvider] with a stand-in, because a real Google map
/// is a native view that cannot be built in a widget test.
class MapViewSpec {
  const MapViewSpec({
    required this.center,
    this.zoom = 16,
    this.interactive = true,
    this.marker,
    this.myLocation,
    this.onCenterChanged,
    this.onCreated,
  });

  /// Where the camera starts.
  final MapPoint center;
  final double zoom;

  /// False for a small preview: no panning or zooming.
  final bool interactive;

  /// A pin drawn on the map (previews). The picker uses a fixed centre pin
  /// drawn by the screen instead.
  final MapPoint? marker;

  /// The device's own position, drawn as a blue marker apart from the pin.
  final MapPoint? myLocation;

  /// Called when the camera stops moving, with the point under the centre.
  final ValueChanged<MapPoint>? onCenterChanged;

  final ValueChanged<MapViewController>? onCreated;
}

/// Moves the camera of a map built from a [MapViewSpec].
abstract interface class MapViewController {
  Future<void> animateTo(MapPoint point, {double? zoom});
}

typedef MapViewBuilder = Widget Function(BuildContext context, MapViewSpec spec);
