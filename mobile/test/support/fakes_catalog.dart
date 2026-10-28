import 'dart:typed_data';

import 'package:ff_garage/core/media/image_picker_service.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/availability.dart';
import 'package:ff_garage/data/models/catalog.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/service_area.dart';
import 'package:ff_garage/data/repositories/availability_repository.dart';
import 'package:ff_garage/data/repositories/catalog_repository.dart';
import 'package:ff_garage/data/repositories/service_area_repository.dart';

const conflictError = ApiException(
  type: ApiErrorType.conflict,
  message: 'A service area with this PIN code already exists',
  statusCode: 409,
);

ServicePackage package({
  String id = 'p1',
  String serviceId = 's1',
  String name = 'Basic',
  double price = 499,
  bool isActive = true,
  List<String> inclusions = const ['Wash', 'Oil top-up'],
  int? minutes = 90,
  List<ExtraCharge> charges = const [],
  double? originalPrice,
  double? advancePercent,
  int? warrantyDays,
  int? repeatIntervalDays,
  List<String> includedParts = const [],
  List<String> exclusions = const [],
}) =>
    ServicePackage(
      originalPrice: originalPrice,
      advancePercent: advancePercent,
      warrantyDays: warrantyDays,
      repeatIntervalDays: repeatIntervalDays,
      includedParts: includedParts,
      exclusions: exclusions,
      id: id,
      serviceId: serviceId,
      name: name,
      price: price,
      inclusions: inclusions,
      estimatedDurationMinutes: minutes,
      displayOrder: 0,
      isActive: isActive,
      extraCharges: charges,
    );

ExtraCharge charge({
  String id = 'c1',
  String serviceId = 's1',
  String? packageId,
  String name = 'Engine oil 10W-30',
  ExtraChargeType type = ExtraChargeType.engineOil,
  double? amount = 350,
  bool isActive = true,
}) =>
    ExtraCharge(
      id: id,
      serviceId: serviceId,
      packageId: packageId,
      chargeType: type,
      name: name,
      amount: amount,
      isActive: isActive,
    );

GarageService service({
  String id = 's1',
  String name = 'General Service',
  VehicleType type = VehicleType.scooter,
  bool isActive = true,
  List<ServicePackage>? packages,
  List<ExtraCharge> charges = const [],
  String? categoryId = 'cat-package',
  String? shortDescription,
  String? badge,
  String? systemKey,
  List<String> supportedMakes = const [],
  List<String> supportedModels = const [],
  List<String> partImageUrls = const [],
  String? bannerUrl,
  String? thumbnailUrl,
}) =>
    GarageService(
      id: id,
      name: name,
      vehicleType: type,
      category: 'Maintenance',
      categoryId: categoryId,
      shortDescription: shortDescription,
      badge: badge,
      systemKey: systemKey,
      supportedMakes: supportedMakes,
      supportedModels: supportedModels,
      partImageUrls: partImageUrls,
      bannerUrl: bannerUrl,
      thumbnailUrl: thumbnailUrl,
      description: 'Routine service',
      displayOrder: 0,
      isActive: isActive,
      packages: packages ?? [package(serviceId: id)],
      extraCharges: charges,
    );

ServiceCategory category({
  String id = 'cat-package',
  String name = 'Service Packages',
  CatalogTab tab = CatalogTab.package,
  bool isActive = true,
  int order = 20,
  String? systemKey,
}) =>
    ServiceCategory(
      id: id,
      name: name,
      tab: tab,
      displayOrder: order,
      isActive: isActive,
      systemKey: systemKey,
    );

