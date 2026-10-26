import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/auth_failure.dart';
import '../../core/utils/validators.dart';
import '../models/enums.dart';
import '../models/user_profile.dart';
import '../services/auth_gateway.dart';
import 'profile_repository.dart';

/// How "Continue with Google" ended, with the profile when it signed in.
class GoogleSignInOutcome {
  const GoogleSignInOutcome._(this.result, this.profile);

  const GoogleSignInOutcome.signedIn(UserProfile profile)
      : this._(GoogleSignInResult.signedIn, profile);

  const GoogleSignInOutcome.cancelled()
      : this._(GoogleSignInResult.cancelled, null);

  const GoogleSignInOutcome.redirecting()
      : this._(GoogleSignInResult.redirecting, null);

  final GoogleSignInResult result;

  /// Set only when [result] is [GoogleSignInResult.signedIn].
  final UserProfile? profile;
}

/// Sign-in, sign-up and session restore.
///
/// Supabase proves *who* the user is; the backend profile says *what they may
/// do*. After every sign-in the profile is loaded from the backend and the
/// role is checked against the login screen that was used. A mismatch signs
/// the user straight back out, so a driver can never end up in the customer
/// flow (or the reverse), and only the administrator sign-in opens the admin
/// area (which the backend then enforces again on every request).
///
/// Throws [AuthFailure] for user-facing problems. [restoreSession] throws
/// [ApiException] when the backend cannot be reached, so the caller can offer
/// a retry instead of signing the user out.
class AuthRepository {
  AuthRepository({
    required AuthGateway gateway,
    required ProfileRepository profiles,
    required AppConfig config,
  })  : _gateway = gateway,
        _profiles = profiles,
        _config = config;

  final AuthGateway _gateway;
  final ProfileRepository _profiles;
  final AppConfig _config;

  Future<UserProfile> signInCustomer({
    required String email,
    required String password,
  }) async {
    await _gateway.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return _loadProfileFor(UserRole.customer);
  }

  Future<UserProfile> signInDriver({
    required String driverId,
    required String password,
  }) async {
    try {
      await _gateway.signInWithPassword(
        email: _config.driverEmailFor(driverId),
        password: password,
      );
    } on AuthFailure catch (failure) {
      // Say "driver ID", not "email": drivers never see an email address.
      if (failure.type == AuthFailureType.invalidCredentials) {
        throw AuthFailure.invalidDriverCredentials;
      }
      rethrow;
    }
    return _loadProfileFor(UserRole.driver);
  }

  /// The shared "Driver & Admin Login". [identifier] is a driver ID or an
  /// email address. Supabase proves who the user is, then the backend profile
  /// decides where they go: driver -> driver area, admin -> admin area. A
  /// customer account (or an inactive one) is signed straight back out.
  Future<UserProfile> signInStaff({
    required String identifier,
    required String password,
  }) async {
    final text = identifier.trim();
    final isEmail = text.contains('@');
    try {
      await _gateway.signInWithPassword(
        email: isEmail ? text.toLowerCase() : _config.driverEmailFor(text),
        password: password,
      );
    } on AuthFailure catch (failure) {
      if (failure.type == AuthFailureType.invalidCredentials) {
        throw AuthFailure.invalidStaffCredentials;
      }
      rethrow;
    }
    final UserProfile profile;
    try {
      profile = await _profiles.getMyProfile();
    } on ApiException catch (error) {
      await _gateway.signOut();
      throw _failureFor(error);
    }
    if (profile.role != UserRole.driver && profile.role != UserRole.admin) {
      await _gateway.signOut();
      throw AuthFailure.notStaffAccount;
    }
    if (!profile.isActive) {
      await _gateway.signOut();
      throw AuthFailure.accountDisabled;
    }
    return profile;
  }

  Future<UserProfile> signInAdmin({
    required String email,
    required String password,
  }) async {
    await _gateway.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
    return _loadProfileFor(UserRole.admin);
  }

