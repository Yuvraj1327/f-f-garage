/// Small helpers for reading API JSON. Every method throws [FormatException]
/// with the field name when the value is missing or has the wrong type;
/// repositories turn that into `ApiException.invalidResponse()`.
abstract final class JsonReader {
  static String string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw FormatException('Expected "$key" to be a non-empty string, got $value');
  }

  static String? optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('Expected "$key" to be a string or null, got $value');
  }

  static int integer(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    throw FormatException('Expected "$key" to be an int, got $value');
  }

  static int? optionalInteger(Map<String, dynamic> json, String key) {
    return json[key] == null ? null : integer(json, key);
  }

  /// A plain JSON number (coordinates), or null when absent / null.
  static double? optionalDouble(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    throw FormatException('Expected "$key" to be a number or null, got $value');
  }

  static bool boolean(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('Expected "$key" to be a bool, got $value');
  }

  /// Money arrives as a decimal string ("499.00") or a number.
  static double money(Map<String, dynamic> json, String key) {
    final parsed = optionalMoney(json, key);
    if (parsed == null) {
      throw FormatException('Expected "$key" to be an amount');
    }
    return parsed;
  }

  static double? optionalMoney(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
    throw FormatException('Expected "$key" to be an amount, got $value');
  }

  /// A "YYYY-MM-DD" date as a calendar date (no time zone shifts).
  static DateTime date(Map<String, dynamic> json, String key) {
    final text = string(json, key);
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (match == null) {
      throw FormatException('Expected "$key" to be a date, got $text');
    }
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static List<String> stringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is List && value.every((item) => item is String)) {
      return List<String>.unmodifiable(value.cast<String>());
    }
    throw FormatException('Expected "$key" to be a list of strings, got $value');
  }

  static List<int> intList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is List && value.every((item) => item is int)) {
      return List<int>.unmodifiable(value.cast<int>());
    }
    throw FormatException('Expected "$key" to be a list of ints, got $value');
  }

  static List<T> objectList<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final value = json[key];
    if (value is List && value.every((item) => item is Map<String, dynamic>)) {
      return List<T>.unmodifiable(
        value.cast<Map<String, dynamic>>().map(parse),
      );
    }
    throw FormatException('Expected "$key" to be a list of objects, got $value');
  }
}

/// "2026-10-20" for a calendar date.
String formatApiDate(DateTime date) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-${two(date.day)}';
}
