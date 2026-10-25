import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';
import 'google_map_view.dart';
import 'map_view.dart';

/// The widget that draws a map. Tests override this with a stand-in.
final mapViewBuilderProvider = Provider<MapViewBuilder>(
  (ref) => buildGoogleMapView,
);

/// Is a Maps key configured for the platform this build runs on? When false,
/// screens fall back to "Open in Google Maps" links and typed addresses.
final mapsAvailableProvider = Provider<bool>((ref) {
  final config = ref.watch(appConfigProvider);
  return config.mapsConfigured(isWeb: kIsWeb, platform: defaultTargetPlatform);
});
