import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../models/place.dart';

/// Why the phone's position could not be read.
enum LocationProblem {
  /// Location is switched off for the whole device.
  servicesOff,

  /// The user said no this time (we may ask again).
  denied,

  /// The user said "don't ask again": only the system settings can undo it.
  deniedForever,

  /// No fix within the time allowed (indoors, no signal).
  timeout,

  /// Anything else, or a platform with no location support.
  unavailable,
}

/// The phone's position, or why there is none.
sealed class LocationResult {
  const LocationResult();
}

class LocationFound extends LocationResult {
  const LocationFound(this.point);

  final MapPoint point;
}

class LocationFailed extends LocationResult {
  const LocationFailed(this.problem);

  final LocationProblem problem;
}

/// Reads the device position, asking for permission first. A narrow interface
/// so screens and tests never touch the plugin. Never throws.
abstract interface class LocationService {
  Future<LocationResult> currentLocation();

  /// Opens the system screen that can fix [problem] (app permissions, or the
  /// location switch). False when the platform cannot open it.
  Future<bool> openSettings(LocationProblem problem);
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  static const Duration _timeLimit = Duration(seconds: 15);

  @override
  Future<LocationResult> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFailed(LocationProblem.servicesOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const LocationFailed(LocationProblem.denied);
        case LocationPermission.deniedForever:
          return const LocationFailed(LocationProblem.deniedForever);
        case LocationPermission.unableToDetermine:
          return const LocationFailed(LocationProblem.unavailable);
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          break;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _timeLimit,
        ),
      );
      return LocationFound(MapPoint(position.latitude, position.longitude));
    } on TimeoutException {
      return const LocationFailed(LocationProblem.timeout);
    } on LocationServiceDisabledException {
      return const LocationFailed(LocationProblem.servicesOff);
    } on PermissionDeniedException {
      return const LocationFailed(LocationProblem.denied);
    } catch (_) {
      return const LocationFailed(LocationProblem.unavailable);
    }
  }

  @override
  Future<bool> openSettings(LocationProblem problem) async {
    try {
      return problem == LocationProblem.servicesOff
          ? await Geolocator.openLocationSettings()
          : await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}

/// A short, friendly sentence for [problem].
String locationProblemMessage(LocationProblem problem) {
  switch (problem) {
    case LocationProblem.servicesOff:
      return 'Location is switched off on this device. Turn it on, or search '
          'for your address instead.';
    case LocationProblem.denied:
      return 'We need permission to use your location. You can also search '
          'for your address.';
    case LocationProblem.deniedForever:
      return 'Location permission is blocked for this app. Allow it in your '
          'device settings, or search for your address instead.';
    case LocationProblem.timeout:
      return "We couldn't get a location fix in time. Try again outdoors, or "
          'search for your address.';
    case LocationProblem.unavailable:
      return "Your location isn't available right now. You can search for "
          'your address instead.';
  }
}
