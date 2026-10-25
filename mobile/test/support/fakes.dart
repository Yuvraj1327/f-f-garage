import 'dart:async';

import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/models/user_profile.dart';
import 'package:ff_garage/data/repositories/profile_repository.dart';
import 'package:ff_garage/data/services/auth_gateway.dart';

UserProfile profileFor(
  UserRole role, {
  bool isActive = true,
  String? fullName = 'Test User',
}) =>
    UserProfile(
      id: '11111111-1111-1111-1111-111111111111',
      role: role,
      isActive: isActive,
      fullName: fullName,
      phone: '+919876543210',
      email: role == UserRole.driver ? null : 'user@example.com',
      driverLoginId: role == UserRole.driver ? 'ravi01' : null,
    );

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.hasStoredSession = false});

  bool hasStoredSession;
  AuthFailure? signInError;
  AuthFailure? signUpError;
  SignUpResult signUpResult = SignUpResult.signedIn;
  String? lastEmail;
  String? lastPassword;
  Map<String, dynamic>? lastMetadata;
  int signOutCalls = 0;

  /// What the next "Continue with Google" does. [googleError] wins when set.
  GoogleSignInResult googleResult = GoogleSignInResult.signedIn;
  AuthFailure? googleError;
  int googleCalls = 0;
  final StreamController<void> _signedOut = StreamController<void>.broadcast();

  @override
  String? get accessToken => hasStoredSession ? 'token' : null;

  @override
  bool get hasSession => hasStoredSession;

  @override
  Stream<void> get signedOut => _signedOut.stream;

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) async {
    if (signUpError != null) throw signUpError!;
    lastEmail = email;
    lastPassword = password;
    lastMetadata = metadata;
    hasStoredSession = signUpResult == SignUpResult.signedIn;
    return signUpResult;
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (signInError != null) throw signInError!;
    lastEmail = email;
    lastPassword = password;
    hasStoredSession = true;
  }

  @override
  Future<GoogleSignInResult> signInWithGoogle() async {
    googleCalls += 1;
    if (googleError != null) throw googleError!;
    hasStoredSession = googleResult == GoogleSignInResult.signedIn;
    return googleResult;
  }

  @override
  Future<String?> refreshAccessToken() async => hasStoredSession ? 'token' : null;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    hasStoredSession = false;
    _signedOut.add(null);
  }
}

class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository(this.profile);

  UserProfile profile;
  ApiException? error;
  String? lastFullName;
  String? lastPhone;

  @override
  Future<UserProfile> getMyProfile() async {
    if (error != null) throw error!;
    return profile;
  }

  @override
  Future<UserProfile> updateMyProfile({String? fullName, String? phone}) async {
    if (error != null) throw error!;
    lastFullName = fullName;
    lastPhone = phone;
    profile = profile.copyWith(fullName: fullName, phone: phone);
    return profile;
  }
}

const networkError = ApiException(
  type: ApiErrorType.network,
  message: 'Unable to reach the server.',
);
const unauthorizedError = ApiException(
  type: ApiErrorType.unauthorized,
  message: 'Invalid token',
  statusCode: 401,
);
const forbiddenError = ApiException(
  type: ApiErrorType.forbidden,
  message: 'No access',
  statusCode: 403,
);
