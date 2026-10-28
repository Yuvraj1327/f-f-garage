import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/brand_logo.dart';

/// "Why Choose F&F Garage?": the motorcycle-mechanic picture, a short pitch and
/// the four benefits. The picture keeps its own 16:9 shape (nothing is
/// cropped) and the card grows with its text, so it never overflows.
class WhyChooseSection extends StatelessWidget {
  const WhyChooseSection({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('promo-why-choose'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PromoImage(
            asset: BrandAssets.promoBike,
            imageKey: ValueKey('promo-bike-image'),
            label: 'A mechanic servicing a motorcycle in a bright garage',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Why Choose F&F Garage?',
                      style: textTheme.titleLarge),
                ),
                const SizedBox(height: 6),
                Text(
                  'Expert bike servicing at your doorstep. Our trained '
                  'mechanics come to you, so you never have to queue at a '
                  'workshop.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                const _BenefitGrid(
                  benefits: [
                    _Benefit(Icons.home_repair_service_outlined,
                        'Convenient doorstep service'),
                    _Benefit(Icons.engineering_outlined, 'Skilled mechanics'),
                    _Benefit(Icons.receipt_long_outlined,
                        'Transparent pricing'),
                    _Benefit(Icons.touch_app_outlined, 'Easy booking'),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('promo-why-choose-cta'),
                  onPressed: () => context.push(AppRoutes.browseServices),
                  child: const Text('Book a service'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Reliable scooter servicing": the scooter-repair picture with a short pitch
/// and a shortcut to the service list.
class ScooterServiceSection extends StatelessWidget {
  const ScooterServiceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('promo-scooter'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              const _PromoImage(
                asset: BrandAssets.promoScooter,
                imageKey: ValueKey('promo-scooter-image'),
                label: 'A mechanic servicing a scooter in a bright garage',
              ),
              Positioned(
                left: 12,
                top: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    child: Text(
                      'SCOOTER CARE',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Reliable scooter servicing',
                      style: textTheme.titleLarge),
                ),
                const SizedBox(height: 6),
                Text(
                  'From oil changes to brake checks, we keep your scooter '
                  'running smoothly, right outside your home.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                const _CheckLine('Genuine parts and clear service packages'),
                const _CheckLine('Live tracking from booking to completion'),
                const _CheckLine('Pay securely once the work is done'),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  key: const ValueKey('promo-scooter-cta'),
                  onPressed: () => context.push(AppRoutes.browseServices),
                  icon: const Icon(Icons.two_wheeler),
                  label: const Text('View services'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A 16:9 picture shown whole (the files are 16:9, so nothing is cropped).
class _PromoImage extends StatelessWidget {
  const _PromoImage({
    required this.asset,
    required this.imageKey,
    required this.label,
  });

  final String asset;
  final Key imageKey;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Image.asset(
        asset,
        key: imageKey,
        fit: BoxFit.cover,
        semanticLabel: label,
        errorBuilder: (context, error, stack) => const ColoredBox(
          color: AppColors.primarySoft,
          child: Center(
            child: Icon(Icons.two_wheeler, size: 56, color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

class _Benefit {
  const _Benefit(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Benefits in two columns on a phone, four in a row when there is room.
class _BenefitGrid extends StatelessWidget {
  const _BenefitGrid({required this.benefits});

  final List<_Benefit> benefits;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final benefit in benefits)
              SizedBox(width: width, child: _BenefitTile(benefit: benefit)),
          ],
        );
      },
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.benefit});

  final _Benefit benefit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.primary,
          child: Icon(benefit.icon, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            benefit.label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.check_circle, size: 18, color: AppColors.success),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
