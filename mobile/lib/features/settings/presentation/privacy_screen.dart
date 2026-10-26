import 'package:flutter/material.dart';

/// A plain-language summary of what the app does with personal data. The garage
/// should replace it with its own legal policy before launch.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = <(String, String)>[
    (
      'What we collect',
      'Your name, mobile number and email address; the address and map '
          'location you enter for a booking; your vehicle details; and your '
          'booking and payment history. If you sign in with Google we receive '
          'your name and email from Google.'
    ),
    (
      'Why we collect it',
      'Only to book and carry out your service, to let the driver find you, '
          'to take payment, and to contact you about your booking.'
    ),
    (
      'Who can see it',
      'Your bookings are visible to you, to the garage administrators, and '
          'to the driver assigned to that booking. Card details are handled by '
          'the payment provider and never reach this app or our servers.'
    ),
    (
      'Your choices',
      'You can update your name and mobile number and change your password in '
          'Settings. To delete your account or data, contact the garage from '
          'Help & Support.'
    ),
    (
      'On your phone',
      'The app stores your theme and notification choices on the device. '
          'Signing out ends your session.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            for (final (title, body) in _sections) ...[
              Text(title, style: textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(body, style: textTheme.bodyLarge),
              const SizedBox(height: 20),
            ],
            Text(
              'This is a summary, not a legal document.',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
