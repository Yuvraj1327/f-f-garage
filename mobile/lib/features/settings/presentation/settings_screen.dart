import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/preferences/app_preferences.dart';
import '../../../core/widgets/app_nav.dart';
import '../../../core/widgets/section_header.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/user_profile.dart';
import '../../admin/presentation/admin_scaffold.dart';
import '../../auth/providers/auth_controller.dart';
import '../../auth/presentation/sign_out.dart';

/// Settings for every role: profile, password, theme, notifications, help,
/// about, privacy and sign out. Business settings appear for administrators
/// only. A role can never be changed from here: the profile screen has no role
/// field, and the backend ignores any attempt (see `PATCH /profiles/me`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    final role = profile?.role;
    final content = SafeArea(
        child: profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _AccountHeader(profile: profile),
                  const SectionHeader(title: 'Account'),
                  _Group(children: [
                    _NavTile(
                      key: const ValueKey('settings-profile'),
                      icon: Icons.person_outline,
                      title: 'Edit profile',
                      subtitle: role == UserRole.customer
                          ? 'Name and mobile number'
                          : 'Your details',
                      onTap: () => context.push(AppRoutes.profile),
                    ),
                    if (role == UserRole.customer)
                      _NavTile(
                        key: const ValueKey('settings-vehicles'),
                        icon: Icons.two_wheeler,
                        title: 'My vehicles',
                        subtitle: 'Add, edit or remove your bike or scooter',
                        onTap: () => context.push(AppRoutes.vehicles),
                      ),
                    _NavTile(
                      key: const ValueKey('settings-password'),
                      icon: Icons.lock_outline,
                      title: 'Change password',
                      onTap: () => context.push(AppRoutes.settingsPassword),
                    ),
                  ]),
                  if (role == UserRole.admin) ...[
                    const SectionHeader(title: 'Garage'),
                    _Group(children: [
                      _NavTile(
                        key: const ValueKey('settings-garage'),
                        icon: Icons.storefront_outlined,
                        title: 'Garage details',
                        subtitle: 'Name, phone, email, address, hours',
                        onTap: () => context.push(AppRoutes.settingsGarage),
                      ),
                    ]),
                  ],
                  const SectionHeader(title: 'Appearance'),
                  const _ThemeSelector(),
                  if (role == UserRole.customer) ...[
                    const SectionHeader(title: 'Notifications'),
                    const _NotificationSettings(),
                  ],
                  const SectionHeader(title: 'More'),
                  _Group(children: [
                    _NavTile(
                      key: const ValueKey('settings-help'),
                      icon: Icons.support_agent_outlined,
                      title: 'Help & Support',
                      onTap: () => context.push(AppRoutes.support),
                    ),
                    _NavTile(
                      key: const ValueKey('settings-about'),
                      icon: Icons.info_outline,
                      title: 'About App',
                      onTap: () => context.push(AppRoutes.settingsAbout),
                    ),
                    _NavTile(
                      key: const ValueKey('settings-privacy'),
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      onTap: () => context.push(AppRoutes.settingsPrivacy),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const ValueKey('settings-logout'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                        width: 1.5,
                      ),
                    ),
                    onPressed: () => confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ],
              ),
    );
    if (role == UserRole.admin) {
      return AdminScaffold(section: AdminSection.settings, body: content);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      bottomNavigationBar: navFor(ref, NavTab.settings),
      body: content,
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.profile});

  final UserProfile profile;

  String get _roleLabel {
    switch (profile.role) {
      case UserRole.customer:
        return 'Customer';
      case UserRole.driver:
        return 'Driver';
      case UserRole.admin:
        return 'Administrator';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final name = profile.displayName;
    final secondary = profile.role == UserRole.driver
        ? (profile.driverLoginId ?? '')
        : (profile.email ?? '');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                  style: textTheme.titleLarge
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (secondary.isNotEmpty)
                    Text(secondary,
                        style: textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(_roleLabel,
                      style: textTheme.labelMedium
                          ?.copyWith(color: scheme.primary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A card holding a few tiles separated by dividers.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Light / Dark / System default. Saved on the device and applied at once.
class _ThemeSelector extends ConsumerWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;
    Widget option(String key, ThemeMode value, IconData icon, String label,
        String? hint) {
      final selected = mode == value;
      return Semantics(
        inMutuallyExclusiveGroup: true,
        selected: selected,
        child: ListTile(
          key: ValueKey(key),
          leading: Icon(icon, color: scheme.primary),
          title: Text(label),
          subtitle: hint == null ? null : Text(hint),
          trailing: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? scheme.primary : scheme.outline,
          ),
          onTap: () => ref.read(themeModeProvider.notifier).setMode(value),
        ),
      );
    }

    return _Group(children: [
      option('theme-light', ThemeMode.light, Icons.light_mode_outlined, 'Light',
          'Default'),
      option('theme-dark', ThemeMode.dark, Icons.dark_mode_outlined, 'Dark',
          null),
      option('theme-system', ThemeMode.system, Icons.brightness_auto_outlined,
          'System default', 'Follows your phone'),
    ]);
  }
}

/// Customer-only: what the app does on this phone. Kept on the device; the
/// garage sends no push messages, so there is nothing to opt out of on the
/// server.
class _NotificationSettings extends ConsumerWidget {
  const _NotificationSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final controller = ref.read(notificationPrefsProvider.notifier);
    return _Group(children: [
      SwitchListTile(
        key: const ValueKey('pref-badge'),
        secondary: const Icon(Icons.notifications_none),
        title: const Text('Unread badge'),
        subtitle: const Text('Show the number of unread notifications'),
        value: prefs.showBadge,
        onChanged: controller.setShowBadge,
      ),
      SwitchListTile(
        key: const ValueKey('pref-auto-refresh'),
        secondary: const Icon(Icons.sync),
        title: const Text('Keep updates live'),
        subtitle: const Text(
          'Check for new notifications and booking progress automatically',
        ),
        value: prefs.autoRefresh,
        onChanged: controller.setAutoRefresh,
      ),
    ]);
  }
}
