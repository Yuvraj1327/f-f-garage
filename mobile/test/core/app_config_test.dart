import 'dart:convert';

import 'package:ff_garage/core/config/app_config.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

String _encodeSegment(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

String _jwt(Map<String, Object?> claims) =>
    '${_encodeSegment({'alg': 'HS256', 'typ': 'JWT'})}.'
    '${_encodeSegment(claims)}.signature';

AppConfig _config({String url = '', String key = ''}) => AppConfig(
      apiBaseUrl: 'http://api.test/api/v1',
      supabaseUrl: url,
      supabaseAnonKey: key,
    );

void main() {
  group('isPrivilegedSupabaseKey', () {
    test('flags a legacy service_role JWT', () {
      expect(
        AppConfig.isPrivilegedSupabaseKey(_jwt({'role': 'service_role'})),
        isTrue,
      );
    });

    test('accepts a legacy anon JWT', () {
      expect(
        AppConfig.isPrivilegedSupabaseKey(_jwt({'role': 'anon'})),
        isFalse,
      );
    });

    test('flags the new secret key format only', () {
      expect(AppConfig.isPrivilegedSupabaseKey('sb_secret_abc123'), isTrue);
      expect(AppConfig.isPrivilegedSupabaseKey('sb_publishable_abc123'), isFalse);
    });

    test('does not crash on malformed values', () {
      expect(AppConfig.isPrivilegedSupabaseKey(''), isFalse);
      expect(AppConfig.isPrivilegedSupabaseKey('not-a-jwt'), isFalse);
      expect(AppConfig.isPrivilegedSupabaseKey('a.b.c'), isFalse);
      expect(AppConfig.isPrivilegedSupabaseKey('a.%%%.c'), isFalse);
    });
  });

  group('AppConfig', () {
    test('ensureNoPrivilegedKeys throws for a service-role key', () {
      final config = _config(
        url: 'https://x.supabase.co',
        key: _jwt({'role': 'service_role'}),
      );
      expect(config.ensureNoPrivilegedKeys, throwsStateError);
    });

    test('ensureNoPrivilegedKeys allows the anon key and an empty config', () {
      expect(
        _config(url: 'https://x.supabase.co', key: _jwt({'role': 'anon'}))
            .ensureNoPrivilegedKeys,
        returnsNormally,
      );
      expect(_config().ensureNoPrivilegedKeys, returnsNormally);
    });

    test('isSupabaseConfigured needs both URL and key', () {
      expect(_config().isSupabaseConfigured, isFalse);
      expect(_config(url: 'https://x.supabase.co').isSupabaseConfigured, isFalse);
      expect(_config(key: 'k').isSupabaseConfigured, isFalse);
      expect(
        _config(url: 'https://x.supabase.co', key: 'k').isSupabaseConfigured,
        isTrue,
      );
    });

  });

  group('AppConfig.fromMap (.env values)', () {
    const good = {
      'API_BASE_URL': 'https://api.example.com/api/v1',
      'SUPABASE_URL': 'https://abc.supabase.co',
      'SUPABASE_ANON_KEY': 'public-anon-key',
      'DRIVER_EMAIL_DOMAIN': 'drivers.example.invalid',
    };

    test('reads every value and trims whitespace', () {
      final config = AppConfig.fromMap({
        ...good,
        'SUPABASE_URL': '  https://abc.supabase.co  ',
      });
      expect(config.apiBaseUrl, 'https://api.example.com/api/v1');
      expect(config.supabaseUrl, 'https://abc.supabase.co');
      expect(config.supabaseAnonKey, 'public-anon-key');
      expect(config.driverEmailDomain, 'drivers.example.invalid');
      expect(config.problems, isEmpty);
      expect(config.isValid, isTrue);
    });

    test('an empty .env falls back to defaults and reports what is missing', () {
      final config = AppConfig.fromMap(const {});
      expect(config.apiBaseUrl, AppConfig.defaultApiBaseUrl);
      expect(config.driverEmailDomain, AppConfig.defaultDriverEmailDomain);
      expect(config.isValid, isFalse);
      expect(config.problems.join('\n'), contains('SUPABASE_URL'));
      expect(config.problems.join('\n'), contains('SUPABASE_ANON_KEY'));
      expect(config.problems.join('\n'), isNot(contains('API_BASE_URL')));
    });

    test('blank values count as missing', () {
      final config = AppConfig.fromMap({
        ...good,
        'SUPABASE_ANON_KEY': '   ',
        'API_BASE_URL': '',
        'DRIVER_EMAIL_DOMAIN': '',
      });
      expect(config.apiBaseUrl, AppConfig.defaultApiBaseUrl);
      expect(config.driverEmailDomain, AppConfig.defaultDriverEmailDomain);
      expect(config.problems.single, contains('SUPABASE_ANON_KEY'));
    });

    test('example placeholders are reported, not used', () {
      final config = AppConfig.fromMap({
        ...good,
        'SUPABASE_URL': 'https://YOUR-PROJECT-REF.supabase.co',
        'SUPABASE_ANON_KEY': 'YOUR-PUBLIC-ANON-KEY',
      });
      expect(config.problems, hasLength(2));
    });

    test('a malformed URL is reported', () {
      expect(
        AppConfig.fromMap({...good, 'API_BASE_URL': 'not a url'}).problems.single,
        contains('API_BASE_URL'),
      );
      expect(
        AppConfig.fromMap({...good, 'SUPABASE_URL': 'ftp://x.example'})
            .problems
            .single,
        contains('SUPABASE_URL'),
      );
    });

    test('a service-role key in SUPABASE_ANON_KEY is reported, never echoed', () {
      final key = _jwt({'role': 'service_role'});
      final problems =
          AppConfig.fromMap({...good, 'SUPABASE_ANON_KEY': key}).problems;
      expect(problems.single, contains('service-role'));
      expect(problems.join(), isNot(contains(key)));
    });

    test('server-secret variable names in .env are reported by name only', () {
      final config = AppConfig.fromMap({
        ...good,
        'SUPABASE_SERVICE_ROLE_KEY': 'super-secret-value',
        'PAYMENT_GATEWAY_KEY_SECRET': 'another-secret-value',
        'DATABASE_URL': 'postgres://u:p@h/db',
      });
      expect(config.forbiddenKeys, [
        'DATABASE_URL',
        'PAYMENT_GATEWAY_KEY_SECRET',
        'SUPABASE_SERVICE_ROLE_KEY',
      ]);
      final text = config.problems.join('\n');
      expect(config.problems, hasLength(3));
      expect(text, contains('SUPABASE_SERVICE_ROLE_KEY'));
      expect(text, isNot(contains('super-secret-value')));
      expect(text, isNot(contains('postgres://')));
    });

    test('the public variable names are not mistaken for secrets', () {
      expect(AppConfig.forbiddenKeyNames(good.keys), isEmpty);
    });
  });

  group('AppConfig.fromDotenv', () {
    test('does not throw when .env was never loaded, and reports it', () {
      final config = AppConfig.fromDotenv();
      expect(config.isValid, isFalse);
      expect(config.apiBaseUrl, AppConfig.defaultApiBaseUrl);
    });

    test('reads what flutter_dotenv loaded', () {
      addTearDown(dotenv.clean);
      dotenv.testLoad(
        fileInput: 'API_BASE_URL=https://api.example.com/api/v1\n'
            'SUPABASE_URL=https://abc.supabase.co\n'
            'SUPABASE_ANON_KEY=public-anon-key\n',
      );
      final config = AppConfig.fromDotenv();
      expect(config.supabaseUrl, 'https://abc.supabase.co');
      expect(config.isValid, isTrue);
    });
  });
}