/// In-memory catalogue. Set [error] to make every call fail with it.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository(this.services, {List<ServiceCategory>? categories})
      : categories = categories ??
            [
              category(
                id: 'cat-mechanic',
                name: 'Book a Mechanic',
                tab: CatalogTab.mechanic,
                order: 10,
                systemKey: 'tab_mechanic',
              ),
              category(systemKey: 'tab_package'),
              category(
                id: 'cat-brakes',
                name: 'Brakes',
                tab: CatalogTab.repair,
                order: 40,
              ),
            ];

  List<GarageService> services;
  List<ServiceCategory> categories;
  ApiException? error;
  final List<String> calls = [];
  Map<String, dynamic>? lastChanges;

  /// The fields of the last createService call, by API name.
  Map<String, dynamic>? lastCreate;

  /// The fields of the last createPackage call, by API name.
  Map<String, dynamic>? lastPackage;

  /// Pictures "uploaded", and the ones discarded again.
  final List<String> uploads = [];
  final List<String> discarded = [];

  void _check(String call) {
    calls.add(call);
    if (error != null) throw error!;
  }

  @override
  Future<List<GarageService>> browse({VehicleType? vehicleType}) async {
    _check('browse');
    return services
        .where((s) => s.isActive && s.packages.any((p) => p.isActive))
        .where((s) => vehicleType == null || s.vehicleType == vehicleType)
        .toList();
  }

  @override
  Future<GarageService> browseOne(String id) async {
    _check('browseOne');
    return services.firstWhere((s) => s.id == id);
  }

  @override
  Future<List<ServiceCategory>> browseCategories() async {
    _check('browseCategories');
    return categories.where((c) => c.isActive).toList();
  }

  @override
  Future<List<GarageService>> adminList({VehicleType? vehicleType}) async {
    _check('adminList');
    return services
        .where((s) => vehicleType == null || s.vehicleType == vehicleType)
        .toList();
  }

  @override
  Future<GarageService> adminGet(String id) async {
    _check('adminGet');
    return services.firstWhere((s) => s.id == id);
  }

  @override
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
    _check('createService:$name:${vehicleType.apiValue}:$category');
    lastCreate = {
      'description': description,
      'short_description': shortDescription,
      'category_id': categoryId,
      'banner_url': bannerUrl,
      'thumbnail_url': thumbnailUrl,
      'part_image_urls': partImageUrls,
      'supported_makes': supportedMakes,
      'supported_models': supportedModels,
      'badge': badge,
      'is_active': isActive,
    };
    final created = GarageService(
      id: 'new-${services.length}',
      name: name,
      vehicleType: vehicleType,
      category: category,
      categoryId: categoryId,
      description: description,
      shortDescription: shortDescription,
      bannerUrl: bannerUrl,
      thumbnailUrl: thumbnailUrl,
      partImageUrls: partImageUrls,
      supportedMakes: supportedMakes,
      supportedModels: supportedModels,
      badge: badge,
      displayOrder: displayOrder,
      isActive: isActive,
      packages: const [],
      extraCharges: const [],
    );
    services = [...services, created];
    return created;
  }

  @override
  Future<GarageService> updateService(
    String id,
    Map<String, dynamic> changes,
  ) async {
    _check('updateService:$id');
    lastChanges = changes;
    final old = services.firstWhere((s) => s.id == id);
    final updated = GarageService(
      id: old.id,
      name: (changes['name'] as String?) ?? old.name,
      vehicleType: old.vehicleType,
      category: (changes['category'] as String?) ?? old.category,
      categoryId: old.categoryId,
      systemKey: old.systemKey,
      description: changes.containsKey('description')
          ? changes['description'] as String?
          : old.description,
      displayOrder: (changes['display_order'] as int?) ?? old.displayOrder,
      isActive: (changes['is_active'] as bool?) ?? old.isActive,
      packages: old.packages,
      extraCharges: old.extraCharges,
    );
    services = [for (final s in services) s.id == id ? updated : s];
    return updated;
  }

  @override
  Future<void> deleteService(String id) async {
    _check('deleteService:$id');
    services = services.where((s) => s.id != id).toList();
  }

  @override
  Future<GarageService> duplicateService(String id) async {
    _check('duplicateService:$id');
    final old = services.firstWhere((s) => s.id == id);
    final copy = GarageService(
      id: 'copy-${services.length}',
      name: '${old.name} (Copy)',
      vehicleType: old.vehicleType,
      category: old.category,
      categoryId: old.categoryId,
      displayOrder: old.displayOrder,
      isActive: false,
      packages: old.packages,
      extraCharges: old.extraCharges,
    );
    services = [...services, copy];
    return copy;
  }

  @override
  Future<List<ServiceCategory>> adminCategories() async {
    _check('adminCategories');
    return categories;
  }

  @override
  Future<ServiceCategory> createCategory({
    required String name,
    required CatalogTab tab,
    String? iconKey,
  }) async {
    _check('createCategory:$name:${tab.apiValue}');
    final created = category(
      id: 'cat-new-${categories.length}',
      name: name,
      tab: tab,
      order: categories.length * 10 + 10,
    );
    categories = [...categories, created];
    return created;
  }

  @override
  Future<ServiceCategory> updateCategory(
    String id,
    Map<String, dynamic> changes,
  ) async {
    _check('updateCategory:$id:${changes.keys.join(',')}');
    lastChanges = changes;
    final old = categories.firstWhere((c) => c.id == id);
    final updated = ServiceCategory(
      id: old.id,
      name: (changes['name'] as String?) ?? old.name,
      tab: old.tab,
      displayOrder: old.displayOrder,
      isActive: (changes['is_active'] as bool?) ?? old.isActive,
      systemKey: old.systemKey,
    );
    categories = [for (final c in categories) c.id == id ? updated : c];
    return updated;
  }

  @override
  Future<List<ServiceCategory>> reorderCategories(List<String> ids) async {
    _check('reorderCategories:${ids.join(',')}');
    categories = [
      for (final id in ids) categories.firstWhere((c) => c.id == id),
    ];
    return categories;
  }

  @override
  Future<String> uploadImage(
    ServiceImageKind kind,
    Uint8List bytes,
    String contentType,
  ) async {
    _check('uploadImage:${kind.name}:$contentType:${bytes.length}');
    final url = 'https://cdn.test/${kind.name}-${uploads.length}.jpg';
    uploads.add(url);
    return url;
  }

  @override
  Future<void> discardImage(String url) async {
    calls.add('discardImage:$url');
    discarded.add(url);
  }

  @override
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
    _check('createPackage:$name:$price:${inclusions.join('|')}:$estimatedDurationMinutes');
    lastPackage = {
      'original_price': originalPrice,
      'advance_percent': advancePercent,
      'labour_charge': labourCharge,
      'repeat_interval_days': repeatIntervalDays,
      'warranty_days': warrantyDays,
      'included_parts': includedParts,
      'exclusions': exclusions,
      'parts_policy': partsPolicy.apiValue,
    };
    final created = package(
      id: 'np-${calls.length}',
      serviceId: serviceId,
      name: name,
      price: price,
      inclusions: inclusions,
      minutes: estimatedDurationMinutes,
      isActive: isActive,
    );
    final old = services.firstWhere((s) => s.id == serviceId);
    services = [
      for (final s in services)
        s.id == serviceId
            ? GarageService(
                id: old.id,
                name: old.name,
                vehicleType: old.vehicleType,
                category: old.category,
                categoryId: old.categoryId,
                displayOrder: old.displayOrder,
                isActive: old.isActive,
                packages: [...old.packages, created],
                extraCharges: old.extraCharges,
              )
            : s,
    ];
    return created;
  }

  @override
  Future<ServicePackage> updatePackage(
    String id,
    Map<String, dynamic> changes,
  ) async {
    _check('updatePackage:$id');
    lastChanges = changes;
    final old = services.expand((s) => s.packages).firstWhere((p) => p.id == id);
    return package(
      id: old.id,
      serviceId: old.serviceId,
      name: (changes['name'] as String?) ?? old.name,
      isActive: (changes['is_active'] as bool?) ?? old.isActive,
    );
  }

  @override
  Future<ExtraCharge> createCharge(
    String serviceId, {
    required String name,
    required ExtraChargeType chargeType,
    double? amount,
    String? description,
    String? packageId,
    bool isActive = true,
  }) async {
    _check('createCharge:$name:${chargeType.apiValue}:$amount:$packageId');
    return charge(
      id: 'nc',
      serviceId: serviceId,
      packageId: packageId,
      name: name,
      type: chargeType,
      amount: amount,
    );
  }

  @override
  Future<ExtraCharge> updateCharge(
    String id,
    Map<String, dynamic> changes,
  ) async {
    _check('updateCharge:$id');
    lastChanges = changes;
    return charge(id: id);
  }

  @override
  Future<void> deleteCharge(String id) async => _check('deleteCharge:$id');
}

