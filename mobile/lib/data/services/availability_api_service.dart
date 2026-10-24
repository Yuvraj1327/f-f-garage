import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls for time slots, date exceptions and availability. Returns JSON.
class AvailabilityApiService {
  AvailabilityApiService(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> availability({
    required String startDate,
    String? endDate,
  }) async =>
      asJsonObjectList(
        await _client.get(
          ApiEndpoints.availability,
          queryParameters: {'start_date': startDate, if (endDate != null) 'end_date': endDate},
        ),
      );

  Future<List<Map<String, dynamic>>> slots() async =>
      asJsonObjectList(await _client.get(ApiEndpoints.adminSlots));

  Future<Map<String, dynamic>> createSlot(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.adminSlots, data: body));

  Future<Map<String, dynamic>> updateSlot(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.adminSlot(id), data: body));

  Future<void> deleteSlot(String id) async {
    await _client.delete(ApiEndpoints.adminSlot(id));
  }

  Future<List<Map<String, dynamic>>> exceptions({
    required String startDate,
    required String endDate,
  }) async =>
      asJsonObjectList(
        await _client.get(
          ApiEndpoints.adminExceptions,
          queryParameters: {'start_date': startDate, 'end_date': endDate},
        ),
      );

  Future<Map<String, dynamic>> createException(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.adminExceptions, data: body));

  Future<Map<String, dynamic>> updateException(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.patch(ApiEndpoints.adminException(id), data: body),
      );

  Future<void> deleteException(String id) async {
    await _client.delete(ApiEndpoints.adminException(id));
  }
}
