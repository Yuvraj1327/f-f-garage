import 'enums.dart';
import 'json_reader.dart';

/// An extra charge that may apply on top of a package (spare part, engine oil...).
class ExtraCharge {
  const ExtraCharge({
    required this.id,
    required this.serviceId,
    required this.chargeType,
    required this.name,
    required this.isActive,
    this.packageId,
    this.description,
    this.amount,
  });

  factory ExtraCharge.fromJson(Map<String, dynamic> json) => ExtraCharge(
        id: JsonReader.string(json, 'id'),
        serviceId: JsonReader.string(json, 'service_id'),
        packageId: JsonReader.optionalString(json, 'package_id'),
        chargeType:
            ExtraChargeType.fromApiValue(JsonReader.string(json, 'charge_type')),
        name: JsonReader.string(json, 'name'),
        description: JsonReader.optionalString(json, 'description'),
        amount: JsonReader.optionalMoney(json, 'amount'),
        isActive: JsonReader.boolean(json, 'is_active'),
      );

  final String id;
  final String serviceId;

  /// Null = applies to every package of the service.
  final String? packageId;
  final ExtraChargeType chargeType;
  final String name;
  final String? description;

  /// Null = charged at actuals (priced on the day).
  final double? amount;
  final bool isActive;
}

class ServicePackage {
  const ServicePackage({
    required this.id,
    required this.serviceId,
    required this.name,
    required this.price,
    required this.inclusions,
    required this.displayOrder,
    required this.isActive,
    required this.extraCharges,
    this.exclusions = const [],
    this.partsPolicy = PartsPolicy.serviceOnly,
    this.description,
    this.originalPrice,
    this.warrantyDays,
    this.partsNote,
    this.estimatedDurationMinutes,
  });

  factory ServicePackage.fromJson(Map<String, dynamic> json) => ServicePackage(
        id: JsonReader.string(json, 'id'),
        serviceId: JsonReader.string(json, 'service_id'),
        name: JsonReader.string(json, 'name'),
        description: JsonReader.optionalString(json, 'description'),
        price: JsonReader.money(json, 'price'),
        originalPrice: JsonReader.optionalMoney(json, 'original_price'),
        inclusions: JsonReader.stringList(json, 'inclusions'),
        exclusions: json['exclusions'] == null
            ? const []
            : JsonReader.stringList(json, 'exclusions'),
        warrantyDays: JsonReader.optionalInteger(json, 'warranty_days'),
        partsPolicy: PartsPolicy.fromApiValue(
          JsonReader.optionalString(json, 'parts_policy') ?? 'service_only',
        ),
        partsNote: JsonReader.optionalString(json, 'parts_note'),
        estimatedDurationMinutes:
            JsonReader.optionalInteger(json, 'estimated_duration_minutes'),
        displayOrder: JsonReader.integer(json, 'display_order'),
        isActive: JsonReader.boolean(json, 'is_active'),
        extraCharges: json.containsKey('extra_charges')
            ? JsonReader.objectList(json, 'extra_charges', ExtraCharge.fromJson)
            : const [],
      );

  final String id;
  final String serviceId;
  final String name;
  final String? description;
  final double price;

  /// The crossed-out price, when the garage shows a discount.
  final double? originalPrice;
  final List<String> inclusions;

  /// What the price does not cover.
  final List<String> exclusions;
  final int? warrantyDays;
  final PartsPolicy partsPolicy;
  final String? partsNote;
  final int? estimatedDurationMinutes;

  bool get hasDiscount => originalPrice != null && originalPrice! > price;

  /// "30 days", "6 months" ... for the warranty chip.
  String? get warrantyLabel {
    final days = warrantyDays;
    if (days == null) return null;
    if (days % 30 == 0 && days >= 60) return '${days ~/ 30} months';
    return days == 1 ? '1 day' : '$days days';
  }
  final int displayOrder;
  final bool isActive;

  /// Charges that apply to this package specifically.
  final List<ExtraCharge> extraCharges;
}

/// A service the garage offers (named `GarageService` to avoid clashing with
/// the many other things called "service" in the code).
class GarageService {
  const GarageService({
    required this.id,
    required this.name,
    required this.vehicleType,
    required this.category,
    required this.displayOrder,
    required this.isActive,
    required this.packages,
    required this.extraCharges,
    this.catalogTab = CatalogTab.package,
    this.description,
    this.repairGroup,
    this.imageUrl,
    this.badge,
  });

  factory GarageService.fromJson(Map<String, dynamic> json) => GarageService(
        id: JsonReader.string(json, 'id'),
        name: JsonReader.string(json, 'name'),
        vehicleType:
            VehicleType.fromApiValue(JsonReader.string(json, 'vehicle_type')),
        category: JsonReader.string(json, 'category'),
        description: JsonReader.optionalString(json, 'description'),
        catalogTab: CatalogTab.fromApiValue(
          JsonReader.optionalString(json, 'catalog_tab') ?? 'package',
        ),
        repairGroup: JsonReader.optionalString(json, 'repair_group'),
        imageUrl: JsonReader.optionalString(json, 'image_url'),
        badge: JsonReader.optionalString(json, 'badge'),
        displayOrder: JsonReader.integer(json, 'display_order'),
        isActive: JsonReader.boolean(json, 'is_active'),
        packages: JsonReader.objectList(
          json,
          'packages',
          ServicePackage.fromJson,
        ),
        extraCharges: JsonReader.objectList(
          json,
          'extra_charges',
          ExtraCharge.fromJson,
        ),
      );

  final String id;
  final String name;
  final VehicleType vehicleType;
  final String category;
  final String? description;

  /// Which tab of the service screen lists it.
  final CatalogTab catalogTab;

  /// For repairs: the filter chip it belongs to (Brakes, Cables ...).
  final String? repairGroup;
  final String? imageUrl;

  /// A short label such as "Popular" or "Best value".
  final String? badge;
  final int displayOrder;
  final bool isActive;
  final List<ServicePackage> packages;

  /// Charges that apply to every package of this service.
  final List<ExtraCharge> extraCharges;

  /// Lowest active package price, for "from ₹..." labels.
  double? get startingPrice {
    final prices = packages.where((p) => p.isActive).map((p) => p.price);
    return prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
  }

  /// Every charge that can apply to [package]: service-wide plus its own.
  List<ExtraCharge> chargesFor(ServicePackage package) => [
        ...extraCharges,
        ...package.extraCharges,
      ];
}
