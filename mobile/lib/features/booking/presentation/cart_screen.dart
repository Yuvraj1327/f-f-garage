import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../catalog/presentation/service_card.dart' show ServiceImage;
import '../../vehicles/presentation/vehicle_switcher.dart';
import '../providers/booking_providers.dart';
import 'booking_widgets.dart';

/// The cart: the service the customer added, the vehicle it is for, a way to
/// change or remove it, the subtotal and the way on to checkout. A booking
/// holds one service, so the cart does too.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(bookingFlowProvider);
    final service = flow.service;
    final package = flow.package;
    if (service == null || package == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your cart')),
        body: EmptyView(
          icon: Icons.shopping_cart_outlined,
          message: 'Your cart is empty. Add a service to get started.',
          action: FilledButton(
            key: const ValueKey('cart-browse'),
            onPressed: () => context.go(AppRoutes.browseServices),
            child: const Text('Browse services'),
          ),
        ),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    final duration = package.estimatedDurationMinutes;
    return Scaffold(
      appBar: AppBar(title: const Text('Your cart')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SectionCard(
                    title: 'Your vehicle',
                    children: const [VehicleSwitcher(showTypeToggle: false)],
                  ),
                  SectionCard(
                    title: '1 service',
                    children: [
                      Row(
                        key: const ValueKey('cart-item'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ServiceImage(service: service, size: 72),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(service.name, style: textTheme.titleMedium),
                                Text(
                                  '${package.name}'
                                  '${duration == null ? '' : ' - about ${formatDuration(duration)}'}',
                                  style: textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(package.price),
                                style: textTheme.titleMedium,
                              ),
                              if (package.hasDiscount)
                                Text(
                                  formatMoney(package.originalPrice!),
                                  style: textTheme.bodySmall?.copyWith(
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            key: const ValueKey('cart-edit'),
                            onPressed: () => context
                                .push(AppRoutes.serviceDetail(service.id)),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit'),
                          ),
                          TextButton.icon(
                            key: const ValueKey('cart-item-remove'),
                            onPressed: () {
                              ref.read(bookingFlowProvider.notifier).reset();
                              showSnack(context, '${service.name} removed.');
                            },
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SectionCard(
                    title: 'Subtotal',
                    children: [
                      SummaryRow(
                        key: const ValueKey('cart-subtotal'),
                        label: 'Subtotal',
                        value: formatMoney(package.price),
                        bold: true,
                      ),
                      Text(
                        'Add-ons, coupon and the 20% advance are shown at '
                        'checkout.',
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('cart-continue'),
                  onPressed: () => context.push(AppRoutes.checkout),
                  child: const Text('Continue to Checkout'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
