import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/data/services/auth_error_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

AuthFailureType _type({
  String message = '',
  String? code,
  String? status,
  bool network = false,
}) =>
    mapAuthError(
      message: message,
      code: code,
      statusCode: status,
      isNetworkError: network,
    ).type;

void main() {
  test('maps by error code', () {
    expect(_type(code: 'invalid_credentials'), AuthFailureType.invalidCredentials);
    expect(_type(code: 'email_not_confirmed'), AuthFailureType.emailNotConfirmed);
    expect(_type(code: 'user_already_exists'), AuthFailureType.emailAlreadyRegistered);
    expect(_type(code: 'email_exists'), AuthFailureType.emailAlreadyRegistered);
    expect(_type(code: 'weak_password'), AuthFailureType.weakPassword);
    expect(_type(code: 'over_request_rate_limit'), AuthFailureType.rateLimited);
    expect(_type(code: 'user_banned'), AuthFailureType.accountDisabled);
    expect(_type(code: 'email_address_invalid'), AuthFailureType.invalidEmail);
    expect(_type(code: 'signup_disabled'), AuthFailureType.signupDisabled);
    expect(_type(code: 'over_email_send_rate_limit'), AuthFailureType.rateLimited);
  });

  test('falls back to message text and status for older servers', () {
    expect(
      _type(message: 'Invalid login credentials'),
      AuthFailureType.invalidCredentials,
    );
    expect(_type(message: 'Email not confirmed'), AuthFailureType.emailNotConfirmed);
    expect(
      _type(message: 'User already registered'),
      AuthFailureType.emailAlreadyRegistered,
    );
    expect(_type(message: 'x', status: '429'), AuthFailureType.rateLimited);
    expect(_type(message: 'User is banned'), AuthFailureType.accountDisabled);
  });

  test('network errors win and unknown errors never leak server text', () {
    expect(_type(message: 'whatever', network: true), AuthFailureType.network);
    final failure = mapAuthError(message: 'db password is hunter2');
    expect(failure.type, AuthFailureType.unknown);
    expect(failure.message, isNot(contains('hunter2')));
  });
}
