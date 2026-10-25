import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Where the brand images live (registered in pubspec.yaml).
abstract final class BrandAssets {
  static const String logo = 'assets/images/logo.jpg';
  static const String onboardingHero = 'assets/images/onboarding_hero.jpg';
}

/// The F&F Two Wheeler Garage logo, shown whole (never stretched or cropped) in
/// a [size] x [size] box. The picture has a white background, so put it on a
/// white surface. If the image cannot be loaded a simple blue badge is drawn
/// instead, so a missing asset never breaks a screen.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      BrandAssets.logo,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'F&F Two Wheeler Garage',
      errorBuilder: (context, error, stack) => _Fallback(size: size),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary,
      ),
      child: Icon(Icons.two_wheeler, size: size * 0.52, color: Colors.white),
    );
  }
}
