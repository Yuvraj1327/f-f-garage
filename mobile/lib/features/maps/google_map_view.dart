import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/models/place.dart';
import 'map_view.dart';

/// The real map, drawn by `google_maps_flutter`. The only file that names the
/// plugin's types.
Widget buildGoogleMapView(BuildContext context, MapViewSpec spec) =>
    GoogleMapView(spec: spec);

class GoogleMapView extends StatefulWidget {
  const GoogleMapView({super.key, required this.spec});

  final MapViewSpec spec;

  @override
  State<GoogleMapView> createState() => _GoogleMapViewState();
}

class _GoogleMapViewState extends State<GoogleMapView>
    implements MapViewController {
  GoogleMapController? _controller;
  late LatLng _center = _latLng(widget.spec.center);

  static LatLng _latLng(MapPoint p) => LatLng(p.latitude, p.longitude);

  @override
  Future<void> animateTo(MapPoint point, {double? zoom}) async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final target = _latLng(point);
    await controller.animateCamera(
      zoom == null
          ? CameraUpdate.newLatLng(target)
          : CameraUpdate.newLatLngZoom(target, zoom),
    );
  }

  @override
  void didUpdateWidget(GoogleMapView old) {
    super.didUpdateWidget(old);
    // A preview whose pin moved (the booking was edited) follows it.
    final spec = widget.spec;
    if (!spec.interactive && spec.center != old.spec.center) {
      unawaited(animateTo(spec.center, zoom: spec.zoom));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final interactive = spec.interactive;
    final marker = spec.marker;
    final map = GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _latLng(spec.center),
        zoom: spec.zoom,
      ),
      onMapCreated: (controller) {
        _controller = controller;
        spec.onCreated?.call(this);
      },
      onCameraMove: (position) => _center = position.target,
      onCameraIdle: () => spec.onCenterChanged?.call(
        MapPoint(_center.latitude, _center.longitude),
      ),
      markers: {
        if (marker != null)
          Marker(markerId: const MarkerId('pin'), position: _latLng(marker)),
        if (spec.myLocation case final here?)
          Marker(
            markerId: const MarkerId('me'),
            position: _latLng(here),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure,
            ),
            zIndexInt: 1,
          ),
      },
      // Previews are pictures: no gestures, no controls. (Android's lite mode
      // renders a static image, which is cheaper in a scrolling list.)
      liteModeEnabled: !interactive &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android,
      scrollGesturesEnabled: interactive,
      zoomGesturesEnabled: interactive,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      zoomControlsEnabled: interactive &&
          (kIsWeb || defaultTargetPlatform == TargetPlatform.android),
      mapToolbarEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
    );
    // A preview sits in a scrolling page: let touches reach the page.
    return interactive ? map : IgnorePointer(child: map);
  }
}
