import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';

/// Raw calls for services, packages and extra charges. Returns JSON.
class CatalogApiService {
  CatalogApiService(this._client);

  final ApiClient _client;

  // ---- customers ----
  Future<List<Map<String, dynamic>>> browse({String? vehicleType}) async {
    return asJsonObjectList(
      await _client.get(
        ApiEndpoints.catalogServices,
        queryParameters: {if (vehicleType != null) 'vehicle_type': vehicleType},
      ),
    );
  }

  Future<Map<String, dynamic>> browseOne(String id) async =>
      asJsonObject(await _client.get(ApiEndpoints.catalogService(id)));

  // ---- admins ----
  Future<List<Map<String, dynamic>>> adminList({String? vehicleType}) async {
    return asJsonObjectList(
      await _client.get(
        ApiEndpoints.adminServices,
        queryParameters: {if (vehicleType != null) 'vehicle_type': vehicleType},
      ),
    );
  }

  Future<Map<String, dynamic>> adminGet(String id) async =>
      asJsonObject(await _client.get(ApiEndpoints.adminService(id)));

  Future<Map<String, dynamic>> createService(Map<String, dynamic> body) async =>
      asJsonObject(await _client.post(ApiEndpoints.adminServices, data: body));

  Future<Map<String, dynamic>> updateService(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.adminService(id), data: body));

  Future<Map<String, dynamic>> createPackage(
    String serviceId,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.adminServicePackages(serviceId), data: body),
      );

  Future<Map<String, dynamic>> updatePackage(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.adminPackage(id), data: body));

  Future<Map<String, dynamic>> createCharge(
    String serviceId,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(
        await _client.post(ApiEndpoints.adminServiceCharges(serviceId), data: body),
      );

  Future<Map<String, dynamic>> updateCharge(
    String id,
    Map<String, dynamic> body,
  ) async =>
      asJsonObject(await _client.patch(ApiEndpoints.adminCharge(id), data: body));

  Future<void> deleteCharge(String id) async {
    await _client.delete(ApiEndpoints.adminCharge(id));
  }
}
