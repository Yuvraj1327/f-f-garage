import '../../core/network/api_exception.dart';
import '../models/support_contact.dart';
import '../services/support_api_service.dart';

/// The garage's contact details. Throws [ApiException] only.
class SupportRepository {
  SupportRepository(this._service);

  final SupportApiService _service;

  Future<SupportContact> contact() async {
    final json = await _service.contact();
    try {
      return SupportContact.fromJson(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
