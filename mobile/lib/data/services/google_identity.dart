import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/network/auth_failure.dart';

/// What Google hands back after the user picks an account on the phone.
class GoogleCredential {
  const GoogleCredential({required this.idToken, this.accessToken});

  /// A JWT signed by Google. Supabase verifies it; the app never decodes it.
  final String idToken;
  final String? accessToken;
}

/// The phone's "choose a Google account" flow, behind a small interface so no
/// plugin type reaches the rest of the app and tests can substitute a fake.
///
/// Used on Android and iOS. Flutter Web signs in through a Supabase OAuth
/// redirect instead (see [SupabaseAuthGateway.signInWithGoogle]).
abstract interface class GoogleIdentityProvider {
  /// Shows Google's account chooser. Returns null when the user closed it
  /// without choosing (not an error). Throws [AuthFailure] for real problems.
  Future<GoogleCredential?> authenticate();

  /// Forgets the chosen account so the next sign-in shows the chooser again.
  /// Never throws.
  Future<void> signOut();
}

/// [GoogleIdentityProvider] on top of the `google_sign_in` plugin (6.x API).
///
/// [serverClientId] is the *Web* client ID: Google then issues an ID token
/// whose audience is that client, which is what Supabase checks. [clientId] is
/// only used on iOS.
class PluginGoogleIdentityProvider implements GoogleIdentityProvider {
  PluginGoogleIdentityProvider({
    required String serverClientId,
    String? clientId,
    GoogleSignIn? plugin,
  }) : _google = plugin ??
            GoogleSignIn(
              clientId: clientId,
              serverClientId: serverClientId,
              scopes: const ['email', 'profile'],
            );

  final GoogleSignIn _google;

  @override
  Future<GoogleCredential?> authenticate() async {
    try {
      // A previous account would otherwise be reused silently, which is wrong
      // after "Sign out": the user expects to be able to pick another account.
      await _google.signOut();
      final account = await _google.signIn();
      if (account == null) {
        return null; // closed the chooser
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        // Happens when serverClientId is missing or wrong.
        throw AuthFailure.googleNotConfigured;
      }
      return GoogleCredential(idToken: idToken, accessToken: auth.accessToken);
    } on PlatformException catch (error) {
      if (error.code == 'sign_in_canceled') {
        return null; // some plugin versions report "closed" as an error
      }
      throw mapGoogleError(error.code, error.message);
    } on TimeoutException {
      throw AuthFailure.network;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // Nothing to clear, or the plugin is unavailable: either way we are out.
    }
  }
}

/// Turns the plugin's error code into a message that is safe to show.
///
/// Codes (google_sign_in): `sign_in_canceled`, `network_error`, `sign_in_failed`
/// (Android "10" = wrong SHA-1 / client ID, "12500" = Play services problem),
/// `channel-error` (plugin not set up on this platform).
AuthFailure mapGoogleError(String code, [String? message]) {
  final text = '$code ${message ?? ''}'.toLowerCase();
  if (text.contains('network')) {
    return AuthFailure.network;
  }
  if (text.contains('developer_error') ||
      text.contains(' 10:') ||
      text.contains('apiexception: 10') ||
      text.contains('channel-error') ||
      text.contains('clientid') ||
      text.contains('missing')) {
    return AuthFailure.googleNotConfigured;
  }
  return AuthFailure.googleFailed;
}
