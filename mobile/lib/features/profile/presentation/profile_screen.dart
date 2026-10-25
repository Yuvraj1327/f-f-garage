import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/customer_nav.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/user_profile.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../auth/providers/auth_controller.dart';

/// The signed-in user's profile. Customers can edit their name and phone;
/// drivers see their details read-only (the garage manages driver accounts).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(authControllerProvider.select((s) => s.profile));

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      bottomNavigationBar: customerNavFor(ref, CustomerTab.profile),
      body: SafeArea(
        child: profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  _ProfileHeader(profile: profile),
                  const SizedBox(height: 16),
                  if (profile.role == UserRole.customer)
                    _CustomerProfileForm(profile: profile)
                  else
                    _ReadOnlyProfileDetails(profile: profile),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.support_agent),
                      title: const Text('Help & support'),
                      subtitle: const Text('Contact the garage'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push(AppRoutes.support),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                        width: 1.5,
                      ),
                    ),
                    onPressed: () => _confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to use the app.',
      confirmLabel: 'Sign out',
    );
    if (confirmed) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

/// Avatar with initials, the name and the account type.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final UserProfile profile;

  String get _initial {
    final name = profile.fullName?.trim() ?? '';
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }

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
    final name = profile.fullName;
    return Row(
      children: [
        ExcludeSemantics(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              _initial,
              style: textTheme.headlineSmall
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name != null && name.isNotEmpty)
                Text(
                  name,
                  style: textTheme.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(_roleLabel, style: textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyProfileDetails extends StatelessWidget {
  const _ReadOnlyProfileDetails({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReadOnlyRow(label: 'Name', value: profile.fullName),
        if (profile.role == UserRole.driver)
          _ReadOnlyRow(label: 'Driver ID', value: profile.driverLoginId)
        else ...[
          _ReadOnlyRow(label: 'Email', value: profile.email),
          const _ReadOnlyRow(label: 'Role', value: 'Administrator'),
        ],
        _ReadOnlyRow(label: 'Mobile', value: profile.phone),
        const SizedBox(height: 8),
        Text(
          profile.role == UserRole.driver
              ? 'To change these details, contact the garage.'
              : 'Administrator details are managed in Supabase.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Text(
        (value == null || value!.isEmpty) ? '-' : value!,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _CustomerProfileForm extends ConsumerStatefulWidget {
  const _CustomerProfileForm({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_CustomerProfileForm> createState() =>
      _CustomerProfileFormState();
}

class _CustomerProfileFormState extends ConsumerState<_CustomerProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _busy = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.fullName ?? '');
    _phone = TextEditingController(
      text: _displayPhone(widget.profile.phone),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// The form shows the 10 digits; "+91" is already in the field's prefix.
  static String _displayPhone(String? stored) {
    if (stored == null) return '';
    return stored.startsWith('+91') ? stored.substring(3) : stored;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      final updated = await ref.read(profileRepositoryProvider).updateMyProfile(
            fullName: Validators.normalizeName(_name.text),
            phone: Validators.normalizedMobile(_phone.text),
          );
      if (!mounted) return;
      ref.read(authControllerProvider.notifier).profileUpdated(updated);
      setState(() {
        _busy = false;
        _saved = true;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) MessageBanner(message: _error!),
          if (_saved)
            const MessageBanner(message: 'Profile updated.', isError: false),
          _ReadOnlyRow(label: 'Email', value: widget.profile.email),
          const SizedBox(height: 8),
          TextFormField(
            controller: _name,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            validator: Validators.fullName,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _save(),
            validator: Validators.phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '+91 ',
            ),
          ),
          const SizedBox(height: 24),
          BusyButton(label: 'Save changes', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
