import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/data/services/auth_error_mapper.dart';
import 'package:ff_garage/data/services/google_identity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

class _FakeAuth implements GoogleSignInAuthentication {
  _FakeAuth(this.idToken, this.accessToken);

  @override
  final String? idToken;
  @override
  final String? accessToken;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccount implements GoogleSignInAccount {
  _FakeAccount(this._auth);

  final _FakeAuth _auth;

  @override
  Future<GoogleSignInAuthentication> get authentication async => _auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGoogleSignIn implements GoogleSignIn {
  GoogleSignInAccount? account;
  Object? error;
  int signOuts = 0;

  @override
  Future<GoogleSignInAccount?> signIn() async {
    if (error != null) throw error!;
    return account;
  }

  @override
  Future<GoogleSignInAccount?> signOut() async {
    signOuts += 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PluginGoogleIdentityProvider', () {
    late _FakeGoogleSignIn plugin;
    late PluginGoogleIdentityProvider provider;

    setUp(() {
      plugin = _FakeGoogleSignIn();
      provider = PluginGoogleIdentityProvider(
        serverClientId: 'web-client',
        plugin: plugin,
      );
    });

    test('returns the ID and access token the user chose', () async {
      plugin.account = _FakeAccount(_FakeAuth('id-token', 'access-token'));
      final credential = await provider.authenticate();
      expect(credential!.idToken, 'id-token');
      expect(credential.accessToken, 'access-token');
      // The previous account is forgotten first so the chooser always shows.
      expect(plugin.signOuts, 1);
    });

    test('closing the chooser returns null', () async {
      plugin.account = null;
      expect(await provider.authenticate(), isNull);
    });

    test('a "canceled" error from the plugin also counts as closing',
        () async {
      plugin.error = PlatformException(code: 'sign_in_canceled');
      expect(await provider.authenticate(), isNull);
    });

    test('a missing ID token means the client IDs are not set up', () async {
      plugin.account = _FakeAccount(_FakeAuth(null, 'access'));
      await expectLater(
        provider.authenticate(),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.type,
            'type',
            AuthFailureType.googleNotConfigured,
          ),
        ),
      );
    });

    test('plugin errors become friendly failures', () async {
      plugin.error = PlatformException(code: 'network_error');
      await expectLater(
        provider.authenticate(),
        throwsA(isA<AuthFailure>().having((f) => f.type, 'type', AuthFailureType.network)),
      );
      plugin.error = PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 10: ',
      );
      await expectLater(
        provider.authenticate(),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.type,
            'type',
            AuthFailureType.googleNotConfigured,
          ),
        ),
      );
      plugin.error = PlatformException(code: 'something_else');
      await expectLater(
        provider.authenticate(),
        throwsA(isA<AuthFailure>().having((f) => f.type, 'type', AuthFailureType.googleFailed)),
      );
    });

    test('signOut never throws', () async {
      plugin.error = null;
      await provider.signOut();
      expect(plugin.signOuts, 1);
    });
  });

  group('mapAuthError for Google', () {
    test('a provider that is switched off in Supabase', () {
      expect(
        mapAuthError(message: 'Unsupported provider: provider is not enabled')
            .type,
        AuthFailureType.googleNotConfigured,
      );
      expect(
        mapAuthError(message: 'x', code: 'validation_failed').type,
        AuthFailureType.googleNotConfigured,
      );
    });

    test('a rejected token', () {
      expect(
        mapAuthError(message: 'Nonces mismatch').type,
        AuthFailureType.googleFailed,
      );
      expect(
        mapAuthError(message: 'x', code: 'bad_jwt').type,
        AuthFailureType.googleFailed,
      );
    });

    test('existing mappings are unchanged', () {
      expect(
        mapAuthError(message: 'Invalid login credentials').type,
        AuthFailureType.invalidCredentials,
      );
    });
  });

  group('AppConfig Google settings', () {
    AppConfig config(Map<String, String> extra) => AppConfig.fromMap({
          'SUPABASE_URL': 'https://p.supabase.co',
          'SUPABASE_ANON_KEY': 'anon',
          ...extra,
        });

    test('reads the three client IDs', () {
      final c = config({
        'GOOGLE_CLIENT_ID_WEB': 'web.apps.googleusercontent.com',
        'GOOGLE_CLIENT_ID_ANDROID': 'android.apps.googleusercontent.com',
        'GOOGLE_CLIENT_ID_IOS': 'ios.apps.googleusercontent.com',
      });
      expect(c.googleClientIdWeb, 'web.apps.googleusercontent.com');
      expect(c.googleClientIdAndroid, 'android.apps.googleusercontent.com');
      expect(c.googleClientIdIos, 'ios.apps.googleusercontent.com');
      expect(c.isValid, isTrue);
    });

    test('placeholders from .env.example count as not set up', () {
      final c = config({
        'GOOGLE_CLIENT_ID_WEB': 'YOUR-WEB-CLIENT-ID.apps.googleusercontent.com',
        'GOOGLE_CLIENT_ID_ANDROID': 'YOUR-ANDROID-CLIENT-ID',
      });
      expect(c.googleClientIdWeb, isEmpty);
      expect(c.googleClientIdAndroid, isEmpty);
    });

    test('availability per platform', () {
      final none = config({});
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          none.googleSignInConfigured(isWeb: false, platform: platform),
          isFalse,
        );
      }
      // Web redirects through Supabase, so it needs nothing in .env.
      expect(
        none.googleSignInConfigured(isWeb: true, platform: TargetPlatform.android),
        isTrue,
      );

      final android = config({
        'GOOGLE_CLIENT_ID_WEB': 'w',
        'GOOGLE_CLIENT_ID_ANDROID': 'a',
      });
      expect(
        android.googleSignInConfigured(isWeb: false, platform: TargetPlatform.android),
        isTrue,
      );
      expect(
        android.googleSignInConfigured(isWeb: false, platform: TargetPlatform.iOS),
        isFalse,
      );

      final ios = config({
        'GOOGLE_CLIENT_ID_WEB': 'w',
        'GOOGLE_CLIENT_ID_IOS': 'i',
      });
      expect(
        ios.googleSignInConfigured(isWeb: false, platform: TargetPlatform.iOS),
        isTrue,
      );
      // The Web client ID alone is not enough on a phone.
      expect(
        config({'GOOGLE_CLIENT_ID_WEB': 'w'})
            .googleSignInConfigured(isWeb: false, platform: TargetPlatform.android),
        isFalse,
      );
    });

    test('a Google client secret in .env is still refused', () {
      final c = config({'GOOGLE_CLIENT_SECRET': 'GOCSPX-xxxx'});
      expect(c.isValid, isFalse);
      expect(c.forbiddenKeys, ['GOOGLE_CLIENT_SECRET']);
    });

    test('maps keys per platform', () {
      final c = config({'GOOGLE_MAPS_KEY_ANDROID': 'k'});
      expect(
        c.mapsConfigured(isWeb: false, platform: TargetPlatform.android),
        isTrue,
      );
      expect(c.mapsConfigured(isWeb: false, platform: TargetPlatform.iOS), isFalse);
      expect(c.mapsConfigured(isWeb: true, platform: TargetPlatform.android), isFalse);
      expect(
        config({'GOOGLE_MAPS_KEY_WEB': 'YOUR-WEB-MAPS-KEY'})
            .mapsConfigured(isWeb: true, platform: TargetPlatform.android),
        isFalse,
      );
    });
  });
}
