import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/auth_failure.dart';
import '../../../core/utils/validators.dart';
import '../providers/auth_controller.dart';
import 'widgets/auth_widgets.dart';

/// One sign-in for drivers and administrators. There is no sign-up here and no
/// Google option: driver accounts are created by an administrator, and admin
/// accounts by the project owner. After signing in, the account's role (read
/// from the backend profile) decides the dashboard: drivers and admins are
/// taken to their own area, and a customer account is turned away.
class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  /// A driver ID, or an email address.
  static String? _validateIdentifier(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return 'Enter your driver ID or email';
    }
    return text.contains('@') ? Validators.email(text) : Validators.driverId(text);
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).signInStaff(
            identifier: _identifier.text,
            password: _password.text,
          );
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(authControllerProvider.select((s) => s.notice));
    return AuthScaffold(
      title: 'Driver & Admin Login',
      subtitle: 'Sign in with the driver ID or email and password the garage '
          'gave you.',
      showBack: true,
      children: [
        if (notice != null && _error == null)
          MessageBanner(message: notice, isError: false),
        if (_error != null) MessageBanner(message: _error!),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('staff-identifier'),
                  controller: _identifier,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  validator: _validateIdentifier,
                  decoration: const InputDecoration(
                    labelText: 'Driver ID or email',
                  ),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  label: 'Password',
                  enabled: !_busy,
                  validator: Validators.requiredPassword,
                  onSubmitted: _submit,
                ),
                const SizedBox(height: 24),
                BusyButton(label: 'Sign in', busy: _busy, onPressed: _submit),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => context.go(AppRoutes.login),
          child: const Text('I am a customer'),
        ),
      ],
    );
  }
}
