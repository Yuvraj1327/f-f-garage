import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/auth_gateway.dart';
import '../../data/services/google_identity.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import '../network/session_events.dart';

/// App configuration from `.env`. `main.dart` overrides this with the validated
/// instance; tests override it with fixed values.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromDotenv(),
);

/// Announces "the session is no longer valid" from the network layer.
final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// The phone's Google account chooser, or null when this build cannot offer it:
/// Web (it redirects through Supabase instead) or missing Google client IDs in
/// `.env`. "Continue with Google" then explains that it is not set up.
final googleIdentityProvider = Provider<GoogleIdentityProvider?>((ref) {
  final config = ref.watch(appConfigProvider);
  if (kIsWeb ||
      !config.googleSignInConfigured(
        isWeb: false,
        platform: defaultTargetPlatform,
      )) {
    return null;
  }
  return PluginGoogleIdentityProvider(
    serverClientId: config.googleClientIdWeb,
    clientId: defaultTargetPlatform == TargetPlatform.iOS
        ? config.googleClientIdIos
        : null,
  );
});

/// The app's only contact with Supabase Auth. Falls back to an inert gateway
/// when there is no Supabase configuration, so the app still starts.
final authGatewayProvider = Provider<AuthGateway>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.isSupabaseConfigured) {
    return const UnconfiguredAuthGateway();
  }
  return SupabaseAuthGateway(
    Supabase.instance.client.auth,
    google: ref.watch(googleIdentityProvider),
  );
});

/// Where the API client gets the bearer token.
final accessTokenReaderProvider = Provider<AccessTokenReader>((ref) {
  final gateway = ref.watch(authGatewayProvider);
  return () async => gateway.accessToken;
});

/// The one shared backend client. Services receive it from here.
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final gateway = ref.watch(authGatewayProvider);
  final events = ref.watch(sessionEventsProvider);
  return ApiClient(
    baseUrl: config.apiBaseUrl,
    accessTokenReader: ref.watch(accessTokenReaderProvider),
    refreshSession: gateway.refreshAccessToken,
    onSessionExpired: events.notifyExpired,
  );
});
