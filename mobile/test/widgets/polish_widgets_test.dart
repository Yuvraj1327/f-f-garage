import 'package:ff_garage/app/responsive_shell.dart';
import 'package:ff_garage/app/theme/app_theme.dart';
import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/core/widgets/async_view.dart';
import 'package:ff_garage/core/widgets/dialogs.dart';
import 'package:ff_garage/core/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {ThemeData? theme}) =>
    MaterialApp(theme: theme ?? AppTheme.light(), home: Scaffold(body: child));

void main() {
  group('AsyncView', () {
    testWidgets('shows a spinner by default while loading', (tester) async {
      await tester.pumpWidget(_host(
        AsyncView<int>(
          value: const AsyncLoading(),
          onRetry: () {},
          builder: (_) => const Text('data'),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the given skeleton instead of the spinner',
        (tester) async {
      await tester.pumpWidget(_host(
        AsyncView<int>(
          value: const AsyncLoading(),
          loading: const ListSkeleton(count: 2),
          onRetry: () {},
          builder: (_) => const Text('data'),
        ),
      ));
      expect(find.byType(SkeletonCard), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error: friendly message and a Retry that works',
        (tester) async {
      var retries = 0;
      await tester.pumpWidget(_host(
        AsyncView<int>(
          value: AsyncError(
            const ApiException(
              type: ApiErrorType.network,
              message: 'No connection.',
            ),
            StackTrace.empty,
          ),
          onRetry: () => retries++,
          builder: (_) => const Text('data'),
        ),
      ));
      expect(find.text('No connection.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('an unknown error never leaks technical text',
        (tester) async {
      await tester.pumpWidget(_host(
        AsyncView<int>(
          value: AsyncError(StateError('boom: secret'), StackTrace.empty),
          onRetry: () {},
          builder: (_) => const Text('data'),
        ),
      ));
      expect(find.textContaining('secret'), findsNothing);
      expect(find.text('Something went wrong. Please try again.'),
          findsOneWidget);
    });

    testWidgets('EmptyView shows its message, icon and action',
        (tester) async {
      await tester.pumpWidget(_host(
        EmptyView(
          message: 'Nothing here.',
          icon: Icons.build_outlined,
          action: FilledButton(onPressed: () {}, child: const Text('Go')),
        ),
      ));
      expect(find.text('Nothing here.'), findsOneWidget);
      expect(find.byIcon(Icons.build_outlined), findsOneWidget);
      expect(find.text('Go'), findsOneWidget);
    });
  });

  group('theme', () {
    test('buttons and icon buttons have at least a 48dp touch target', () {
      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        expect(
          theme.filledButtonTheme.style!.minimumSize!.resolve({})!.height,
          greaterThanOrEqualTo(48),
        );
        expect(
          theme.outlinedButtonTheme.style!.minimumSize!.resolve({})!.height,
          greaterThanOrEqualTo(48),
        );
        expect(
          theme.textButtonTheme.style!.minimumSize!.resolve({})!.height,
          greaterThanOrEqualTo(48),
        );
        expect(
          theme.iconButtonTheme.style!.minimumSize!.resolve({})!.shortestSide,
          greaterThanOrEqualTo(48),
        );
      }
    });

    test('light and dark themes use Material 3', () {
      expect(AppTheme.light().useMaterial3, isTrue);
      expect(AppTheme.dark().brightness, Brightness.dark);
    });
  });

  group('ResponsiveShell', () {
    testWidgets('keeps content from stretching on a wide screen',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: ResponsiveShell(child: SizedBox.expand(key: Key('content'))),
      ));

      expect(
        tester.getSize(find.byKey(const Key('content'))).width,
        ResponsiveShell.maxContentWidth,
      );
    });

    testWidgets('uses the whole width on a phone', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        home: ResponsiveShell(child: SizedBox.expand(key: Key('content'))),
      ));

      expect(tester.getSize(find.byKey(const Key('content'))).width, 360);
    });

    testWidgets('clamps a huge system font but honours a moderate one',
        (tester) async {
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      double? seen;
      Widget probe() => MaterialApp(
            home: ResponsiveShell(
              child: Builder(builder: (context) {
                seen = MediaQuery.of(context).textScaler.scale(10);
                return const SizedBox();
              }),
            ),
          );

      tester.platformDispatcher.textScaleFactorTestValue = 3;
      await tester.pumpWidget(probe());
      expect(seen, closeTo(10 * ResponsiveShell.maxTextScale, 0.001));

      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      await tester.pumpWidget(probe());
      await tester.pump();
      expect(seen, closeTo(13, 0.001));
    });

    testWidgets('tapping outside a text field closes the keyboard focus',
        (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(MaterialApp(
        home: ResponsiveShell(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: node),
                const Expanded(child: SizedBox.expand(key: Key('blank'))),
              ],
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(node.hasFocus, isTrue);

      await tester.tap(find.byKey(const Key('blank')));
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });
  });

  group('success snack', () {
    testWidgets('shows the message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSuccessSnack(context, 'Saved'),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('Saved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });
}
