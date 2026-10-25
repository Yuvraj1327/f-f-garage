import 'json_reader.dart';

/// A point on the map. Plain numbers, so no map-plugin type reaches the rest of
/// the app (and tests need no map).
class MapPoint {
  const MapPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// "12.971599,77.594566": what Google Maps links accept as a place.
  String get asQuery =>
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

  @override
  bool operator ==(Object other) =>
      other is MapPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'MapPoint($asQuery)';
}

/// One address found by the backend's lookup, with the PIN code taken from it.
/// [serviceable] comes from the garage's own service areas (null: no PIN code).
class Place {
  const Place({
    required this.formattedAddress,
    required this.point,
    this.pincode,
    this.areaName,
    this.city,
    this.state,
    this.serviceable,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    final latitude = JsonReader.optionalDouble(json, 'latitude');
    final longitude = JsonReader.optionalDouble(json, 'longitude');
    if (latitude == null || longitude == null) {
      throw const FormatException('A place needs latitude and longitude');
    }
    final serviceable = json['serviceable'];
    if (serviceable != null && serviceable is! bool) {
      throw const FormatException('Expected "serviceable" to be true/false');
    }
    return Place(
      formattedAddress: JsonReader.string(json, 'formatted_address'),
      point: MapPoint(latitude, longitude),
      pincode: JsonReader.optionalString(json, 'pincode'),
      areaName: JsonReader.optionalString(json, 'area_name'),
      city: JsonReader.optionalString(json, 'city'),
      state: JsonReader.optionalString(json, 'state'),
      serviceable: serviceable as bool?,
    );
  }

  final String formattedAddress;
  final MapPoint point;
  final String? pincode;
  final String? areaName;
  final String? city;
  final String? state;
  final bool? serviceable;
}

/// What the map picker hands back: the pin, and the address found there (null
/// when the lookup was unavailable; the customer then types the address).
class PickedLocation {
  const PickedLocation({required this.point, this.place});

  final MapPoint point;
  final Place? place;
}
