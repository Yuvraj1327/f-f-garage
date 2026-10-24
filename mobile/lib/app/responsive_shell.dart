import 'package:flutter/material.dart';

/// Wraps every screen with three app-wide behaviours:
///  * content never stretches wider than [maxContentWidth] (tablets, web),
///  * text scaling is clamped so very large system fonts stay usable
///    (still honouring the user's setting up to [maxTextScale]),
///  * tapping outside a text field closes the keyboard.
class ResponsiveShell extends StatelessWidget {
  const ResponsiveShell({super.key, required this.child});

  final Widget child;

  static const double maxContentWidth = 720;
  static const double maxTextScale = 1.6;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scaler = media.textScaler.clamp(
      minScaleFactor: 0.85,
      maxScaleFactor: maxTextScale,
    );
    return MediaQuery(
      data: media.copyWith(textScaler: scaler),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        ),
      ),
    );
  }
}
