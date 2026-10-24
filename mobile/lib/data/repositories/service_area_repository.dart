import '../../core/network/api_exception.dart';
import '../models/service_area.dart';
import '../services/service_area_api_service.dart';

/// Serviceable PIN codes. Throws [ApiException] only.
class ServiceAreaRepository {
  ServiceAreaRepository(this._service);

  final ServiceAreaApiService _service;

  Future<PincodeCheck> checkPincode(String pincode) async =>
      _parse(await _service.check(pincode), PincodeCheck.fromJson);

  Future<List<ServiceArea>> adminList() async {
    final rows = await _service.adminList();
    return rows
        .map((row) => _parse(row, ServiceArea.fromJson))
        .toList(growable: false);
  }

  Future<ServiceArea> create({
    required String pincode,
    required String areaName,
    required String city,
    required String state,
    bool isActive = true,
  }) async {
    final json = await _service.create({
      'pincode': pincode,
      'area_name': areaName,
      'city': city,
      'state': state,
      'is_active': isActive,
    });
    return _parse(json, ServiceArea.fromJson);
  }

  Future<ServiceArea> update(String id, Map<String, dynamic> changes) async =>
      _parse(await _service.update(id, changes), ServiceArea.fromJson);

  Future<void> delete(String id) => _service.delete(id);

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
