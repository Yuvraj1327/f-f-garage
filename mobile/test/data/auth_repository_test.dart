import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/network/auth_failure.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/repositories/auth_repository.dart';
import 'package:ff_garage/data/services/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeAuthGateway gateway;
  late FakeProfileRepository profiles;
  late AuthRepository repo;

  AuthRepository build(UserRole role, {bool isActive = true}) {
    gateway = FakeAuthGateway();
    profiles = FakeProfileRepository(profileFor(role, isActive: isActive));
    return AuthRepository(
      gateway: gateway,
      profiles: profiles,
      config: const AppConfig(
        apiBaseUrl: 'http://x',
        supabaseUrl: 'http://x',
        supabaseAnonKey: 'anon',
      ),
    );
  }

  Matcher failure(AuthFailureType type) =>
      isA<AuthFailure>().having((f) => f.type, 'type', type);

  group('customer sign-in', () {
    test('succeeds for a customer and lower-cases the email', () async {
      repo = build(UserRole.customer);
      final profile = await repo.signInCustomer(
        email: ' User@Example.com ',
        password: 'pw',
      );
      expect(profile.role, UserRole.customer);
      expect(gateway.lastEmail, 'user@example.com');
      expect(gateway.signOutCalls, 0);
    });

    test('a driver account is rejected and signed straight back out', () async {
      repo = build(UserRole.driver);
      await expectLater(
        repo.signInCustomer(email: 'a@b.co', password: 'pw'),
        throwsA(failure(AuthFailureType.wrongAccountType)),
      );
      expect(gateway.signOutCalls, 1);
      expect(gateway.hasSession, isFalse);
    });

    test('an admin account is rejected', () async {
      repo = build(UserRole.admin);
      await expectLater(
        repo.signInCustomer(email: 'a@b.co', password: 'pw'),
        throwsA(failure(AuthFailureType.wrongAccountType)),
      );
      expect(gateway.hasSession, isFalse);
    });

    test('a disabled account is rejected', () async {
      repo = build(UserRole.customer, isActive: false);
      await expectLater(
        repo.signInCustomer(email: 'a@b.co', password: 'pw'),
        throwsA(failure(AuthFailureType.accountDisabled)),
      );
      expect(gateway.hasSession, isFalse);
    });

    test('invalid credentials pass through and no profile is fetched', () async {
      repo = build(UserRole.customer);
      gateway.signInError = AuthFailure.invalidCredentials;
      await expectLater(
        repo.signInCustomer(email: 'a@b.co', password: 'bad'),
        throwsA(failure(AuthFailureType.invalidCredentials)),
      );
    });

    test('an unreachable backend signs out and reports a network problem',
        () async {
      repo = build(UserRole.customer);
      profiles.error = networkError;
      await expectLater(
        repo.signInCustomer(email: 'a@b.co', password: 'pw'),
        throwsA(failure(AuthFailureType.network)),
      );
      expect(gateway.hasSession, isFalse);
    });

    test('a 403 (no profile / disabled) is reported as a disabled account',
        () async {
      repo = build(UserRole.customer);
      profiles.error = forbiddenError;
      await expectLater(
        repo.signInCustomer(email: 'a@b.co', password: 'pw'),
        throwsA(failure(AuthFailureType.accountDisabled)),
      );
    });
  });

  group('admin sign-in', () {
    test('succeeds for an admin account', () async {
      repo = build(UserRole.admin);
      final profile = await repo.signInAdmin(email: ' Boss@Example.com ', password: 'pw');
      expect(profile.role, UserRole.admin);
      expect(gateway.lastEmail, 'boss@example.com');
    });

    test('customer and driver accounts are rejected on the admin screen', () async {
      for (final role in [UserRole.customer, UserRole.driver]) {
        repo = build(role);
        await expectLater(
          repo.signInAdmin(email: 'a@b.co', password: 'pw'),
          throwsA(failure(AuthFailureType.wrongAccountType)),
        );
        expect(gateway.hasSession, isFalse);
      }
    });

    test('a disabled admin is rejected', () async {
      repo = build(UserRole.admin, isActive: false);
      await expectLater(
        repo.signInAdmin(email: 'a@b.co', password: 'pw'),
        throwsA(failure(AuthFailureType.accountDisabled)),
      );
    });

    test('an admin cannot use the customer or driver sign-in', () async {
      repo = build(UserRole.admin);
      await expectLater(
        repo.signInCustomer(email: 'a@b.co', password: 'pw'),
        throwsA(failure(AuthFailureType.wrongAccountType)),
      );
      await expectLater(
        repo.signInDriver(driverId: 'ravi01', password: 'pw'),
        throwsA(failure(AuthFailureType.wrongAccountType)),
      );
    });
  });

  group('driver sign-in', () {
    test('builds the synthetic email from the ID, case-insensitively',
        () async {
      repo = build(UserRole.driver);
      await repo.signInDriver(driverId: ' Ravi01 ', password: 'pw');
      expect(gateway.lastEmail, 'ravi01@drivers.ffgarage.invalid');
    });

    test('a customer account is rejected on the driver screen', () async {
      repo = build(UserRole.customer);
      await expectLater(
        repo.signInDriver(driverId: 'ravi01', password: 'pw'),
        throwsA(failure(AuthFailureType.wrongAccountType)),
      );
      expect(gateway.hasSession, isFalse);
    });

    test('wrong password talks about the driver ID, not an email', () async {
      repo = build(UserRole.driver);
      gateway.signInError = AuthFailure.invalidCredentials;
      await expectLater(
        repo.signInDriver(driverId: 'ravi01', password: 'bad'),
        throwsA(
          isA<AuthFailure>().having(
            (f) => f.message,
            'message',
            contains('driver ID'),
          ),
        ),
      );
    });
  });

  group('registration', () {
    test('sends name and normalised phone as metadata, never a role', () async {
      repo = build(UserRole.customer);
      final profile = await repo.registerCustomer(
        fullName: '  Asha   Rao ',
        email: 'Asha@Example.com',
        phone: '98765 43210',
        password: 'password1',
      );
      expect(profile, isNotNull);
      expect(gateway.lastEmail, 'asha@example.com');
      expect(gateway.lastMetadata, {
        'full_name': 'Asha Rao',
        'phone': '+919876543210',
      });
      expect(gateway.lastMetadata!.containsKey('role'), isFalse);
    });

    test('returns null when email confirmation is required', () async {
      repo = build(UserRole.customer);
      gateway.signUpResult = SignUpResult.emailConfirmationRequired;
      final profile = await repo.registerCustomer(
        fullName: 'Asha Rao',
        email: 'a@b.co',
        phone: '9876543210',
        password: 'password1',
      );
      expect(profile, isNull);
      expect(gateway.hasSession, isFalse);
    });

    test('a duplicate email surfaces as a failure', () async {
      repo = build(UserRole.customer);
      gateway.signUpError = AuthFailure.emailAlreadyRegistered;
      await expectLater(
        repo.registerCustomer(
          fullName: 'Asha Rao',
          email: 'a@b.co',
          phone: '9876543210',
          password: 'password1',
        ),
        throwsA(failure(AuthFailureType.emailAlreadyRegistered)),
      );
    });
  });

  group('session restore', () {
    test('no stored session -> null without calling the backend', () async {
      repo = build(UserRole.customer);
      expect(await repo.restoreSession(), isNull);
    });

    test('valid session returns the profile', () async {
      repo = build(UserRole.driver);
      gateway.hasStoredSession = true;
      final profile = await repo.restoreSession();
      expect(profile!.role, UserRole.driver);
    });

    test('rejected token or revoked access signs out', () async {
      repo = build(UserRole.customer);
      gateway.hasStoredSession = true;
      profiles.error = unauthorizedError;
      expect(await repo.restoreSession(), isNull);
      expect(gateway.hasSession, isFalse);

      gateway.hasStoredSession = true;
      profiles.error = forbiddenError;
      expect(await repo.restoreSession(), isNull);
    });

    test('a disabled profile signs out', () async {
      repo = build(UserRole.customer, isActive: false);
      gateway.hasStoredSession = true;
      expect(await repo.restoreSession(), isNull);
      expect(gateway.hasSession, isFalse);
    });

    test('an unreachable backend keeps the session and throws', () async {
      repo = build(UserRole.customer);
      gateway.hasStoredSession = true;
      profiles.error = networkError;
      await expectLater(repo.restoreSession(), throwsA(anything));
      expect(gateway.hasSession, isTrue);
    });
  });
}
