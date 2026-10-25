enum AuthFailureType {
  invalidCredentials,
  emailNotConfirmed,
  emailAlreadyRegistered,
  weakPassword,
  rateLimited,
  network,
  wrongAccountType,
  accountDisabled,
  sessionExpired,
  notConfigured,
  googleNotConfigured,
  googleFailed,
  unknown,
}

/// A sign-in / sign-up problem, with a message that is safe to show the user.
class AuthFailure implements Exception {
  const AuthFailure(this.type, this.message);

  final AuthFailureType type;
  final String message;

  static const AuthFailure invalidCredentials = AuthFailure(
    AuthFailureType.invalidCredentials,
    'Incorrect email or password.',
  );
  static const AuthFailure invalidDriverCredentials = AuthFailure(
    AuthFailureType.invalidCredentials,
    'Incorrect driver ID or password.',
  );
  static const AuthFailure emailNotConfirmed = AuthFailure(
    AuthFailureType.emailNotConfirmed,
    'Please confirm your email address first. Check your inbox for the link.',
  );
  static const AuthFailure emailAlreadyRegistered = AuthFailure(
    AuthFailureType.emailAlreadyRegistered,
    'An account with this email already exists. Try signing in instead.',
  );
  static const AuthFailure weakPassword = AuthFailure(
    AuthFailureType.weakPassword,
    'That password is too weak. Use a longer, less common password.',
  );
  static const AuthFailure rateLimited = AuthFailure(
    AuthFailureType.rateLimited,
    'Too many attempts. Please wait a few minutes and try again.',
  );
  static const AuthFailure network = AuthFailure(
    AuthFailureType.network,
    'Unable to reach the server. Check your internet connection and try again.',
  );
  static const AuthFailure notCustomerAccount = AuthFailure(
    AuthFailureType.wrongAccountType,
    'This is not a customer account. Drivers and staff should use their own '
    'sign-in.',
  );
  static const AuthFailure notDriverAccount = AuthFailure(
    AuthFailureType.wrongAccountType,
    'This is not a driver account. Customers should use the customer login.',
  );
  static const AuthFailure notAdminAccount = AuthFailure(
    AuthFailureType.wrongAccountType,
    'This is not an administrator account.',
  );
  static const AuthFailure accountDisabled = AuthFailure(
    AuthFailureType.accountDisabled,
    'This account cannot be used right now. Please contact the garage.',
  );
  static const AuthFailure sessionExpired = AuthFailure(
    AuthFailureType.sessionExpired,
    'Your session has expired. Please sign in again.',
  );
  static const AuthFailure notConfigured = AuthFailure(
    AuthFailureType.notConfigured,
    'This build of the app is not configured for sign-in.',
  );
  static const AuthFailure googleNotConfigured = AuthFailure(
    AuthFailureType.googleNotConfigured,
    'Google sign-in is not set up in this version of the app yet. Please sign '
    'in with your email and password.',
  );
  static const AuthFailure googleFailed = AuthFailure(
    AuthFailureType.googleFailed,
    'Google sign-in did not work. Please try again, or use your email and '
    'password.',
  );
  static const AuthFailure unknown = AuthFailure(
    AuthFailureType.unknown,
    'Something went wrong. Please try again.',
  );

  @override
  String toString() => 'AuthFailure($type): $message';
}
