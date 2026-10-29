import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../auth/presentation/sign_out.dart';
import '../../auth/providers/auth_controller.dart';

/// Every top-level screen of the admin area.
enum AdminSection {
  dashboard('Dashboard', Icons.dashboard_outlined, Icons.dashboard, AppRoutes.adminHome),
  bookings('Bookings', Icons.receipt_long_outlined, Icons.receipt_long, AppRoutes.adminBookings),
  drivers('Drivers', Icons.badge_outlined, Icons.badge, AppRoutes.adminDrivers),
  services('Services', Icons.build_outlined, Icons.build, AppRoutes.adminServices),
  coupons('Coupons', Icons.local_offer_outlined, Icons.local_offer, AppRoutes.adminCoupons),
  areas('Service Areas', Icons.location_on_outlined, Icons.location_on, AppRoutes.adminAreas),
  availability('Availability', Icons.event_available_outlined, Icons.event_available,
      AppRoutes.adminAvailability),
  garage('Garage Details', Icons.storefront_outlined, Icons.storefront, AppRoutes.settingsGarage),
  settings('Settings', Icons.settings_outlined, Icons.settings, AppRoutes.settings);

  const AdminSection(this.label, this.icon, this.selectedIcon, this.route);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String route;
}

/// The sidebar's groups, in order. Settings sits at the bottom on its own.
const List<(String, List<AdminSection>)> adminNavGroups = [
  ('Overview', [AdminSection.dashboard]),
  ('Operations', [AdminSection.bookings, AdminSection.drivers]),
  ('Catalogue', [AdminSection.services, AdminSection.coupons]),
  ('Setup', [
    AdminSection.areas,
    AdminSection.availability,
    AdminSection.garage,
  ]),
];

/// Widths at which the layout changes: below [adminSidebarBreakpoint] the
/// sidebar is a drawer; from [adminSidebarOpenBreakpoint] it starts expanded
/// (between the two it starts as a slim icon rail).
const double adminSidebarBreakpoint = 720;
const double adminSidebarOpenBreakpoint = 1100;
const double adminContentMaxWidth = 1200;

/// The person's choice on wide screens: true = icon rail, false = full
/// sidebar, null = decide from the width.
final adminSidebarCollapsedProvider = StateProvider<bool?>((ref) => null);

/// The frame of every admin screen: a sidebar (a drawer on phones), a clean top
/// bar with the page title, the admin's profile and Sign out, and the page.
///
/// Pages that open from a list (a booking, a service form...) keep their own
/// back-button app bar and are not wrapped in this.
class AdminScaffold extends ConsumerWidget {
  const AdminScaffold({
    super.key,
    required this.section,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottom,
  });

  final AdminSection section;
  final Widget body;

  /// Defaults to the section's name.
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  PreferredSizeWidget _bar(Widget leading) => AppBar(
        automaticallyImplyLeading: false,
        leading: leading,
        title: Text(title ?? section.label),
        bottom: bottom,
        actions: [...?actions, const AdminProfileMenu(), const SizedBox(width: 8)],
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: adminContentMaxWidth),
        child: body,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < adminSidebarBreakpoint) {
          return Scaffold(
            appBar: _bar(
              Builder(
                builder: (context) => IconButton(
                  key: const ValueKey('admin-menu'),
                  tooltip: 'Menu',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
            drawer: Drawer(
              child: SafeArea(
                child: AdminSidebar(section: section, collapsed: false, inDrawer: true),
              ),
            ),
            floatingActionButton: floatingActionButton,
            body: content,
          );
        }
        final collapsed = ref.watch(adminSidebarCollapsedProvider) ??
            constraints.maxWidth < adminSidebarOpenBreakpoint;
        return Row(
          children: [
            AdminSidebar(section: section, collapsed: collapsed, inDrawer: false),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: Scaffold(
                appBar: _bar(
                  IconButton(
                    key: const ValueKey('admin-menu'),
                    tooltip: collapsed ? 'Expand menu' : 'Collapse menu',
                    icon: Icon(collapsed ? Icons.menu : Icons.menu_open),
                    onPressed: () => ref
                        .read(adminSidebarCollapsedProvider.notifier)
                        .state = !collapsed,
                  ),
                ),
                floatingActionButton: floatingActionButton,
                body: content,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The grouped navigation list. Collapsed it shows icons only (with tooltips).
class AdminSidebar extends ConsumerWidget {
  const AdminSidebar({
    super.key,
    required this.section,
    required this.collapsed,
    required this.inDrawer,
  });

  final AdminSection section;
  final bool collapsed;
  final bool inDrawer;

  void _open(BuildContext context, AdminSection target) {
    if (inDrawer) Navigator.of(context).pop();
    if (target != section) context.go(target.route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget item(AdminSection s) => _SidebarItem(
          key: ValueKey('side-${s.name}'),
          section: s,
          selected: s == section,
          collapsed: collapsed,
          onTap: () => _open(context, s),
        );
    final nav = ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final (label, sections) in adminNavGroups) ...[
          if (collapsed)
            const SizedBox(height: 8)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 4),
              child: Text(
                label.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          for (final s in sections) item(s),
        ],
      ],
    );
    return Material(
      color: scheme.surface,
      child: SizedBox(
        width: collapsed ? 72 : 264,
        child: Column(
          children: [
            _SidebarHeader(collapsed: collapsed),
            Expanded(child: nav),
            Divider(height: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: item(AdminSection.settings),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final mark = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.two_wheeler, color: scheme.onPrimary),
    );
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 16 : 20),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          mark,
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('F&F Garage',
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  Text('Admin', style: textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    super.key,
    required this.section,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final AdminSection section;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final tile = Semantics(
      button: true,
      selected: selected,
      label: section.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(selected ? section.selectedIcon : section.icon,
                  size: 22, color: color),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected ? scheme.primary : scheme.onSurface,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 10, vertical: 2),
      child: collapsed ? Tooltip(message: section.label, child: tile) : tile,
    );
  }
}

/// The admin's avatar in the top bar: name, e-mail, Settings and Sign out.
class AdminProfileMenu extends ConsumerWidget {
  const AdminProfileMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));
    final scheme = Theme.of(context).colorScheme;
    final name = profile?.displayName ?? 'Admin';
    final email = profile?.email ?? '';
    return PopupMenuButton<String>(
      key: const ValueKey('admin-profile-menu'),
      tooltip: 'Account',
      offset: const Offset(0, 44),
      onSelected: (value) {
        if (value == 'settings') context.go(AppRoutes.settings);
        if (value == 'signout') confirmSignOut(context, ref);
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: scheme.onSurface)),
              if (email.isNotEmpty && email != name)
                Text(email, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          key: ValueKey('admin-menu-settings'),
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
          ),
        ),
        const PopupMenuItem<String>(
          key: ValueKey('admin-menu-signout'),
          value: 'signout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: scheme.primaryContainer,
          child: Text(
            name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
