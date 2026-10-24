import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../data/models/support_contact.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/support_providers.dart';

/// Help & support: how to reach the garage (details configured by the operator
/// on the server) plus short answers to the common questions. Available to every
/// signed-in role. [bookingCode] is set when opened from a booking, so the
/// message to the garage can quote it.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key, this.bookingCode});

  final String? bookingCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contact = ref.watch(supportContactProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Help & support')),
      body: SafeArea(
        child: AsyncView<SupportContact>(
          value: contact,
          loading: const ListSkeleton(count: 2),
          onRetry: () => ref.invalidate(supportContactProvider),
          builder: (data) => RefreshIndicator(
            onRefresh: () => ref.refresh(supportContactProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (bookingCode != null && bookingCode!.isNotEmpty)
                  _BookingNote(code: bookingCode!),
                _ContactCard(contact: data, bookingCode: bookingCode),
                const SizedBox(height: 16),
                const _HelpTopics(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookingNote extends StatelessWidget {
  const _BookingNote({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.receipt_long_outlined,
                color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Asking about booking $code? Mention this code when you contact us.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends ConsumerWidget {
  const _ContactCard({required this.contact, this.bookingCode});

  final SupportContact contact;
  final String? bookingCode;

  String get _intro => bookingCode == null || bookingCode!.isEmpty
      ? 'Hi, I need help with my service.'
      : 'Hi, I need help with booking $bookingCode.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launcher = ref.watch(contactLauncherProvider);
    final textTheme = Theme.of(context).textTheme;

    Future<void> open(Future<bool> Function() action, String fallback) async {
      final opened = await action();
      if (!opened && context.mounted) {
        showSnack(context, "Couldn't open that on this device. $fallback");
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                contact.name.isEmpty ? 'Contact us' : contact.name,
                style: textTheme.titleLarge,
              ),
            ),
            if (!contact.hasAnyContact)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'The garage has not published contact details yet. '
                  'Please check back soon.',
                ),
              ),
            if (contact.hasPhone)
              _ContactTile(
                icon: Icons.call_outlined,
                title: 'Call us',
                value: contact.phone,
                onTap: () => open(
                  () => launcher.call(contact.phone),
                  'Our number is ${contact.phone}.',
                ),
              ),
            if (contact.hasWhatsapp)
              _ContactTile(
                icon: Icons.chat_outlined,
                title: 'WhatsApp',
                value: contact.whatsapp,
                onTap: () => open(
                  () => launcher.whatsapp(contact.whatsapp, message: _intro),
                  'Our WhatsApp number is ${contact.whatsapp}.',
                ),
              ),
            if (contact.hasEmail)
              _ContactTile(
                icon: Icons.email_outlined,
                title: 'Email',
                value: contact.email,
                onTap: () => open(
                  () => launcher.email(contact.email, subject: 'Help request'),
                  'Our email is ${contact.email}.',
                ),
              ),
            if (contact.hasAddress)
              _ContactTile(
                icon: Icons.place_outlined,
                title: 'Visit us',
                value: contact.address,
                onTap: () => open(
                  () => launcher.map(contact.address),
                  'Our address is ${contact.address}.',
                ),
              ),
            if (contact.hasHours)
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Opening hours'),
                subtitle: Text(contact.hours),
              ),
          ],
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      onTap: onTap,
      trailing: IconButton(
        tooltip: 'Copy $title',
        icon: const Icon(Icons.copy_outlined),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) {
            showSuccessSnack(context, 'Copied to clipboard');
          }
        },
      ),
    );
  }
}

class _HelpTopics extends StatelessWidget {
  const _HelpTopics();

  static const _topics = <(String, String)>[
    (
      'How do I track my booking?',
      'Open My bookings and tap a booking. The progress list shows each step, '
          'and Notifications tells you when something changes.',
    ),
    (
      'How do I change or cancel a booking?',
      'Open the booking and choose Change address or time, or Cancel booking. These are possible '
          'until shortly before your slot starts; after that, please contact us.',
    ),
    (
      'My payment failed or is stuck',
      'Open the booking and tap the Pay button to try again. If money left your account '
          'but the booking still says Awaiting payment, contact us with the '
          'booking code.',
    ),
    (
      'My area is not serviceable',
      'Use the PIN code check on the home screen. We add new areas over time; '
          'contact us to ask about yours.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Common questions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final (question, answer) in _topics)
            ExpansionTile(
              title: Text(question),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(answer)],
            ),
        ],
      ),
    );
  }
}