class FakeServiceAreaRepository implements ServiceAreaRepository {
  FakeServiceAreaRepository(this.areas);

  List<ServiceArea> areas;
  ApiException? error;
  final List<String> calls = [];
  Map<String, dynamic>? lastChanges;

  void _check(String call) {
    calls.add(call);
    if (error != null) throw error!;
  }

  @override
  Future<PincodeCheck> checkPincode(String pincode) async {
    _check('check:$pincode');
    final match = areas.where((a) => a.pincode == pincode && a.isActive);
    if (match.isEmpty) {
      return PincodeCheck(pincode: pincode, serviceable: false);
    }
    final a = match.first;
    return PincodeCheck(
      pincode: pincode,
      serviceable: true,
      areaName: a.areaName,
      city: a.city,
      state: a.state,
    );
  }

  @override
  Future<List<ServiceArea>> adminList() async {
    _check('list');
    return areas;
  }

  @override
  Future<ServiceArea> create({
    required String pincode,
    required String areaName,
    required String city,
    required String state,
    bool isActive = true,
  }) async {
    _check('create:$pincode:$areaName:$city:$state:$isActive');
    final created = ServiceArea(
      id: 'a-${areas.length}',
      pincode: pincode,
      areaName: areaName,
      city: city,
      state: state,
      isActive: isActive,
    );
    areas = [...areas, created];
    return created;
  }

