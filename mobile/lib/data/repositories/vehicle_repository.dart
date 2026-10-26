import '../../core/network/api_exception.dart';
import '../models/enums.dart';
import '../models/vehicle.dart';
import '../services/vehicle_api_service.dart';

/// The signed-in customer's saved vehicles. Throws [ApiException] only.
class VehicleRepository {
  VehicleRepository(this._service);

  final VehicleApiService _service;

  Future<List<Vehicle>> list() async => _parseAll(await _service.list());

  Future<Vehicle> add({
    required VehicleType type,
    required String registration,
    required String make,
    required String model,
    String? nickname,
  }) async =>
      _parse(
        await _service.create({
          'vehicle_type': type.apiValue,
          'registration_number': registration,
          'make': make,
          'model': model,
          if (nickname != null && nickname.trim().isNotEmpty)
            'nickname': nickname.trim(),
        }),
      );

  /// Sends the whole form, so a cleared nickname is cleared on the server.
  Future<Vehicle> update(
    String id, {
    required VehicleType type,
    required String registration,
    required String make,
    required String model,
    String? nickname,
  }) async =>
      _parse(
        await _service.update(id, {
          'vehicle_type': type.apiValue,
          'registration_number': registration,
          'make': make,
          'model': model,
          'nickname':
              (nickname == null || nickname.trim().isEmpty) ? null : nickname.trim(),
        }),
      );

  Future<void> delete(String id) => _service.delete(id);

  Vehicle _parse(Map<String, dynamic> json) {
    try {
      return Vehicle.fromJson(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }

  List<Vehicle> _parseAll(List<Map<String, dynamic>> rows) {
    try {
      return rows.map(Vehicle.fromJson).toList();
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
