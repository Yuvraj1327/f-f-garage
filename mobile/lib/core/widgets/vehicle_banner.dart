import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import 'brand_logo.dart';

/// The picture for a vehicle type: the blue-white scooter or the blue-orange
/// sports bike. Both are 16:9 and shown whole at that ratio (never stretched).
class VehicleBanner extends StatelessWidget {
  const VehicleBanner({super.key, required this.type});

  final VehicleType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBike = type == VehicleType.bike;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1672 / 941,
        child: Image.asset(
          isBike ? BrandAssets.bike : BrandAssets.scooter,
          key: ValueKey('vehicle-${type.name}'),
          fit: BoxFit.cover,
          semanticLabel: isBike ? 'Sports bike' : 'Scooter',
          errorBuilder: (context, error, stack) => ColoredBox(
            color: scheme.primaryContainer,
            child: Icon(Icons.two_wheeler, size: 56, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}
