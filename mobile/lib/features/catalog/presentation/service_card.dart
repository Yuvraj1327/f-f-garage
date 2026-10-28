import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/brand_logo.dart' show BrandAssets;
import '../../../core/widgets/service_icon.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../booking/providers/booking_providers.dart';

/// The packages a customer can buy now.
List<ServicePackage> activePackages(GarageService service) =>
    service.packages.where((p) => p.isActive).toList();

/// Adds [service] to the cart. With one package it goes straight in; with
/// several the customer picks one on the detail screen first.
void addServiceToCart(BuildContext context, WidgetRef ref, GarageService service) {
  final packages = activePackages(service);
  if (packages.isEmpty) {
    showSnack(context, 'This service cannot be booked right now.');
    return;
  }
  if (packages.length > 1) {
    context.push(AppRoutes.serviceDetail(service.id));
    return;
  }
  final flow = ref.read(bookingFlowProvider);
  final replacing = flow.service != null && flow.service!.id != service.id;
  ref.read(bookingFlowProvider.notifier).start(service, packages.first);
  showSnack(
    context,
    replacing
        ? 'Cart updated: a booking holds one service.'
        : '${service.name} added.',
  );
}

/// A service in the catalogue: picture, name, short description, price,
/// duration and warranty, with Add and View details.
class ServiceCard extends ConsumerWidget {
  const ServiceCard({super.key, required this.service});

  final GarageService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final packages = activePackages(service);
    final cheapest = packages.isEmpty
        ? null
        : packages.reduce((a, b) => a.price <= b.price ? a : b);
    final inCart = ref.watch(bookingFlowProvider).service?.id == service.id;
    final duration = cheapest?.estimatedDurationMinutes;
    final warranty = cheapest?.warrantyLabel;
    return Card(
      key: ValueKey('service-${service.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.serviceDetail(service.id)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ServiceImage(service: service, size: 84),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (service.badge != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _Badge(text: service.badge!),
                          ),
                        Text(service.name, style: textTheme.titleMedium),
                        if (service.description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              service.description!,
                              style: textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (duration != null)
                    _Meta(icon: Icons.schedule, text: formatDuration(duration)),
                  if (warranty != null)
                    _Meta(icon: Icons.verified_outlined, text: '$warranty warranty'),
                  if (packages.length > 1)
                    _Meta(
                      icon: Icons.layers_outlined,
                      text: '${packages.length} options',
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (cheapest != null)
                    Expanded(child: _Price(package: cheapest, from: packages.length > 1))
                  else
                    const Expanded(child: Text('Not available right now')),
                  TextButton(
                    key: ValueKey('details-${service.id}'),
                    onPressed: () =>
                        context.push(AppRoutes.serviceDetail(service.id)),
                    child: const Text('View details'),
                  ),
                  const SizedBox(width: 4),
                  if (inCart)
                    OutlinedButton.icon(
                      key: ValueKey('added-${service.id}'),
                      onPressed: null,
                      icon: Icon(Icons.check, color: scheme.primary),
                      label: const Text('Added'),
                    )
                  else
                    FilledButton(
                      key: ValueKey('add-${service.id}'),
                      onPressed: cheapest == null
                          ? null
                          : () => addServiceToCart(context, ref, service),
                      child: const Text('Add'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 1:1 thumbnail of a service: the admin's picture, else the bundled one
/// for the three headline services, else the category icon in a light-blue
/// circle. Pictures are cropped to fill the square, never stretched.
class ServiceImage extends StatelessWidget {
  const ServiceImage({super.key, required this.service, this.size = 72});

  final GarageService service;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = ServiceThumb(category: service.category, size: size);
    final url = service.imageUrl;
    final asset = serviceAssetFor(service.name);
    final Widget? picture;
    if (url != null) {
      picture = Image.network(
        url,
        key: ValueKey('image-${service.id}'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: service.name,
        errorBuilder: (context, error, stack) => asset == null
            ? fallback
            : _assetSquare(asset),
      );
    } else if (asset != null) {
      picture = _assetSquare(asset);
    } else {
      picture = null;
    }
    if (picture == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: size, height: size, child: picture),
    );
  }

  Widget _assetSquare(ServiceAsset asset) => Image.asset(
        asset.square,
        key: ValueKey('asset-image-${service.id}'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: service.name,
        errorBuilder: (context, error, stack) =>
            ServiceThumb(category: service.category, size: size),
      );
}

/// The large 16:9 picture at the top of the service screen, edge to edge.
/// Same order as [ServiceImage]; with none it falls back to the vehicle banner.
class ServiceBanner extends StatelessWidget {
  const ServiceBanner({super.key, required this.service});

  final GarageService service;

  @override
  Widget build(BuildContext context) {
    final asset = serviceAssetFor(service.name);
    final url = service.imageUrl;
    Widget fallback() => asset != null
        ? _assetBanner(asset)
        : _frame(ServiceBannerFallback(service: service));
    return KeyedSubtree(
      key: const ValueKey('service-banner'),
      child: url != null
          ? _frame(
              Image.network(
                url,
                fit: BoxFit.cover,
                semanticLabel: service.name,
                errorBuilder: (context, error, stack) => fallback(),
              ),
            )
          : fallback(),
    );
  }

  Widget _assetBanner(ServiceAsset asset) => _frame(
        Image.asset(
          asset.banner,
          fit: BoxFit.cover,
          semanticLabel: service.name,
        ),
      );

  Widget _frame(Widget child) => AspectRatio(aspectRatio: 16 / 9, child: child);
}

/// No picture at all: the vehicle picture (scooter or bike), full width.
class ServiceBannerFallback extends StatelessWidget {
  const ServiceBannerFallback({super.key, required this.service});

  final GarageService service;

  @override
  Widget build(BuildContext context) {
    final bike = service.vehicleType == VehicleType.bike;
    return Image.asset(
      bike ? BrandAssets.bike : BrandAssets.scooter,
      fit: BoxFit.cover,
      semanticLabel: service.name,
      errorBuilder: (context, error, stack) => ColoredBox(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Center(
          child: ServiceThumb(category: service.category, size: 96),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// "₹499", with the crossed-out original price when there is a discount.
class _Price extends StatelessWidget {
  const _Price({required this.package, required this.from});

  final ServicePackage package;
  final bool from;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        if (from) Text('from', style: textTheme.bodySmall),
        Text(
          formatMoney(package.price),
          style: textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (package.hasDiscount)
          Text(
            formatMoney(package.originalPrice!),
            style: textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}
