import 'json_reader.dart';

/// A discount code, as the admin manages it.
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minOrderAmount,
    required this.perCustomerLimit,
    required this.isActive,
    required this.timesUsed,
    this.description,
    this.maxDiscount,
    this.startsAt,
    this.endsAt,
    this.usageLimit,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
        id: JsonReader.string(json, 'id'),
        code: JsonReader.string(json, 'code'),
        description: JsonReader.optionalString(json, 'description'),
        discountType: JsonReader.string(json, 'discount_type'),
        discountValue: JsonReader.money(json, 'discount_value'),
        maxDiscount: JsonReader.optionalMoney(json, 'max_discount'),
        minOrderAmount: JsonReader.money(json, 'min_order_amount'),
        startsAt: _date(json, 'starts_at'),
        endsAt: _date(json, 'ends_at'),
        usageLimit: JsonReader.optionalInteger(json, 'usage_limit'),
        perCustomerLimit: JsonReader.integer(json, 'per_customer_limit'),
        isActive: JsonReader.boolean(json, 'is_active'),
        timesUsed: JsonReader.optionalInteger(json, 'times_used') ?? 0,
      );

  final String id;
  final String code;
  final String? description;

  /// 'percent' or 'flat'.
  final String discountType;
  final double discountValue;
  final double? maxDiscount;
  final double minOrderAmount;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? usageLimit;
  final int perCustomerLimit;
  final bool isActive;
  final int timesUsed;

  bool get isPercent => discountType == 'percent';

  /// "10% off" or "₹100 off".
  String get offerLabel {
    final value = discountValue == discountValue.roundToDouble()
        ? discountValue.toStringAsFixed(0)
        : discountValue.toStringAsFixed(2);
    return isPercent ? '$value% off' : '₹$value off';
  }
}

DateTime? _date(Map<String, dynamic> json, String key) {
  final text = JsonReader.optionalString(json, key);
  return text == null ? null : DateTime.parse(text);
}
