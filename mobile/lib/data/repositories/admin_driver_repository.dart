import '../../core/network/api_exception.dart';
import '../models/driver.dart';
import '../services/admin_driver_api_service.dart';

/// Driver accounts for admins. Throws [ApiException] only.
class AdminDriverRepository {
  AdminDriverRepository(this._service);

  final AdminDriverApiService _service;

  Future<List<DriverAccount>> list() async {
    final rows = await _service.list();
    try {
      return rows.map(DriverAccount.fromJson).toList();
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }

  Future<DriverAccount> get(String id) async =>
      _parse(await _service.get(id));

  Future<DriverAccount> create({
    required String driverId,
    required String password,
    required String fullName,
    String? phone,
  }) async =>
      _parse(
        await _service.create({
          'driver_id': driverId,
          'password': password,
          'full_name': fullName,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
        }),
      );

  /// Sends only what changed (full_name, phone, is_active).
  Future<DriverAccount> update(String id, Map<String, dynamic> changes) async =>
      _parse(await _service.update(id, changes));

  Future<void> resetPassword(String id, String newPassword) =>
      _service.resetPassword(id, newPassword);

  DriverAccount _parse(Map<String, dynamic> json) {
    try {
      return DriverAccount.fromJson(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
