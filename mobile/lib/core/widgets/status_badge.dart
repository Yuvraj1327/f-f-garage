import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The colour family of a [StatusBadge] (from the design system).
enum BadgeTone { info, success, warning, danger, neutral }

/// A small rounded pill: "Ongoing" (blue), "Completed" (green), "Pending"
/// (orange), "Cancelled" (red). An optional icon means the state is never
/// conveyed by colour alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = BadgeTone.neutral,
    this.icon,
  });

  final String label;
  final BadgeTone tone;
  final IconData? icon;

  (Color, Color) _colors(ColorScheme scheme) {
    switch (tone) {
      case BadgeTone.info:
        return (AppColors.primarySoft, AppColors.primaryOnSoft);
      case BadgeTone.success:
        return (AppColors.secondarySoft, AppColors.secondaryOnSoft);
      case BadgeTone.warning:
        return (AppColors.accentSoft, AppColors.accentOnSoft);
      case BadgeTone.danger:
        return (AppColors.errorSoft, AppColors.errorOnSoft);
      case BadgeTone.neutral:
        return (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