  @override
  Future<ServiceArea> update(String id, Map<String, dynamic> changes) async {
    _check('update:$id');
    lastChanges = changes;
    final old = areas.firstWhere((a) => a.id == id);
    final updated = ServiceArea(
      id: old.id,
      pincode: (changes['pincode'] as String?) ?? old.pincode,
      areaName: (changes['area_name'] as String?) ?? old.areaName,
      city: (changes['city'] as String?) ?? old.city,
      state: (changes['state'] as String?) ?? old.state,
      isActive: (changes['is_active'] as bool?) ?? old.isActive,
    );
    areas = [for (final a in areas) a.id == id ? updated : a];
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    _check('delete:$id');
    areas = areas.where((a) => a.id != id).toList();
  }
}

class FakeAvailabilityRepository implements AvailabilityRepository {
  FakeAvailabilityRepository({
    List<TimeSlot>? slots,
    List<AvailabilityException>? exceptions,
  })  : slotList = slots ?? [],
        exceptionList = exceptions ?? [];

  List<TimeSlot> slotList;
  List<AvailabilityException> exceptionList;

  /// What the customer availability endpoint answers.
  List<DayAvailability> days = [];
  ApiException? error;
  final List<String> calls = [];

  void _check(String call) {
    calls.add(call);
    if (error != null) throw error!;
  }

  @override
  Future<List<DayAvailability>> availability(DateTime start, [DateTime? end]) async {
    _check('availability');
    return days;
  }

  @override
  Future<List<TimeSlot>> slots() async {
    _check('slots');
    return slotList;
  }

  @override
  Future<TimeSlot> createSlot({
    required ClockTime start,
    required ClockTime end,
    required int capacity,
    required List<int> daysOfWeek,
    bool isActive = true,
  }) async {
    _check('createSlot:${start.toApi()}-${end.toApi()}:$capacity:${daysOfWeek.join(',')}');
    final created = TimeSlot(
      id: 'sl-${slotList.length}',
      start: start,
      end: end,
      capacity: capacity,
      daysOfWeek: daysOfWeek,
      isActive: isActive,
    );
    slotList = [...slotList, created];
    return created;
  }

  @override
  Future<TimeSlot> updateSlot(String id, Map<String, dynamic> changes) async {
    _check('updateSlot:$id:${changes.keys.join(',')}');
    final old = slotList.firstWhere((s) => s.id == id);
    final updated = TimeSlot(
      id: old.id,
      start: old.start,
      end: old.end,
      capacity: (changes['capacity'] as int?) ?? old.capacity,
      daysOfWeek: old.daysOfWeek,
      isActive: (changes['is_active'] as bool?) ?? old.isActive,
    );
    slotList = [for (final s in slotList) s.id == id ? updated : s];
    return updated;
  }

  @override
  Future<void> deleteSlot(String id) async {
    _check('deleteSlot:$id');
    slotList = slotList.where((s) => s.id != id).toList();
  }

  @override
  Future<List<AvailabilityException>> exceptions(DateTime start, DateTime end) async {
    _check('exceptions');
    return exceptionList;
  }

  @override
  Future<AvailabilityException> createException({
    required DateTime date,
    String? timeSlotId,
    bool isOpen = false,
    int? capacity,
    String? reason,
  }) async {
    _check('createException:$timeSlotId:$isOpen:$capacity:$reason');
    final created = AvailabilityException(
      id: 'ex-${exceptionList.length}',
      date: date,
      timeSlotId: timeSlotId,
      isOpen: isOpen,
      capacity: capacity,
      reason: reason,
    );
    exceptionList = [...exceptionList, created];
    return created;
  }

  @override
  Future<AvailabilityException> updateException(
    String id,
    Map<String, dynamic> changes,
  ) async {
    _check('updateException:$id');
    return exceptionList.firstWhere((e) => e.id == id);
  }

  @override
  Future<void> deleteException(String id) async {
    _check('deleteException:$id');
    exceptionList = exceptionList.where((e) => e.id != id).toList();
  }
}

const conflictServiceError = ApiException(
  type: ApiErrorType.conflict,
  message: 'A service with this name already exists',
  statusCode: 409,
);


/// A tiny but real JPEG header, enough for the type check.
final Uint8List fakeJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

/// Hands back the queued pictures instead of opening the gallery or camera.
class FakeImagePicker implements ImagePickerService {
  /// What the next pick returns (null = the person backed out).
  final List<PickedImage?> queue = [];
  final List<PickSource> sources = [];
  Object? failWith;

  @override
  Future<PickedImage?> pick(PickSource source) async {
    sources.add(source);
    if (failWith != null) throw failWith!;
    return queue.isEmpty ? null : queue.removeAt(0);
  }
}
