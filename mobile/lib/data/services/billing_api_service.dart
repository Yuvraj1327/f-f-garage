import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls for the bill, extra charge requests, coupons and refunds.
class BillingApiService {
  BillingApiService(this._client);

  final ApiClient _client;

  // ---- customer ----
  Future<Map<String, dynamic>> bill(String bookingId) async =>
      asJsonObject(await _client.get(ApiEndpoints.bookingBill(bookingId)));

  Future<List<Map<String, dynamic>>> extras(String bookingId) async =>
      asJsonObjectList(
        await _client.get(ApiEndpoints.bookingExtras(bookingId)),
      );

  Future<Map<String, dynamic>> approve(String bookingId, String extraId) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.approveExtra(bookingId, extraId)),
      );

  Future<Map<String, dynamic>> decline(String bookingId, String extraId) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.declineExtra(bookingId, extraId)),
      );

  // ---- driver ----
  Future<List<Map<String, dynamic>>> driverExtras(String bookingId) async =>
      asJsonObjectList(
        await _client.get(ApiEndpoints.driverBookingExtras(bookingId)),
      );

  Future<Map<String, dynamic>> driverRequest(
    String bookingId,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.post(
          ApiEndpoints.driverBookingExtras(bookingId),
          data: body,
        ),
      );

  Future<Map<String, dynamic>> driverWithdraw(
    String bookingId,
    String extraId,
  ) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.driverWithdrawExtra(bookingId, extraId)),
      );

  // ---- admin ----
  Future<Map<String, dynamic>> adminBill(String bookingId) async =>
      asJsonObject(await _client.get(ApiEndpoints.adminBookingBill(bookingId)));

  Future<List<Map<String, dynamic>>> adminExtras(String bookingId) async =>
      asJsonObjectList(
        await _client.get(ApiEndpoints.adminBookingExtras(bookingId)),
      );

  Future<Map<String, dynamic>> adminRequest(
    String bookingId,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.post(
          ApiEndpoints.adminBookingExtras(bookingId),
          data: body,
        ),
      );

  Future<Map<String, dynamic>> adminWithdraw(
    String bookingId,
    String extraId,
  ) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.adminWithdrawExtra(bookingId, extraId)),
      );

  Future<List<Map<String, dynamic>>> coupons() async =>
      asJsonObjectList(await _client.get(ApiEndpoints.adminCoupons));

  Future<Map<String, dynamic>> createCoupon(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.adminCoupons, data: body));

  Future<Map<String, dynamic>> updateCoupon(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.adminCoupon(id), data: body));

  Future<Map<String, dynamic>> recordRefund(
    String paymentId,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.post(
          ApiEndpoints.adminPaymentRefunds(paymentId),
          data: body,
        ),
      );
}
