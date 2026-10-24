/// Form validators. Each returns an error message, or null when the value is
/// acceptable (the contract of `TextFormField.validator`).
///
/// The rules mirror the backend (`app/schemas/*.py`) and the database
/// constraints, so a value that passes here is accepted there.
abstract final class Validators {
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 72;

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _driverId = RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$');
  static final RegExp _indianMobile = RegExp(r'^[6-9][0-9]{9}$');
  static final RegExp _phoneSeparators = RegExp(r'[\s\-().]');
  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _amount = RegExp(r'^\d{1,7}(\.\d{1,2})?$');
  static final RegExp _pincode = RegExp(r'^[1-9][0-9]{5}$');

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return 'Enter your email address';
    }
    if (!_email.hasMatch(text)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// For sign-in: only checks that something was typed. Password strength
  /// rules are applied when a password is created, never when it is used.
  static String? requiredPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Enter your password';
    }
    return null;
  }

  static String? newPassword(String? value) {
    final text = value ?? '';
    if (text.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    if (text.length > maxPasswordLength) {
      return 'Use at most $maxPasswordLength characters';
    }
    if (text.trim().isEmpty) {
      return 'Password cannot be blank';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) {
      return 'Re-enter your password';
    }
    if (value != original) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? fullName(String? value) {
    final text = normalizeName(value ?? '');
    if (text.isEmpty) {
      return 'Enter your full name';
    }
    if (text.length < 2 || text.length > 120) {
      return 'Name must be 2 to 120 characters';
    }
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter your mobile number';
    }
    if (normalizedMobile(value) == null) {
      return 'Enter a valid 10-digit mobile number';
    }
    return null;
  }

  static String? driverId(String? value) {
    final text = normalizeDriverId(value ?? '');
    if (text.isEmpty) {
      return 'Enter your driver ID';
    }
    if (!_driverId.hasMatch(text)) {
      return 'Driver ID uses letters, digits, ".", "_" or "-" (3 to 32 characters)';
    }
    return null;
  }

  // ---- Catalogue and availability (mirror the backend's limits) -------------

  /// A required single-line text of [min]..[max] characters after trimming.
  static String? requiredText(
    String? value, {
    required String label,
    int min = 2,
    required int max,
  }) {
    final text = normalizeName(value ?? '');
    if (text.isEmpty) {
      return 'Enter the $label';
    }
    if (text.length < min || text.length > max) {
      return 'The $label must be $min to $max characters';
    }
    return null;
  }

  /// Optional free text, at most [max] characters.
  static String? optionalText(String? value, {required String label, required int max}) {
    if ((value ?? '').trim().length > max) {
      return 'The $label must be at most $max characters';
    }
    return null;
  }

  static const double maxMoney = 1000000;

  /// A rupee amount: 0 to 10,00,000 with at most two decimals.
  static String? price(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Enter the price';
    }
    return _amountError(text);
  }

  /// Optional amount; empty means "charged at actuals".
  static String? optionalAmount(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : _amountError(text);
  }

  static String? _amountError(String text) {
    if (!_amount.hasMatch(text)) {
      return 'Enter a valid amount (at most 2 decimal places)';
    }
    if (double.parse(text) > maxMoney) {
      return 'The amount must be at most ${maxMoney.toStringAsFixed(0)}';
    }
    return null;
  }

  /// Parses what [price] / [optionalAmount] accepted; null for empty input.
  static double? parseAmount(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : double.tryParse(text);
  }

  /// Optional whole minutes, 5 to 1440.
  static String? optionalDuration(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null;
    }
    final minutes = int.tryParse(text);
    if (minutes == null || minutes < 5 || minutes > 1440) {
      return 'Enter whole minutes between 5 and 1440';
    }
    return null;
  }

  static String? displayOrder(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return null; // defaults to 0
    }
    final n = int.tryParse(text);
    if (n == null || n < 0 || n > 10000) {
      return 'Enter a whole number from 0 to 10000';
    }
    return null;
  }

  static String? capacity(String? value) {
    final n = int.tryParse((value ?? '').trim());
    if (n == null || n < 1 || n > 50) {
      return 'Enter a whole number from 1 to 50';
    }
    return null;
  }

  /// Six digits, not starting with 0 (spaces are ignored).
  static String? pincode(String? value) {
    final text = (value ?? '').replaceAll(' ', '');
    if (text.isEmpty) {
      return 'Enter the PIN code';
    }
    if (!_pincode.hasMatch(text)) {
      return 'Enter a valid 6-digit PIN code';
    }
    return null;
  }

  static String normalizePincode(String value) => value.replaceAll(' ', '');

  /// Whole minutes since midnight must run forward.
  static String? slotOrder(int startMinutes, int endMinutes) =>
      endMinutes > startMinutes ? null : 'The slot must end after it starts';

  static String normalizeName(String value) =>
      value.trim().replaceAll(_whitespace, ' ');

  static String normalizeDriverId(String value) => value.trim().toLowerCase();

  /// Returns an Indian mobile number as `+91XXXXXXXXXX`, or null if [raw] is
  /// not one. Accepts spaces/dashes and a leading 0, 91 or +91.
  static String? normalizedMobile(String? raw) {
    if (raw == null) {
      return null;
    }
    var digits = raw.replaceAll(_phoneSeparators, '');
    if (digits.startsWith('+91')) {
      digits = digits.substring(3);
    } else if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return _indianMobile.hasMatch(digits) ? '+91$digits' : null;
  }
}
