import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/brand_logo.dart';
import '../../support/providers/support_providers.dart';

/// The app version shown on the About screen. Keep in step with `pubspec.yaml`.
const String appVersion = '0.1.0';

/// About the app and the garage. The garage's contact details are the ones the
/// administrator saved (same source as Help & support).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final contact = ref.watch(supportContactProvider).valueOrNull;
    final garageName = (contact != null && contact.name.isNotEmpty)
        ? contact.name
        : 'F&F Two Wheeler Garage';
    return Scaffold(
      appBar: AppBar(title: const Text('About App')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Center(child: BrandLogo(size: 120)),
            const SizedBox(height: 16),
            Text(garageName,
                style: textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text('Version $appVersion',
                style: textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Text(
              'Book bike and scooter servicing at your doorstep, follow the '
              'booking, and pay online or on completion. Drivers see their '
              'assigned jobs and the garage manages everything from the admin '
              'dashboard.',
              style: textTheme.bodyLarge,
            ),
            if (contact != null && contact.hasAnyContact) ...[
              const SizedBox(height: 24),
              Text('Contact', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              if (contact.hasPhone) Text('Phone: ${contact.phone}'),
              if (contact.hasEmail) Text('Email: ${contact.email}'),
              if (contact.hasAddress) Text(contact.address),
              if (contact.hasHours) Text('Hours: ${contact.hours}'),
            ],
          ],
        ),
      ),
    );
  }
}
