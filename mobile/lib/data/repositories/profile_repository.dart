import '../../core/network/api_exception.dart';
import '../models/user_profile.dart';
import '../services/profile_api_service.dart';

/// The signed-in user's own profile. Throws [ApiException] only.
class ProfileRepository {
  ProfileRepository(this._service);

  final ProfileApiService _service;

  Future<UserProfile> getMyProfile() async {
    return _parse(await _service.fetchMyProfile());
  }

  /// Sends only the fields that are given. The backend accepts these two for
  /// customers and rejects anything else.
  Future<UserProfile> updateMyProfile({String? fullName, String? phone}) async {
    final changes = <String, dynamic>{
      if (fullName != null) 'full_name': fullName,
      if (phone != null) 'phone': phone,
    };
    return _parse(await _service.updateMyProfile(changes));
  }

  UserProfile _parse(Map<String, dynamic> json) {
    try {
      return UserProfile.fromJson(json);
    } on FormatException {
      throw ApiException.invalidResponse();
    }
  }
}
