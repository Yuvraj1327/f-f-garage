import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/auth_failure.dart';
import '../../../core/providers/core_providers.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/providers/data_providers.dart';
import '../../../data/services/auth_gateway.dart' show GoogleSignInResult;

enum AuthStatus {
  /// Checking for a stored session at start-up.
  unknown,
  unauthenticated,
  authenticated,

  /// A stored session exists but the backend could not be reached to confirm it.
  connectionError,
}

/// (Named to avoid a clash with Supabase's own `AuthState`.)
class AppAuthState {
  const AppAuthState._(this.status, {this.profile, this.notice});

  const AppAuthState.unknown() : this._(AuthStatus.unknown);

  const AppAuthState.unauthenticated({String? notice})
      : this._(AuthStatus.unauthenticated, notice: notice);

  const AppAuthState.authenticated(UserProfile profile)
      : this._(AuthStatus.authenticated, profile: profile);

  const AppAuthState.connectionError() : this._(AuthStatus.connectionError);

  final AuthStatus status;

  /// Set only when [status] is [AuthStatus.authenticated].
  final UserProfile? profile;

  /// A message for the login screen, e.g. "Your session has expired".
  final String? notice;

  UserRole? get role => profile?.role;
}

/// Owns the signed-in user for the whole app. The router watches this to decide
/// which screens are reachable.
class AuthController extends Notifier<AppAuthState> {
  StreamSubscription<void>? _expiredSub;
  StreamSubscription<void>? _signedOutSub;

  @override
  AppAuthState build() {
    final events = ref.watch(sessionEventsProvider);
    final gateway = ref.watch(authGatewayProvider);

    // The network layer reports a dead session (refresh failed / still 401).
    _expiredSub = events.expired.listen((_) => _endSession(expired: true));
    // The SDK reports that the session is gone (e.g. refresh token revoked).
    _signedOutSub = gateway.signedOut.listen((_) => _endSession());
    ref.onDispose(() {
      _expiredSub?.cancel();
      _signedOutSub?.cancel();
    });

    Future.microtask(restoreSession);
    return const AppAuthState.unknown();
  }

  Future<void> restoreSession() async {
    state = const AppAuthState.unknown();
    try {
      final profile = await ref.read(authRepositoryProvider).restoreSession();
      state = profile == null
          ? const AppAuthState.unauthenticated()
          : AppAuthState.authenticated(profile);
    } on ApiException {
      state = const AppAuthState.connectionError();
    }
  }

  /// Throws [AuthFailure].
  Future<void> signInCustomer({
    required String email,
    required String password,
  }) async {
    final profile = await ref
        .read(authRepositoryProvider)
        .signInCustomer(email: email, password: password);
    state = AppAuthState.authenticated(profile);
  }

  /// Throws [AuthFailure].
  Future<void> signInDriver({
    required String driverId,
    required String password,
  }) async {
    final profile = await ref
        .read(authRepositoryProvider)
        .signInDriver(driverId: driverId, password: password);
    state = AppAuthState.authenticated(profile);
  }

  /// Throws [AuthFailure].
  Future<void> signInAdmin({
    required String email,
    required String password,
  }) async {
    final profile = await ref
        .read(authRepositoryProvider)
        .signInAdmin(email: email, password: password);
    state = AppAuthState.authenticated(profile);
  }

  /// "Continue with Google". Returns how it ended; a user who closed Google's
  /// chooser gets [GoogleSignInResult.cancelled] and nothing changes. Throws
  /// [AuthFailure].
  Future<GoogleSignInResult> signInWithGoogle() async {
    final outcome = await ref.read(authRepositoryProvider).signInWithGoogle();
    final profile = outcome.profile;
    if (profile != null) {
      state = AppAuthState.authenticated(profile);
    }
    return outcome.result;
  }

  /// Returns true when the user is signed in, false when they must confirm
  /// their email first. Throws [AuthFailure].
  Future<bool> registerCustomer({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final profile = await ref.read(authRepositoryProvider).registerCustomer(
          fullName: fullName,
          email: email,
          phone: phone,
          password: password,
        );
    if (profile == null) {
      return false;
    }
    state = AppAuthState.authenticated(profile);
    return true;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    _endSession();
  }

  /// Called after the user edits their profile.
  void profileUpdated(UserProfile profile) {
    if (state.status == AuthStatus.authenticated) {
      state = AppAuthState.authenticated(profile);
    }
  }

  void _endSession({bool expired = false}) {
    // A sign-out that arrives while still checking, or after the user is
    // already signed out, changes nothing.
    if (state.status == AuthStatus.unauthenticated && !expired) {
      return;
    }
    final wasSignedIn = state.status == AuthStatus.authenticated;
    state = AppAuthState.unauthenticated(
      notice: expired && wasSignedIn ? AuthFailure.sessionExpired.message : null,
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AppAuthState>(AuthController.new);
