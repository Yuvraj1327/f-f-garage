import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/place.dart';
import 'package:ff_garage/data/repositories/maps_repository.dart';
import 'package:ff_garage/data/services/location_service.dart';
import 'package:ff_garage/features/maps/map_view.dart';
import 'package:flutter/material.dart';

const ApiException lookupUnavailable = ApiException(
  type: ApiErrorType.server,
  message: lookupUnavailableMessage,
  statusCode: 503,
);

Place place({
  String address = '12 MG Road, New Market, Bhopal, Madhya Pradesh 462001, India',
  double latitude = 23.2599,
  double longitude = 77.4126,
  String? pincode = '462001',
  bool? serviceable = true,
}) =>
    Place(
      formattedAddress: address,
      point: MapPoint(latitude, longitude),
      pincode: pincode,
      areaName: 'New Market',
      city: 'Bhopal',
      state: 'Madhya Pradesh',
      serviceable: serviceable,
    );

/// In-memory address lookup. Set [error] / [reverseError] to fail a call.
class FakeMapsRepository implements MapsRepository {
  List<Place> searchResults = [];
  List<Place> reverseResults = [];
  ApiException? error;
  ApiException? reverseError;
  final List<String> searches = [];
  final List<MapPoint> reverses = [];

  @override
  Future<List<Place>> search(String text) async {
    searches.add(text);
    if (error != null) throw error!;
    return searchResults;
  }

  @override
  Future<List<Place>> reverse(MapPoint point) async {
    reverses.add(point);
    if (reverseError != null) throw reverseError!;
    return reverseResults;
  }
}

/// A phone position that is either [result] or a problem.
class FakeLocationService implements LocationService {
  FakeLocationService([LocationResult? result])
      : result = result ?? const LocationFound(MapPoint(23.2599, 77.4126));

  LocationResult result;
  int calls = 0;
  final List<LocationProblem> settingsOpened = [];
  bool settingsCanOpen = true;

  @override
  Future<LocationResult> currentLocation() async {
    calls += 1;
    return result;
  }

  @override
  Future<bool> openSettings(LocationProblem problem) async {
    settingsOpened.add(problem);
    return settingsCanOpen;
  }
}

/// Stands in for the Google map (a native view that cannot be built in a widget
/// test). Remembers the latest [MapViewSpec] so a test can "move the map".
class FakeMapView {
  MapViewSpec? spec;
  final List<MapPoint> animations = [];
  int builds = 0;

  Widget build(BuildContext context, MapViewSpec spec) {
    this.spec = spec;
    builds += 1;
    return _FakeMap(spec: spec, host: this);
  }

  /// The user dragged the map so that [point] is under the pin.
  void moveTo(MapPoint point) => spec!.onCenterChanged!(point);

  bool get interactive => spec?.interactive ?? false;
}

class _FakeMap extends StatefulWidget {
  const _FakeMap({required this.spec, required this.host});

  final MapViewSpec spec;
  final FakeMapView host;

  @override
  State<_FakeMap> createState() => _FakeMapState();
}

class _FakeMapState extends State<_FakeMap> implements MapViewController {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.spec.onCreated?.call(this);
    });
  }

  @override
  Future<void> animateTo(MapPoint point, {double? zoom}) async {
    widget.host.animations.add(point);
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('fake-map'));
}
