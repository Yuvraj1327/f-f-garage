import '../../core/network/api_exception.dart';
import '../models/catalog.dart';
import '../models/enums.dart';
import '../services/catalog_api_service.dart';

/// Services, packages and extra charges. Throws [ApiException] only.
///
/// Update methods take a map of just the fields to change, so a field that is
/// not in the map is left alone and one set to null is cleared (where the
/// backend allows it).
class CatalogRepository {
  CatalogRepository(this._service);

  final CatalogApiService _service;

  // ---- customers ----
  Future<List<GarageService>> browse({VehicleType? vehicleType}) async {
    final rows = await _service.browse(vehicleType: vehicleType?.apiValue);
    return _parseAll(rows, GarageService.fromJson);
  }

  Future<GarageService> browseOne(String id) async =>
      _parse(await _service.browseOne(id), GarageService.fromJson);

  // ---- admins ----
  Future<List<GarageService>> adminList({VehicleType? vehicleType}) async {
    final rows = await _service.adminList(vehicleType: vehicleType?.apiValue);
    return _parseAll(rows, GarageService.fromJson);
  }

  Future<GarageService> adminGet(String id) async =>
      _parse(await _service.adminGet(id), GarageService.fromJson);

  Future<GarageService> createService({
    required String name,
    required VehicleType vehicleType,
    required String category,
    String? description,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    final json = await _service.createService({
      'name': name,
      'vehicle_type': vehicleType.apiValue,
      'category': category,
      'description': description,
      'display_order': displayOrder,
      'is_active': isActive,
    });
    return _parse(json, GarageService.fromJson);
  }

  Future<GarageService> updateService(
    String id,
    Map<String, dynamic> changes,
  ) async =>
      _parse(await _service.updateService(id, changes), GarageService.fromJson);

  Future<ServicePackage> createPackage(
    String serviceId, {
    required String name,
    required double price,
    String? description,
    List<String> inclusions = const [],
    int? estimatedDurationMinutes,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    final json = await _service.createPackage(serviceId, {
      'name': name,
      'price': price.toStringAsFixed(2),
      'description': description,
      'inclusions': inclusions,
      'estimated_duration_minutes': estimatedDurationMinutes,
      'display_order': displayOrder,
      'is_active': isActive,
    });
    return _parse(json, ServicePackage.fromJson);
  }

  Future<ServicePackage> updatePackage(
    String id,
    Map<String, dynamic> changes,
  ) async =>
      _parse(await _service.updatePackage(id, changes), ServicePackage.fromJson);

  Future<ExtraCharge> createCharge(
    String serviceId, {
    required String name,
    required ExtraChargeType chargeType,
    double? amount,
    String? description,
    String? packageId,
    bool isActive = true,
  }) async {
    final json = await _service.createCharge(serviceId, {
      'name': name,
      'charge_type': chargeType.apiValue,
      'amount': amount?.toStringAsFixed(2),
      'description': description,
      'package_id': packageId,
      'is_active': isActive,
    });
    return _parse(json, ExtraCharge.fromJson);
  }

  Future<ExtraCharge> updateCharge(
    String id,
    Map<String, dynamic> changes,
  ) async =>
      _parse(await _service.updateCharge(id, changes), ExtraCharge.fromJson);

  Future<void> deleteCharge(String id) => _service.deleteCharge(id);

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }

  List<T> _parseAll<T>(
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>) parse,
  ) =>
      rows.map((row) => _parse(row, parse)).toList(growable: false);
}
