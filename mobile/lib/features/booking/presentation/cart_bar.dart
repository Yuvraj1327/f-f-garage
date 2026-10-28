import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../providers/booking_providers.dart';

/// The sticky bar at the bottom of the service screens once a service has been
/// added: what is in the cart, its price, and the way to checkout. A booking
/// holds one service, so adding another replaces it.
class CartBar extends ConsumerWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(bookingFlowProvider);
    final service = flow.service;
    final package = flow.package;
    if (service == null || package == null) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Material(
        key: const ValueKey('cart-bar'),
        color: scheme.primary,
        elevation: 8,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1 service added - ${formatMoney(package.price)}',
                      style: textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                    Text(
                      service.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('cart-remove'),
                tooltip: 'Remove from cart',
                color: scheme.onPrimary,
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(bookingFlowProvider.notifier).reset(),
              ),
              FilledButton(
                key: const ValueKey('cart-checkout'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark
                      ? scheme.secondary
                      : Colors.white,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark
                      ? scheme.onSecondary
                      : scheme.primary,
                ),
                onPressed: () => context.push(AppRoutes.checkout),
                child: const Text('Checkout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
