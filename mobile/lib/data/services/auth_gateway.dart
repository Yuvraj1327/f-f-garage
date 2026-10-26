import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/network/auth_failure.dart';
import 'auth_error_mapper.dart';
import 'google_identity.dart';

enum SignUpResult { signedIn, emailConfirmationRequired }

/// How a "Continue with Google" attempt ended (failures throw [AuthFailure]).
enum GoogleSignInResult {
  /// A Supabase session now exists (Android / iOS).
  signedIn,

  /// The user closed Google's account chooser. Not an error.
  cancelled,

  /// Flutter Web: the browser is being sent to Google and will come back to
  /// this app with a session, which start-up restores like any other.
  redirecting,
}

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

  /// Signs in (or up: Supabase creates the account on first use) with Google.
  /// Android / iOS show Google's account chooser and hand the ID token to
  /// Supabase; Web redirects the browser through Supabase's OAuth flow.
  Future<GoogleSignInResult> signInWithGoogle();

  /// Changes the signed-in user's password. The current password is checked
  /// first (by signing in with it again), so a stolen unlocked phone cannot
  /// silently take over the account. Throws [AuthFailure].
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  });

  /// A fresh access token; null if the session is over. Throws on transient
  /// failures such as no network.
  Future<String?> refreshAccessToken();

  /// Ends the session on this device. Never throws.
  Future<void> signOut();
}

class SupabaseAuthGateway implements AuthGateway {
  /// [google] is the phone's Google account chooser; null when this build has no
  /// Google client IDs (or on Web, which redirects instead).
  /// [webRedirectUrl] is where Google sends the browser back to on Web.
  SupabaseAuthGateway(
    this._auth, {
    GoogleIdentityProvider? google,
    bool? isWeb,
    String Function()? webRedirectUrl,
  })  : _google = google,
        _isWeb = isWeb ?? kIsWeb,
        _webRedirectUrl = webRedirectUrl ?? _currentOrigin;

  final GoTrueClient _auth;
  final GoogleIdentityProvider? _google;
  final bool _isWeb;
  final String Function() _webRedirectUrl;

  static String _currentOrigin() => Uri.base.origin;

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
  Future<GoogleSignInResult> signInWithGoogle() async {
    try {
      if (_isWeb) {
        // Full-page redirect to Google and back. The provider must be enabled
        // in Supabase and the redirect URL allow-listed (see the README).
        await _auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: _webRedirectUrl(),
        );
        return GoogleSignInResult.redirecting;
      }
      final google = _google;
      if (google == null) {
        throw AuthFailure.googleNotConfigured;
      }
      final credential = await google.authenticate();
      if (credential == null) {
        return GoogleSignInResult.cancelled;
      }
      await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: credential.idToken,
        accessToken: credential.accessToken,
      );
      return GoogleSignInResult.signedIn;
    } on AuthRetryableFetchException {
      throw AuthFailure.network;
    } on AuthException catch (error) {
      throw _mapGoogle(error);
    } on SocketException {
      throw AuthFailure.network;
    } on TimeoutException {
      throw AuthFailure.network;
    }
  }

  @override
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      try {
        await _auth.signInWithPassword(email: email, password: currentPassword);
      } on AuthRetryableFetchException {
        rethrow;
      } on AuthException catch (error) {
        final failure = _map(error);
        throw failure.type == AuthFailureType.invalidCredentials
            ? AuthFailure.wrongCurrentPassword
            : failure;
      }
      await _auth.updateUser(UserAttributes(password: newPassword));
    } on AuthRetryableFetchException {
      throw AuthFailure.network;
    } on AuthException catch (error) {
      if ((error.code ?? '') == 'same_password' ||
          error.message.toLowerCase().contains('different from the old')) {
        throw AuthFailure.samePassword;
      }
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
    // Forget the Google account too, so the next sign-in offers the chooser.
    await _google?.signOut();
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

  /// A Supabase error during Google sign-in. Anything the mapper does not
  /// recognise is reported as a Google problem, not "wrong password".
  AuthFailure _mapGoogle(AuthException error) {
    final failure = _map(error);
    return failure.type == AuthFailureType.unknown
        ? AuthFailure.googleFailed
        : failure;
  }
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
  Future<GoogleSignInResult> signInWithGoogle() async =>
      throw AuthFailure.notConfigured;

  @override
  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async => throw AuthFailure.notConfigured;

  @override
  Future<String?> refreshAccessToken() async => null;

  @override
  Future<void> signOut() async {}
}
