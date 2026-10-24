import '../../core/network/auth_failure.dart';

/// Turns the pieces of a Supabase Auth error into a user-facing [AuthFailure].
///
/// Takes plain values (not the SDK exception) so it is trivial to test and does
/// not depend on SDK versions. Matches on the stable error `code` first and on
/// the message text as a fallback for older servers.
AuthFailure mapAuthError({
  required String message,
  String? statusCode,
  String? code,
  bool isNetworkError = false,
}) {
  if (isNetworkError) {
    return AuthFailure.network;
  }
  final text = message.toLowerCase();
  final errorCode = (code ?? '').toLowerCase();

  if (errorCode == 'invalid_credentials' ||
      text.contains('invalid login credentials')) {
    return AuthFailure.invalidCredentials;
  }
  if (errorCode == 'email_not_confirmed' || text.contains('email not confirmed')) {
    return AuthFailure.emailNotConfirmed;
  }
  if (errorCode == 'user_already_exists' ||
      errorCode == 'email_exists' ||
      text.contains('already registered') ||
      text.contains('already been registered')) {
    return AuthFailure.emailAlreadyRegistered;
  }
  if (errorCode == 'weak_password' ||
      text.contains('password should be') ||
      text.contains('weak password')) {
    return AuthFailure.weakPassword;
  }
  if (errorCode == 'over_request_rate_limit' ||
      errorCode == 'over_email_send_rate_limit' ||
      statusCode == '429' ||
      text.contains('rate limit')) {
    return AuthFailure.rateLimited;
  }
  if (errorCode == 'email_address_invalid' ||
      errorCode == 'validation_failed' ||
      text.contains('invalid format') ||
      (text.contains('email address') && text.contains('invalid'))) {
    return AuthFailure.invalidEmail;
  }
  if (errorCode == 'signup_disabled' || text.contains('signups not allowed')) {
    return AuthFailure.signupDisabled;
  }
  if (errorCode == 'user_banned' || text.contains('banned')) {
    return AuthFailure.accountDisabled;
  }
  return AuthFailure.unknown;
}
