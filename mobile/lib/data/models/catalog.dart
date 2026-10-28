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
    this.advancePercent,
    this.repeatIntervalDays,
    this.labourCharge,
    this.includedParts = const [],
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
        advancePercent: JsonReader.optionalMoney(json, 'advance_percent'),
        repeatIntervalDays:
            JsonReader.optionalInteger(json, 'repeat_interval_days'),
        labourCharge: JsonReader.optionalMoney(json, 'labour_charge'),
        includedParts: json['included_parts'] == null
            ? const []
            : JsonReader.stringList(json, 'included_parts'),
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

  /// The share paid when booking; null = the garage-wide default.
  final double? advancePercent;

  /// "Every N days": how often the service is worth repeating. Null = as needed.
  final int? repeatIntervalDays;

  /// The labour part of [price].
  final double? labourCharge;

  /// Parts the price already covers.
  final List<String> includedParts;
  final PartsPolicy partsPolicy;
  final String? partsNote;
  final int? estimatedDurationMinutes;

  bool get hasDiscount => originalPrice != null && originalPrice! > price;

  /// "20% OFF" (rounded down), or null when there is no discount.
  String? get discountLabel {
    if (!hasDiscount) return null;
    final percent = ((originalPrice! - price) * 100 / originalPrice!).floor();
    return percent < 1 ? null : '$percent% OFF';
  }

  /// "As needed", or "Every 90 days" / "Every 3 months".
  String get repeatLabel {
    final days = repeatIntervalDays;
    if (days == null) return 'As needed';
    if (days % 30 == 0 && days >= 60) return 'Every ${days ~/ 30} months';
    return days == 1 ? 'Every day' : 'Every $days days';
  }

  /// What is paid when booking, at [defaultPercent] unless the package sets its
  /// own. Only for showing: the server works out the real amount.
  double advanceFor(double defaultPercent) {
    final percent = advancePercent ?? defaultPercent;
    return (price * percent / 100 * 100).round() / 100;
  }

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
    this.shortDescription,
    this.categoryId,
    this.systemKey,
    this.repairGroup,
    this.imageUrl,
    this.bannerUrl,
    this.thumbnailUrl,
    this.partImageUrls = const [],
    this.supportedMakes = const [],
    this.supportedModels = const [],
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
        shortDescription: JsonReader.optionalString(json, 'short_description'),
        categoryId: JsonReader.optionalString(json, 'category_id'),
        systemKey: JsonReader.optionalString(json, 'system_key'),
        imageUrl: JsonReader.optionalString(json, 'image_url'),
        bannerUrl: JsonReader.optionalString(json, 'banner_url'),
        thumbnailUrl: JsonReader.optionalString(json, 'thumbnail_url'),
        partImageUrls: json['part_image_urls'] == null
            ? const []
            : JsonReader.stringList(json, 'part_image_urls'),
        supportedMakes: json['supported_makes'] == null
            ? const []
            : JsonReader.stringList(json, 'supported_makes'),
        supportedModels: json['supported_models'] == null
            ? const []
            : JsonReader.stringList(json, 'supported_models'),
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

  /// One line for the list card; [description] is the long text for the details.
  final String? shortDescription;
  final String? categoryId;

  /// Set on the 3 built-in services (they can be edited and switched off, but
  /// not deleted).
  final String? systemKey;

  /// The older single picture; [thumbnail] falls back to it.
  final String? imageUrl;
  final String? bannerUrl;
  final String? thumbnailUrl;
  final List<String> partImageUrls;

  /// Empty = every vehicle of the type; otherwise only these makes / models.
  final List<String> supportedMakes;
  final List<String> supportedModels;

  /// A short label such as "Popular" or "Best value".
  final String? badge;
  final int displayOrder;
  final bool isActive;
  final List<ServicePackage> packages;

  /// Charges that apply to every package of this service.
  final List<ExtraCharge> extraCharges;

  /// The square picture for lists.
  String? get thumbnail => thumbnailUrl ?? imageUrl;

  /// The wide picture for the top of the details screen.
  String? get banner => bannerUrl ?? thumbnailUrl ?? imageUrl;

  /// What the list card says under the title.
  String? get cardText => shortDescription ?? description;

  /// Whether this service takes a vehicle of this make and model (empty lists
  /// mean every vehicle). The server enforces the same rule when booking.
  bool supports(String make, String model) {
    bool listed(List<String> names, String value) =>
        names.isEmpty ||
        names.any((n) => n.trim().toLowerCase() == value.trim().toLowerCase());
    return listed(supportedMakes, make) && listed(supportedModels, model);
  }

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


/// A category of services, managed by the admin. Each one belongs to a tab of
/// the customer's service screen.
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.name,
    required this.tab,
    required this.displayOrder,
    required this.isActive,
    this.iconKey,
    this.systemKey,
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) => ServiceCategory(
        id: JsonReader.string(json, 'id'),
        name: JsonReader.string(json, 'name'),
        tab: CatalogTab.fromApiValue(JsonReader.string(json, 'tab')),
        iconKey: JsonReader.optionalString(json, 'icon_key'),
        displayOrder: JsonReader.integer(json, 'display_order'),
        isActive: JsonReader.boolean(json, 'is_active'),
        systemKey: JsonReader.optionalString(json, 'system_key'),
      );

  final String id;
  final String name;
  final CatalogTab tab;
  final String? iconKey;
  final int displayOrder;
  final bool isActive;

  /// Built-in categories keep their tab.
  final String? systemKey;
}
