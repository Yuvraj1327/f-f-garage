import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls to the payment endpoints. Returns JSON; no model mapping here.
class PaymentApiService {
  PaymentApiService(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> start(String bookingId) async => asJsonObject(
        await _client.post(ApiEndpoints.bookingPayments(bookingId)),
      );

  Future<Map<String, dynamic>> verify(
    String paymentId,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.verifyPayment(paymentId), data: body),
      );

  Future<Map<String, dynamic>> cancel(String paymentId) async => asJsonObject(
        await _client.post(ApiEndpoints.cancelPayment(paymentId)),
      );

  Future<Map<String, dynamic>> get(String paymentId) async =>
      asJsonObject(await _client.get(ApiEndpoints.payment(paymentId)));

  Future<List<Map<String, dynamic>>> forBooking(String bookingId) async =>
      asJsonObjectList(
        await _client.get(ApiEndpoints.bookingPayments(bookingId)),
      );
}
