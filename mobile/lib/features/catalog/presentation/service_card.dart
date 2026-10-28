import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/brand_logo.dart' show BrandAssets;
import '../../../core/widgets/service_icon.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../booking/providers/booking_providers.dart';
import '../../vehicles/providers/vehicle_providers.dart';

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

/// A service in the catalogue: square picture, name, short text, price with
/// any discount, and a coloured footer with "View details" and Add.
///
/// The admin screens reuse this card: they pass [adminControls] (shown under the
/// card in place of Add) so the admin sees what customers see.
class ServiceCard extends ConsumerWidget {
  const ServiceCard({
    super.key,
    required this.service,
    this.footerColor,
    this.adminControls,
    this.onOpen,
  });

  final GarageService service;

  /// The footer colour; null picks one from the service's position.
  final Color? footerColor;

  /// Management controls (admin). Null for customers.
  final Widget? adminControls;

  /// Where a tap goes; defaults to the customer detail screen.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final packages = activePackages(service);
    final cheapest = packages.isEmpty
        ? null
        : packages.reduce((a, b) => a.price <= b.price ? a : b);
    final inCart = ref.watch(bookingFlowProvider).service?.id == service.id;
    final vehicle =
        adminControls == null ? ref.watch(selectedVehicleProvider) : null;
    final fits = vehicle == null || service.supports(vehicle.make, vehicle.model);
    final color = footerColor ?? _footerColors[_colorIndex(service.id)];
    final open = onOpen ?? () => context.push(AppRoutes.serviceDetail(service.id));
    final discount = cheapest?.discountLabel;
    final offer = service.badge;
    return Card(
      key: ValueKey('service-${service.id}'),
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ServiceImage(service: service, size: 96),
                      if (offer != null)
                        Positioned(left: 0, top: 0, child: _Badge(text: offer)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(service.name, style: textTheme.titleMedium),
                        if (service.cardText != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              service.cardText!,
                              style: textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 6),
                        if (cheapest != null)
                          _Price(package: cheapest, from: packages.length > 1)
                        else
                          const Text('Not available right now'),
                        if (!fits)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Not available for your '
                              '${vehicle!.make} ${vehicle.model}',
                              key: ValueKey('unsupported-${service.id}'),
                              style: textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (discount != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                        discount,
                        key: ValueKey('discount-${service.id}'),
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.secondaryOnSoft,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (adminControls != null)
            adminControls!
          else
            Container(
              color: color,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: ValueKey('details-${service.id}'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        alignment: Alignment.centerLeft,
                      ),
                      onPressed: open,
                      child: const Text('View details  >'),
                    ),
                  ),
                  if (inCart)
                    FilledButton.icon(
                      key: ValueKey('added-${service.id}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: color,
                        disabledBackgroundColor: Colors.white,
                        disabledForegroundColor: color,
                      ),
                      onPressed: null,
                      icon: const Icon(Icons.check),
                      label: const Text('Added'),
                    )
                  else
                    FilledButton(
                      key: ValueKey('add-${service.id}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: color,
                      ),
                      onPressed: cheapest == null || !fits
                          ? null
                          : () => addServiceToCart(context, ref, service),
                      child: const Text('ADD'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

const List<Color> _footerColors = [
  Color(0xFF2563EB),
  Color(0xFF1E3A5F),
  Color(0xFFEA580C),
];

int _colorIndex(String id) =>
    id.codeUnits.fold<int>(0, (a, b) => a + b) % _footerColors.length;

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
    final url = service.thumbnail;
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
    final url = service.banner;
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
      key: const ValueKey('offer-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          bottomRight: Radius.circular(10),
        ),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
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