  /// "Continue with Google" on the customer screens. Supabase creates the
  /// account the first time and signs an existing account in (an account with
  /// the same verified email is linked, not duplicated). The backend profile is
  /// then loaded and must be a customer's: a driver or administrator account is
  /// signed straight back out, exactly as with the password sign-in.
  ///
  /// On Web the browser leaves for Google and returns later; start-up then
  /// restores the session ([restoreSession]) and the router applies the role.
  Future<GoogleSignInOutcome> signInWithGoogle() async {
    final result = await _gateway.signInWithGoogle();
    switch (result) {
      case GoogleSignInResult.cancelled:
        return const GoogleSignInOutcome.cancelled();
      case GoogleSignInResult.redirecting:
        return const GoogleSignInOutcome.redirecting();
      case GoogleSignInResult.signedIn:
        return GoogleSignInOutcome.signedIn(
          await _loadProfileFor(UserRole.customer),
        );
    }
  }

  /// Creates a customer account. Returns the profile when the user is signed
  /// in immediately, or null when the project requires email confirmation
  /// first.
  Future<UserProfile?> registerCustomer({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final metadata = <String, dynamic>{
      'full_name': Validators.normalizeName(fullName),
      if (Validators.normalizedMobile(phone) != null)
        'phone': Validators.normalizedMobile(phone),
    };
    final result = await _gateway.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      metadata: metadata,
    );
    if (result == SignUpResult.emailConfirmationRequired) {
      return null;
    }
    return _loadProfileFor(UserRole.customer);
  }

  /// The profile of a stored session, or null if there is none or it is no
  /// longer valid. Throws [ApiException] if the backend is unreachable.
  Future<UserProfile?> restoreSession() async {
    if (!_gateway.hasSession) {
      return null;
    }
    try {
      final profile = await _profiles.getMyProfile();
      if (!_isAllowedInApp(profile)) {
        await _gateway.signOut();
        return null;
      }
      return profile;
    } on ApiException catch (error) {
      if (error.type == ApiErrorType.unauthorized ||
          error.type == ApiErrorType.forbidden) {
        await _gateway.signOut();
        return null;
      }
      rethrow;
    }
  }

  /// Changes the password of [profile]'s own account after checking the
  /// current one. Drivers have no email of their own: their sign-in address is
  /// built from the driver ID, exactly as at sign-in. Throws [AuthFailure].
  Future<void> changePassword({
    required UserProfile profile,
    required String currentPassword,
    required String newPassword,
  }) {
    final email = (profile.email != null && profile.email!.isNotEmpty)
        ? profile.email!.toLowerCase()
        : (profile.driverLoginId != null && profile.driverLoginId!.isNotEmpty
            ? _config.driverEmailFor(profile.driverLoginId!)
            : null);
    if (email == null) {
      throw AuthFailure.noPasswordSet;
    }
    return _gateway.changePassword(
      email: email,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  Future<void> signOut() => _gateway.signOut();

  Future<UserProfile> _loadProfileFor(UserRole expected) async {
    final UserProfile profile;
    try {
      profile = await _profiles.getMyProfile();
    } on ApiException catch (error) {
      await _gateway.signOut();
      throw _failureFor(error);
    }

    if (profile.role != expected) {
      await _gateway.signOut();
      switch (expected) {
        case UserRole.customer:
          throw AuthFailure.notCustomerAccount;
        case UserRole.driver:
          throw AuthFailure.notDriverAccount;
        case UserRole.admin:
          throw AuthFailure.notAdminAccount;
      }
    }
    if (!profile.isActive) {
      await _gateway.signOut();
      throw AuthFailure.accountDisabled;
    }
    return profile;
  }

  bool _isAllowedInApp(UserProfile profile) => profile.isActive;

  AuthFailure _failureFor(ApiException error) {
    switch (error.type) {
      case ApiErrorType.network:
      case ApiErrorType.timeout:
        return AuthFailure.network;
      case ApiErrorType.forbidden:
        return AuthFailure.accountDisabled;
      case ApiErrorType.unauthorized:
        return AuthFailure.sessionExpired;
      default:
        return AuthFailure(AuthFailureType.unknown, error.message);
    }
  }
}
