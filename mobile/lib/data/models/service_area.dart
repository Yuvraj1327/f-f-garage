import 'json_reader.dart';

class ServiceArea {
  const ServiceArea({
    required this.id,
    required this.pincode,
    required this.areaName,
    required this.city,
    required this.state,
    required this.isActive,
  });

  factory ServiceArea.fromJson(Map<String, dynamic> json) => ServiceArea(
        id: JsonReader.string(json, 'id'),
        pincode: JsonReader.string(json, 'pincode'),
        areaName: JsonReader.string(json, 'area_name'),
        city: JsonReader.string(json, 'city'),
        state: JsonReader.string(json, 'state'),
        isActive: JsonReader.boolean(json, 'is_active'),
      );

  final String id;
  final String pincode;
  final String areaName;
  final String city;
  final String state;
  final bool isActive;
}

/// Answer to "do you service this PIN code?".
class PincodeCheck {
  const PincodeCheck({
    required this.pincode,
    required this.serviceable,
    this.areaName,
    this.city,
    this.state,
  });

  factory PincodeCheck.fromJson(Map<String, dynamic> json) => PincodeCheck(
        pincode: JsonReader.string(json, 'pincode'),
        serviceable: JsonReader.boolean(json, 'serviceable'),
        areaName: JsonReader.optionalString(json, 'area_name'),
        city: JsonReader.optionalString(json, 'city'),
        state: JsonReader.optionalString(json, 'state'),
      );

  final String pincode;
  final bool serviceable;
  final String? areaName;
  final String? city;
  final String? state;
}
