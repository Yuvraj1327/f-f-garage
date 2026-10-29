import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/network/auth_failure.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../data/services/auth_gateway.dart' show GoogleSignInResult;
import '../../auth/providers/auth_controller.dart';
import '../providers/onboarding_providers.dart';

class _Page {
  const _Page(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

const List<_Page> _pages = [
  _Page(
    'Your Bike Care\nAt Your Doorstep',
    'Book trusted two-wheeler service quickly and easily.',
  ),
  _Page(
    'Earn with Your Skills',
    'Get service requests, manage your work and grow your earnings.',
  ),
  _Page(
    'Manage Everything\nin One Place',
    'Manage services, bookings, drivers and grow your business.',
  ),
];

/// Deep navy used for the gradient and the Google button text.
const Color _navy = Color(0xFF0B1B3F);

/// White at about 88%, for supporting text on the dark gradient.
const Color _softWhite = Color(0xE0FFFFFF);

/// The first-run welcome: a full-screen picture with a navy gradient, the logo,
/// three short messages (swipe) and the way into sign-up, sign-in or Google.
/// Shown once per install; "Skip" and every action remember that it was seen.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _leave(String route) async {
    await ref.read(onboardingSeenProvider.notifier).markSeen();
    if (mounted) {
      context.go(route);
    }
  }

  Future<void> _google() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(onboardingSeenProvider.notifier).markSeen();
      final result =
          await ref.read(authControllerProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      // signedIn: the router moves on. redirecting (Web): the browser is on its
      // way to Google. cancelled: back to normal.
      if (result == GoogleSignInResult.cancelled) {
        setState(() => _busy = false);
      }
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // The picture and gradient are dark at the bottom whatever the theme, so
    // the text on them is always white.
    return Scaffold(
      backgroundColor: _navy,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            BrandAssets.onboardingHero,
            key: const ValueKey('onboarding-hero'),
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            semanticLabel: 'A customer booking a service on their phone while '
                'a mechanic works on a bike',
            errorBuilder: (context, error, stack) => const ColoredBox(
              color: AppColors.primary,
              child: Center(
                child: Icon(Icons.two_wheeler, size: 96, color: Colors.white),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.3, 0.46, 0.7, 0.86, 1.0],
                colors: [
                  Color(0xB30B1B3F),
                  Color(0x660B1B3F),
                  Color(0x000B1B3F),
                  Color(0x000B1B3F),
                  Color(0xD90B1B3F),
                  Color(0xFA0B1B3F),
                ],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  height: 64,
                                  child: Row(
                                    children: [
                                      const BrandLogo(size: 48),
                                      const Spacer(),
                                      TextButton(
                                        key: const ValueKey('onboarding-skip'),
                                        onPressed: () =>
                                            _leave(AppRoutes.login),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Skip'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'TWO WHEELER SERVICE',
                                  style: textTheme.labelMedium?.copyWith(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 150,
                                  child: PageView.builder(
                                    key: const ValueKey('onboarding-pages'),
                                    controller: _controller,
                                    itemCount: _pages.length,
                                    onPageChanged: (i) =>
                                        setState(() => _page = i),
                                    itemBuilder: (context, i) => Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _pages[i].title,
                                          style: textTheme.headlineMedium
                                              ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            height: 1.15,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _pages[i].subtitle,
                                          style: textTheme.bodyLarge
                                              ?.copyWith(color: _softWhite),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  height: 24,
                                  child: Row(
                                    children: [
                                      for (var i = 0; i < _pages.length; i++)
                                        AnimatedContainer(
                                          key: ValueKey('dot-$i'),
                                          duration:
                                              const Duration(milliseconds: 200),
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          width: i == _page ? 20 : 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            color: i == _page
                                                ? AppColors.accent
                                                : Colors.white54,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                FilledButton.icon(
                                  key: const ValueKey('onboarding-get-started'),
                                  onPressed: () => _leave(AppRoutes.register),
                                  icon: const Icon(Icons.arrow_forward),
                                  iconAlignment: IconAlignment.end,
                                  label: const Text('Get Started'),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  key: const ValueKey('onboarding-google'),
                                  onPressed: _busy ? null : _google,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: _navy,
                                    disabledBackgroundColor: Colors.white70,
                                    disabledForegroundColor: Colors.black45,
                                  ),
                                  icon:
                                      const Icon(Icons.g_mobiledata, size: 28),
                                  label: const Text('Continue with Google'),
                                ),
                                SizedBox(
                                  height: 48,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Already have an account?',
                                        style: textTheme.bodyMedium
                                            ?.copyWith(color: _softWhite),
                                      ),
                                      TextButton(
                                        key: const ValueKey('onboarding-login'),
                                        onPressed: () =>
                                            _leave(AppRoutes.login),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          textStyle: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            decoration:
                                                TextDecoration.underline,
                                            decorationColor: Colors.white,
                                          ),
                                        ),
                                        child: const Text('Login'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
