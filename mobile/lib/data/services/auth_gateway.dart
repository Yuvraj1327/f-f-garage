import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/auth_failure.dart';
import 'auth_error_mapper.dart';

enum SignUpResult { signedIn, emailConfirmationRequired }

/// The app's only contact point with Supabase Auth. Everything else in the app
/// talks to this interface, which keeps SDK types out of the rest of the code
/// and lets tests substitute a fake.
///
/// Uses the PUBLIC anon key only. Methods throw [AuthFailure].
abstract interface class AuthGateway {
  /// The current access token, or null when signed out.
  String? get accessToken;

  bool get hasSession;

  /// Emits whenever the session ends (explicit sign-out, or the refresh token
  /// was rejected).
  Stream<void> get signedOut;

  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  });

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// A fresh access token; null if the session is over. Throws on transient
  /// failures such as no network.
  Future<String?> refreshAccessToken();

  /// Ends the session on this device. Never throws.
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._auth);

  final GoTrueClient _auth;

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  Stream<void> get signedOut => _auth.onAuthStateChange
      .where((state) => state.event == AuthChangeEvent.signedOut)
      .map((_) {});

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );
      return response.session != null
          ? SignUpResult.signedIn
          : SignUpResult.emailConfirmationRequired;
    } on AuthRetryableFetchException {
      throw AuthFailure.network;
    } on AuthException catch (error) {
      throw _map(error);
    } on SocketException {
      throw AuthFailure.network;
    } on TimeoutException {
      throw AuthFailure.network;
    }
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
    } on AuthRetryableFetchException {
      throw AuthFailure.network;
    } on AuthException catch (error) {
      throw _map(error);
    } on SocketException {
      throw AuthFailure.network;
    } on TimeoutException {
      throw AuthFailure.network;
    }
  }

  @override
  Future<String?> refreshAccessToken() async {
    try {
      final response = await _auth.refreshSession();
      return response.session?.accessToken;
    } on AuthRetryableFetchException {
      rethrow; // transient: the session may still be valid
    } on AuthException {
      return null; // refresh token rejected: the session is over
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthException {
      // The local session is cleared before the server is contacted, so a
      // failed server call changes nothing for the user.
    } on SocketException {
      // Same: offline sign-out still clears this device.
    }
  }

  AuthFailure _map(AuthException error) => mapAuthError(
        message: error.message,
        statusCode: error.statusCode,
        code: error.code,
      );
}

/// Used when the build has no Supabase configuration: the app starts, shows the
/// login screens, and explains why signing in is impossible.
class UnconfiguredAuthGateway implements AuthGateway {
  const UnconfiguredAuthGateway();

  @override
  String? get accessToken => null;

  @override
  bool get hasSession => false;

  @override
  Stream<void> get signedOut => const Stream<void>.empty();

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, dynamic> metadata,
  }) async => throw AuthFailure.notConfigured;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async => throw AuthFailure.notConfigured;

  @override
  Future<String?> refreshAccessToken() async => null;

  @override
  Future<void> signOut() async {}
}
