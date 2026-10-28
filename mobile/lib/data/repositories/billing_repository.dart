import '../../core/network/api_exception.dart';
import '../models/billing.dart';
import '../models/coupon.dart';
import '../models/enums.dart';
import '../services/billing_api_service.dart';

/// The bill, extra charge requests, coupons and refunds. Throws
/// [ApiException] only. Amounts are always the server's.
class BillingRepository {
  BillingRepository(this._service);

  final BillingApiService _service;

  // ---- customer ----
  Future<Bill> bill(String bookingId) async =>
      _parse(await _service.bill(bookingId), Bill.fromJson);

  Future<List<ExtraRequest>> extras(String bookingId) async =>
      _parseAll(await _service.extras(bookingId), ExtraRequest.fromJson);

  Future<ExtraRequest> approve(String bookingId, String extraId) async =>
      _parse(await _service.approve(bookingId, extraId), ExtraRequest.fromJson);

  Future<ExtraRequest> decline(String bookingId, String extraId) async =>
      _parse(await _service.decline(bookingId, extraId), ExtraRequest.fromJson);

  // ---- driver ----
  Future<List<ExtraRequest>> driverExtras(String bookingId) async =>
      _parseAll(await _service.driverExtras(bookingId), ExtraRequest.fromJson);

  Future<ExtraRequest> driverRequest(
    String bookingId, {
    required String name,
    required double amount,
    ExtraChargeType chargeType = ExtraChargeType.sparePart,
    String? description,
  }) async =>
      _parse(
        await _service.driverRequest(
          bookingId,
          _extraBody(name, amount, chargeType, description),
        ),
        ExtraRequest.fromJson,
      );

  Future<ExtraRequest> driverWithdraw(String bookingId, String extraId) async =>
      _parse(
        await _service.driverWithdraw(bookingId, extraId),
        ExtraRequest.fromJson,
      );

  // ---- admin ----
  Future<Bill> adminBill(String bookingId) async =>
      _parse(await _service.adminBill(bookingId), Bill.fromJson);

  Future<List<ExtraRequest>> adminExtras(String bookingId) async =>
      _parseAll(await _service.adminExtras(bookingId), ExtraRequest.fromJson);

  Future<ExtraRequest> adminRequest(
    String bookingId, {
    required String name,
    required double amount,
    ExtraChargeType chargeType = ExtraChargeType.sparePart,
    String? description,
  }) async =>
      _parse(
        await _service.adminRequest(
          bookingId,
          _extraBody(name, amount, chargeType, description),
        ),
        ExtraRequest.fromJson,
      );

  Future<ExtraRequest> adminWithdraw(String bookingId, String extraId) async =>
      _parse(
        await _service.adminWithdraw(bookingId, extraId),
        ExtraRequest.fromJson,
      );

  Future<List<Coupon>> coupons() async =>
      _parseAll(await _service.coupons(), Coupon.fromJson);

  Future<Coupon> createCoupon({
    required String code,
    required String discountType,
    required double discountValue,
    String? description,
    double? maxDiscount,
    double minOrderAmount = 0,
    DateTime? endsAt,
    int? usageLimit,
    int perCustomerLimit = 1,
    bool isActive = true,
  }) async =>
      _parse(
        await _service.createCoupon({
          'code': code.trim(),
          'discount_type': discountType,
          'discount_value': discountValue.toStringAsFixed(2),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          if (maxDiscount != null) 'max_discount': maxDiscount.toStringAsFixed(2),
          'min_order_amount': minOrderAmount.toStringAsFixed(2),
          if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
          if (usageLimit != null) 'usage_limit': usageLimit,
          'per_customer_limit': perCustomerLimit,
          'is_active': isActive,
        }),
        Coupon.fromJson,
      );

  /// [changes] holds only what changed, using the API's field names.
  Future<Coupon> updateCoupon(String id, Map<String, dynamic> changes) async =>
      _parse(await _service.updateCoupon(id, changes), Coupon.fromJson);

  /// Records a refund the admin already made in the payment gateway's
  /// dashboard. This app moves no money.
  Future<void> recordRefund(
    String paymentId, {
    required double amount,
    String? note,
  }) async {
    await _service.recordRefund(paymentId, {
      'amount': amount.toStringAsFixed(2),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Map<String, dynamic> _extraBody(
    String name,
    double amount,
    ExtraChargeType type,
    String? description,
  ) =>
      {
        'name': name.trim(),
        'amount': amount.toStringAsFixed(2),
        'charge_type': type.apiValue,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
      };

  List<T> _parseAll<T>(
    List<Map<String, dynamic>> rows,
    T Function(Map<String, dynamic>) parse,
  ) {
    try {
      return rows.map(parse).toList();
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }

  T _parse<T>(Map<String, dynamic> json, T Function(Map<String, dynamic>) parse) {
    try {
      return parse(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
