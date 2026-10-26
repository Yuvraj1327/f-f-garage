import '../../core/network/api_exception.dart';
import '../models/garage_settings.dart';
import '../services/garage_settings_api_service.dart';

/// The garage's own details (administrators only). Throws [ApiException] only.
class GarageSettingsRepository {
  GarageSettingsRepository(this._service);

  final GarageSettingsApiService _service;

  Future<GarageSettings> load() async => _parse(await _service.get());

  Future<GarageSettings> save({
    required String name,
    required String phone,
    required String whatsapp,
    required String email,
    required String address,
    required String hours,
  }) async =>
      _parse(
        await _service.save({
          'name': name,
          'phone': phone,
          'whatsapp': whatsapp,
          'email': email,
          'address': address,
          'hours': hours,
        }),
      );

  GarageSettings _parse(Map<String, dynamic> json) {
    try {
      return GarageSettings.fromJson(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
