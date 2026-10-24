import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// App configuration, read from the `.env` file (see `.env.example`) through
/// `flutter_dotenv` and handed to the app as an [AppConfig].
///
/// Only PUBLIC values belong in `.env`. Everything in it is bundled into the
/// app, and anyone can unpack an APK/IPA: never put a Supabase service-role key,
/// a database password or a payment-gateway secret there. Those live only in
/// the FastAPI backend. [problems] reports such a mistake, and the app refuses
/// to start instead of shipping the secret.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.driverEmailDomain = defaultDriverEmailDomain,
    this.forbiddenKeys = const [],
  });

  /// Builds the config from `.env` values (`dotenv.env`). Missing, blank or
  /// whitespace-only values fall back to the defaults; nothing here throws, so a
  /// broken `.env` is reported through [problems] instead of crashing.
  factory AppConfig.fromMap(Map<String, String> env) {
    String read(String key, [String fallback = '']) {
      final value = env[key]?.trim();
      return (value == null || value.isEmpty) ? fallback : value;
    }

    return AppConfig(
      apiBaseUrl: read('API_BASE_URL', defaultApiBaseUrl),
      supabaseUrl: read('SUPABASE_URL'),
      supabaseAnonKey: read('SUPABASE_ANON_KEY'),
      driverEmailDomain: read('DRIVER_EMAIL_DOMAIN', defaultDriverEmailDomain),
      forbiddenKeys: forbiddenKeyNames(env.keys),
    );
  }

  /// Reads the values `flutter_dotenv` loaded (an empty map when `.env` could
  /// not be loaded).
  factory AppConfig.fromDotenv() =>
      AppConfig.fromMap(dotenv.isInitialized ? dotenv.env : const {});

  /// Names that must never appear in a client-side `.env`: they hold server
  /// secrets. Matched case-insensitively against each variable name.
  static final RegExp _secretNamePattern = RegExp(
    r'SERVICE_ROLE|SECRET|PASSWORD|PASSWD|PRIVATE_KEY|DATABASE_URL|DB_URL|JWT',
    caseSensitive: false,
  );

  /// The variable names in [names] that look like server secrets.
  static List<String> forbiddenKeyNames(Iterable<String> names) =>
      [for (final name in names) if (_secretNamePattern.hasMatch(name)) name]
        ..sort();

  /// Drivers sign in with an ID and password. Supabase Auth needs an email, so
  /// the login is `<driver id>@<this domain>`. The ".invalid" TLD is reserved,
  /// so nothing can ever be delivered there. Must match the backend setting
  /// `DRIVER_EMAIL_DOMAIN` and the database function
  /// `public.driver_email_domain()`; a backend test enforces this.
  static const String defaultDriverEmailDomain = 'drivers.ffgarage.invalid';

  /// Host machine as seen from the Android emulator. For the iOS simulator use
  /// `http://localhost:8000/api/v1`; for a real device use your machine's LAN
  /// address or a deployed URL.
  static const String defaultApiBaseUrl = 'http://10.0.2.2:8000/api/v1';

  /// Base URL of the FastAPI backend, including the `/api/v1` prefix.
  final String apiBaseUrl;

  final String supabaseUrl;

  /// The PUBLIC anon key. It is safe to ship because Row Level Security limits
  /// what it can do.
  final String supabaseAnonKey;

  /// Email domain used for driver ID logins.
  final String driverEmailDomain;

  /// Variable names found in `.env` that look like server secrets.
  final List<String> forbiddenKeys;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// True while a value is still the example placeholder from `.env.example`.
  static bool _isPlaceholder(String value) =>
      value.toUpperCase().contains('YOUR-');

  /// Everything that stops the app from starting, in plain words (never the
  /// secret values themselves). Empty when the configuration is usable.
  List<String> get problems {
    final found = <String>[];
    if (supabaseUrl.isEmpty || _isPlaceholder(supabaseUrl)) {
      found.add('SUPABASE_URL is missing. Set it to your Supabase project URL.');
    } else if (!_isHttpUrl(supabaseUrl)) {
      found.add('SUPABASE_URL is not a valid http(s) URL.');
    }
    if (supabaseAnonKey.isEmpty || _isPlaceholder(supabaseAnonKey)) {
      found.add('SUPABASE_ANON_KEY is missing. Set it to the public anon key.');
    } else if (hasPrivilegedSupabaseKey) {
      found.add(
        'SUPABASE_ANON_KEY holds a service-role / secret key. Use the public '
        'anon key; keep the service-role key in the backend only.',
      );
    }
    if (!_isHttpUrl(apiBaseUrl) || _isPlaceholder(apiBaseUrl)) {
      found.add('API_BASE_URL must be an http(s) URL of the backend.');
    }
    for (final name in forbiddenKeys) {
      found.add(
        '$name must not be in the app\'s .env: it looks like a server secret '
        'and would be bundled into the app. Remove it.',
      );
    }
    return found;
  }

  bool get isValid => problems.isEmpty;

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// The Supabase Auth email that represents a driver ID.
  String driverEmailFor(String driverId) =>
      '${driverId.trim().toLowerCase()}@$driverEmailDomain';

  bool get hasPrivilegedSupabaseKey => isPrivilegedSupabaseKey(supabaseAnonKey);

  /// Throws if a privileged Supabase key was supplied by mistake, so the app
  /// refuses to start instead of shipping a secret.
  void ensureNoPrivilegedKeys() {
    if (hasPrivilegedSupabaseKey) {
      throw StateError(
        'SUPABASE_ANON_KEY holds a service-role / secret key. Use the public '
        'anon key in the app; keep the service-role key in the backend only.',
      );
    }
  }

  /// True for Supabase secret keys: the new `sb_secret_...` format, or a legacy
  /// JWT whose `role` claim is `service_role`.
  static bool isPrivilegedSupabaseKey(String key) {
    if (key.startsWith('sb_secret_')) {
      return true;
    }
    final parts = key.split('.');
    if (parts.length != 3) {
      return false;
    }
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final claims = jsonDecode(payload);
      return claims is Map<String, dynamic> && claims['role'] == 'service_role';
    } on FormatException {
      return false;
    }
  }
}
