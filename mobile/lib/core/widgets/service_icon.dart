import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Pictures for the three headline services. They are matched by name so an
/// admin who has not uploaded a picture still gets a good one.
class ServiceAsset {
  const ServiceAsset({required this.square, required this.banner});

  /// 1:1 crop for list thumbnails.
  final String square;

  /// 16:9 picture for the top of the service screen.
  final String banner;
}

const ServiceAsset _bookMechanic = ServiceAsset(
  square: 'assets/images/services/book_mechanic_square.jpg',
  banner: 'assets/images/services/book_mechanic_banner.jpg',
);
const ServiceAsset _checkVehicle = ServiceAsset(
  square: 'assets/images/services/check_vehicle_square.jpg',
  banner: 'assets/images/services/check_vehicle_banner.jpg',
);
const ServiceAsset _consultation = ServiceAsset(
  square: 'assets/images/services/mechanic_consultation_square.jpg',
  banner: 'assets/images/services/mechanic_consultation_banner.jpg',
);

/// The bundled picture for [name] ("Book a Mechanic", "Check My Vehicle",
/// "Mechanic Consultation"), or null when there is none.
ServiceAsset? serviceAssetFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('consult')) return _consultation;
  if (n.contains('check') && (n.contains('vehicle') || n.contains('bike'))) {
    return _checkVehicle;
  }
  if (n.contains('book') && n.contains('mechanic')) return _bookMechanic;
  return null;
}

/// The icon for a service category or part ("Engine", "Brakes"...). Unknown
/// ones get a spanner.
IconData serviceIconFor(String category) {
  final name = category.toLowerCase();
  if (name.contains('engine')) return Icons.settings_outlined;
  if (name.contains('brake')) return Icons.disc_full_outlined;
  if (name.contains('tyre') || name.contains('tire') || name.contains('wheel')) {
    return Icons.tire_repair;
  }
  if (name.contains('battery')) return Icons.battery_charging_full;
  if (name.contains('chain') || name.contains('sprocket')) return Icons.link;
  if (name.contains('cable') || name.contains('clutch')) return Icons.cable;
  if (name.contains('light') || name.contains('lamp')) {
    return Icons.lightbulb_outline;
  }
  if (name.contains('filter')) return Icons.filter_alt_outlined;
  if (name.contains('lubric') || name.contains('oil')) {
    return Icons.oil_barrel_outlined;
  }
  if (name.contains('electric') || name.contains('wiring')) {
    return Icons.electrical_services;
  }
  if (name.contains('wash') || name.contains('clean')) {
    return Icons.local_car_wash_outlined;
  }
  return Icons.build_outlined;
}

/// A circle with a light-blue background and the category icon in royal blue,
/// with a small orange dot as the accent.
class ServiceThumb extends StatelessWidget {
  const ServiceThumb({super.key, required this.category, this.size = 56});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dark ? scheme.primaryContainer : AppColors.primarySoft,
              ),
              child: Icon(
                serviceIconFor(category),
                size: size * 0.5,
                color: scheme.primary,
              ),
            ),
            Positioned(
              right: size * 0.08,
              top: size * 0.08,
              child: Container(
                width: size * 0.16,
                height: size * 0.16,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
