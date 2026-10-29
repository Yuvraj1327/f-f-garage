import 'dart:typed_data';

import '../../core/network/api_exception.dart';
import '../models/catalog.dart';
import '../models/enums.dart';
import '../services/catalog_api_service.dart';

/// Which slot a picture is for.
enum ServiceImageKind { banner, thumbnail, part }

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
    // One malformed row must not blank the whole catalogue: skip it.
    final services = <GarageService>[];
    for (final row in rows) {
      try {
        services.add(GarageService.fromJson(row));
      } on FormatException {
        continue;
      }
    }
    if (services.isEmpty && rows.isNotEmpty) {
      throw ApiException.invalidResponse();
    }
    return services;
  }

  Future<GarageService> browseOne(String id) async =>
      _parse(await _service.browseOne(id), GarageService.fromJson);

  Future<List<ServiceCategory>> browseCategories() async =>
      _parseAll(await _service.browseCategories(), ServiceCategory.fromJson);

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
    CatalogTab catalogTab = CatalogTab.package,
    String? repairGroup,
    String? imageUrl,
    String? badge,
    String? shortDescription,
    String? categoryId,
    String? bannerUrl,
    String? thumbnailUrl,
    List<String> partImageUrls = const [],
    List<String> supportedMakes = const [],
    List<String> supportedModels = const [],
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    final json = await _service.createService({
      'name': name,
      'vehicle_type': vehicleType.apiValue,
      'category': category,
      'description': description,
      'short_description': shortDescription,
      if (categoryId != null) 'category_id': categoryId,
      'catalog_tab': catalogTab.apiValue,
      'repair_group': repairGroup,
      'image_url': imageUrl,
      'banner_url': bannerUrl,
      'thumbnail_url': thumbnailUrl,
      'part_image_urls': partImageUrls,
      'supported_makes': supportedMakes,
      'supported_models': supportedModels,
      'badge': badge,
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

  /// Only for a service that was never booked (the server refuses otherwise).
  Future<void> deleteService(String id) => _service.deleteService(id);

  /// A switched-off copy with its packages and extra charges.
  Future<GarageService> duplicateService(String id) async =>
      _parse(await _service.duplicateService(id), GarageService.fromJson);

  Future<List<ServiceCategory>> adminCategories() async =>
      _parseAll(await _service.adminCategories(), ServiceCategory.fromJson);

  Future<ServiceCategory> createCategory({
    required String name,
    required CatalogTab tab,
    String? iconKey,
  }) async =>
      _parse(
        await _service.createCategory({
          'name': name,
          'tab': tab.apiValue,
          if (iconKey != null) 'icon_key': iconKey,
        }),
        ServiceCategory.fromJson,
      );

  Future<ServiceCategory> updateCategory(
    String id,
    Map<String, dynamic> changes,
  ) async =>
      _parse(
        await _service.updateCategory(id, changes),
        ServiceCategory.fromJson,
      );

  /// [ids] is every category, in the order they should appear.
  Future<List<ServiceCategory>> reorderCategories(List<String> ids) async =>
      _parseAll(await _service.reorderCategories(ids), ServiceCategory.fromJson);

  /// Uploads a picture and returns its link, to save on the service.
  Future<String> uploadImage(
    ServiceImageKind kind,
    Uint8List bytes,
    String contentType,
  ) async {
    final json = await _service.uploadImage(kind.name, bytes, contentType);
    final url = json['url'];
    if (url is! String || !url.startsWith('https://')) {
      throw ApiException.invalidResponse();
    }
    return url;
  }

  /// Best effort: a picture left on the server is harmless, so this never throws.
  Future<void> discardImage(String url) async {
    try {
      await _service.discardImage(url);
    } catch (_) {}
  }

  Future<ServicePackage> createPackage(
    String serviceId, {
    required String name,
    required double price,
    String? description,
    List<String> inclusions = const [],
    List<String> exclusions = const [],
    double? originalPrice,
    int? warrantyDays,
    double? advancePercent,
    int? repeatIntervalDays,
    double? labourCharge,
    List<String> includedParts = const [],
    PartsPolicy partsPolicy = PartsPolicy.serviceOnly,
    String? partsNote,
    int? estimatedDurationMinutes,
    int displayOrder = 0,
    bool isActive = true,
  }) async {
    final json = await _service.createPackage(serviceId, {
      'advance_percent': advancePercent?.toStringAsFixed(2),
      'repeat_interval_days': repeatIntervalDays,
      'labour_charge': labourCharge?.toStringAsFixed(2),
      'included_parts': includedParts,
      'name': name,
      'price': price.toStringAsFixed(2),
      'original_price': originalPrice?.toStringAsFixed(2),
      'description': description,
      'inclusions': inclusions,
      'exclusions': exclusions,
      'warranty_days': warrantyDays,
      'parts_policy': partsPolicy.apiValue,
      'parts_note': partsNote,
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
