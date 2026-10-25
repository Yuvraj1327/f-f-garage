import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/brand_logo.dart';
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

/// The first-run welcome: logo, three short messages (swipe), the hero picture
/// and the way into sign-up or sign-in. Shown once per install; "Skip" and the
/// buttons all remember that it was seen.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Everything except the hero takes a fixed height; the hero gets
            // the rest (never less than 220) and the page scrolls on very
            // short screens instead of overflowing.
            const fixed = 48 + 112 + 176 + 24 + 56 + 56 + 32;
            final heroHeight =
                (constraints.maxHeight - fixed).clamp(220.0, 520.0);
            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 48,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              key: const ValueKey('onboarding-skip'),
                              onPressed: () => _leave(AppRoutes.login),
                              child: Text(
                                'Skip',
                                style: TextStyle(color: muted),
                              ),
                            ),
                          ),
                        ),
                        const Center(child: BrandLogo(size: 112)),
                        SizedBox(
                          height: 176,
                          child: PageView.builder(
                            key: const ValueKey('onboarding-pages'),
                            controller: _controller,
                            itemCount: _pages.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (context, i) => Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _pages[i].title,
                                  style: textTheme.headlineMedium,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _pages[i].subtitle,
                                  style: textTheme.bodyLarge
                                      ?.copyWith(color: muted),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          height: heroHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x1A0F172A),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: ColoredBox(
                                color: AppColors.primarySoft,
                                child: Image.asset(
                                  BrandAssets.onboardingHero,
                                  key: const ValueKey('onboarding-hero'),
                                  fit: BoxFit.contain,
                                  semanticLabel:
                                      'A customer booking a service on their '
                                      'phone while a mechanic works on a bike',
                                  errorBuilder: (context, error, stack) =>
                                      const Center(
                                    child: Icon(
                                      Icons.two_wheeler,
                                      size: 72,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < _pages.length; i++)
                                AnimatedContainer(
                                  key: ValueKey('dot-$i'),
                                  duration: const Duration(milliseconds: 200),
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  width: i == _page ? 20 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: i == _page
                                        ? AppColors.primary
                                        : const Color(0xFFCBD5E1),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          key: const ValueKey('onboarding-get-started'),
                          onPressed: () => _leave(AppRoutes.register),
                          icon: const Icon(Icons.arrow_forward),
                          iconAlignment: IconAlignment.end,
                          label: const Text('Get Started'),
                        ),
                        SizedBox(
                          height: 56,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account?',
                                style: textTheme.bodyMedium
                                    ?.copyWith(color: muted),
                              ),
                              TextButton(
                                key: const ValueKey('onboarding-login'),
                                onPressed: () => _leave(AppRoutes.login),
                                child: const Text('Login'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
