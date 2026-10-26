import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_nav.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/service_icon.dart';
import '../../../data/models/catalog.dart';
import '../../auth/providers/auth_controller.dart';
import '../../catalog/presentation/pincode_check_card.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../../notifications/presentation/notification_bell.dart';

/// Customer landing screen: greeting, a "book a service" banner, service
/// categories and popular services from the catalogue API, shortcuts and the
/// service-area check.
class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    final textTheme = Theme.of(context).textTheme;
    // Catalogue sections are a bonus on this screen: while loading, or if the
    // call fails, they are simply left out (the Browse button still works).
    final services =
        ref.watch(browseServicesProvider(null)).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            BrandLogo(size: 32),
            SizedBox(width: 10),
            Text('F&F Garage'),
          ],
        ),
        actions: [
          const NotificationBell(),
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      bottomNavigationBar: navFor(ref, NavTab.home),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(browseServicesProvider(null).future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Hello, ${profile?.displayName ?? 'there'}',
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Doorstep bike and scooter servicing.',
                style: textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              const _HeroBanner(),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.build_outlined,
                      title: 'Browse services',
                      route: AppRoutes.browseServices,
                    ),
                  ),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.receipt_long_outlined,
                      title: 'My bookings',
                      route: AppRoutes.bookings,
                    ),
                  ),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.support_agent,
                      title: 'Help & support',
                      route: AppRoutes.support,
                    ),
                  ),
                ],
              ),
              const PincodeCheckCard(),
              if (services.isNotEmpty) ...[
                const SizedBox(height: 8),
                SectionHeader(
                  title: 'Services',
                  actionLabel: 'See All',
                  onAction: () => context.push(AppRoutes.browseServices),
                ),
                _CategoryGrid(services: services),
                const SizedBox(height: 8),
                SectionHeader(
                  title: 'Popular Services',
                  actionLabel: 'See All',
                  onAction: () => context.push(AppRoutes.browseServices),
                ),
                for (final service in services.take(3))
                  _PopularTile(service: service),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The mechanic banner with the "Book a service" button. The picture's left
/// half is a pale-blue fade, so the (always navy) text sits on it in both themes.
class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 1672 / 940,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              BrandAssets.homeBanner,
              key: const ValueKey('home-banner'),
              fit: BoxFit.cover,
              alignment: Alignment.centerRight,
              semanticLabel: 'A mechanic servicing a scooter and a bike at a '
                  'customer\'s doorstep',
              errorBuilder: (context, error, stack) =>
                  const ColoredBox(color: Color(0xFFDBEAFE)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.58,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reliable Two Wheeler Service At Your Doorstep',
                        style: textTheme.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Book service, track in real time, ride worry free.',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: () =>
                            context.push(AppRoutes.browseServices),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(130, 44),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Book a service'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Up to eight distinct categories, four to a row.
class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.services});

  final List<GarageService> services;

  @override
  Widget build(BuildContext context) {
    final categories = <String>[];
    for (final service in services) {
      if (!categories.contains(service.category)) {
        categories.add(service.category);
      }
    }
    final shown = categories.take(8).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final width = (constraints.maxWidth - gap * 3) / 4;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (final category in shown)
              SizedBox(
                width: width,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(AppRoutes.browseServices),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        ServiceThumb(category: category, size: 52),
                        const SizedBox(height: 6),
                        Text(
                          category,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PopularTile extends StatelessWidget {
  const _PopularTile({required this.service});

  final GarageService service;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final from = service.startingPrice;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.serviceDetail(service.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ServiceThumb(category: service.category, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  service.name,
                  style: textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (from != null)
                Text(
                  formatMoney(from),
                  style: textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// A square-ish shortcut: icon above a short label.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String route;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.primary,
                child: Icon(icon),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
