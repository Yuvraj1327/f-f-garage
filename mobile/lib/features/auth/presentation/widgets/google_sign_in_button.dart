import 'package:flutter/material.dart';

/// "or" divider followed by the "Continue with Google" button, shared by the
/// customer sign-in and sign-up screens.
///
/// Uses the Material "G" glyph. Swap in Google's official logo asset if you
/// need to follow Google's branding guidelines to the letter.
class GoogleSignInSection extends StatelessWidget {
  const GoogleSignInSection({
    super.key,
    required this.busy,
    required this.onPressed,
  });

  /// True while any sign-in on the screen is in progress (disables the button).
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: textTheme.bodySmall?.copyWith(color: muted)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('google-sign-in'),
          onPressed: busy ? null : onPressed,
          icon: const Icon(Icons.g_mobiledata, size: 28),
          label: const Text('Continue with Google'),
        ),
      ],
    );
  }
}
