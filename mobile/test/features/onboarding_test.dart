import 'package:ff_garage/app/app.dart';
import 'package:ff_garage/core/config/app_config.dart';
import 'package:ff_garage/core/providers/core_providers.dart';
import 'package:ff_garage/core/widgets/brand_logo.dart';
import 'package:ff_garage/data/models/enums.dart';
import 'package:ff_garage/data/providers/data_providers.dart';
import 'package:ff_garage/features/onboarding/providers/onboarding_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _MemoryStore implements OnboardingStore {
  int saved = 0;

  @override
  Future<void> markSeen() async => saved += 1;
}

Widget _app({
  required bool seen,
  OnboardingStore? store,
  FakeAuthGateway? gateway,
}) =>
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'http://x',
            supabaseUrl: 'http://x',
            supabaseAnonKey: 'anon',
          ),
        ),
        authGatewayProvider.overrideWithValue(gateway ?? FakeAuthGateway()),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(profileFor(UserRole.customer)),
        ),
        initialOnboardingSeenProvider.overrideWithValue(seen),
        onboardingStoreProvider.overrideWithValue(store),
      ],
      child: const FfGarageApp(),
    );

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets('a first launch opens the welcome screens', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(seen: false));
    await tester.pumpAndSettle();

    expect(find.text('Your Bike Care\nAt Your Doorstep'), findsOneWidget);
    expect(find.text('Book trusted two-wheeler service quickly and easily.'),
        findsOneWidget);
    expect(_key('onboarding-get-started'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('the picture fills the screen and the logo is shown whole',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(seen: false));
    await tester.pumpAndSettle();

    final hero = tester.widget<Image>(_key('onboarding-hero'));
    expect(hero.fit, BoxFit.cover);
    expect((hero.image as AssetImage).assetName, BrandAssets.onboardingHero);
    expect(tester.getSize(_key('onboarding-hero')), const Size(800, 1600));
    final logo = tester.widget<Image>(
      find.descendant(of: find.byType(BrandLogo), matching: find.byType(Image)),
    );
    expect(logo.fit, BoxFit.contain);
  });

  testWidgets('Continue with Google signs in and is remembered',
      (tester) async {
    _tall(tester);
    final store = _MemoryStore();
    final gateway = FakeAuthGateway();
    await tester.pumpWidget(_app(seen: false, store: store, gateway: gateway));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(_key('onboarding-google'));
    await tester.pumpAndSettle();

    expect(gateway.googleCalls, 1);
    expect(store.saved, 1);
  });

  testWidgets('swiping shows the other messages and moves the indicator',
      (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(seen: false));
    await tester.pumpAndSettle();

    await tester.drag(_key('onboarding-pages'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Earn with Your Skills'), findsOneWidget);
    expect(tester.getSize(_key('dot-1')).width, 20);
    expect(tester.getSize(_key('dot-0')).width, 8);

    await tester.drag(_key('onboarding-pages'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Manage Everything\nin One Place'), findsOneWidget);
  });

  testWidgets('Skip goes to sign-in and is remembered', (tester) async {
    _tall(tester);
    final store = _MemoryStore();
    await tester.pumpWidget(_app(seen: false, store: store));
    await tester.pumpAndSettle();

    await tester.tap(_key('onboarding-skip'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(store.saved, 1);
  });

  testWidgets('Get Started opens sign-up', (tester) async {
    _tall(tester);
    final store = _MemoryStore();
    await tester.pumpWidget(_app(seen: false, store: store));
    await tester.pumpAndSettle();

    await tester.tap(_key('onboarding-get-started'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Create account'), findsOneWidget);
    expect(store.saved, 1);
  });

  testWidgets('Login opens sign-in', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(seen: false));
    await tester.pumpAndSettle();

    await tester.tap(_key('onboarding-login'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('once seen, the app opens straight on sign-in', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app(seen: true));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(_key('onboarding-get-started'), findsNothing);
  });

  testWidgets('fits a short phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(seen: false));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_key('onboarding-hero'), findsOneWidget);
  });

  testWidgets('the whole app is light, whatever the device setting',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(_app(seen: true));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Welcome back'));
    expect(Theme.of(context).brightness, Brightness.light);
  });
}
