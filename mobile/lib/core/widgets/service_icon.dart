import 'package:flutter/material.dart';

/// The icon for a service category ("General Service", "Brakes"...). Unknown
/// categories get a spanner.
IconData serviceIconFor(String category) {
  final name = category.toLowerCase();
  if (name.contains('engine')) return Icons.settings_outlined;
  if (name.contains('brake')) return Icons.stop_circle_outlined;
  if (name.contains('tyre') || name.contains('tire')) {
    return Icons.tire_repair;
  }
  if (name.contains('battery')) return Icons.battery_charging_full;
  if (name.contains('electric')) return Icons.electrical_services;
  if (name.contains('ac') && name.length <= 4) return Icons.ac_unit;
  if (name.contains('wash') || name.contains('clean')) {
    return Icons.local_car_wash_outlined;
  }
  return Icons.build_outlined;
}

/// A rounded square with the category icon, as in the service lists.
class ServiceThumb extends StatelessWidget {
  const ServiceThumb({super.key, required this.category, this.size = 56});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          serviceIconFor(category),
          size: size * 0.5,
          color: scheme.primary,
        ),
      ),
    );
  }
}
