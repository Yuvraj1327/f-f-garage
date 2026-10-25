import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/auth_failure.dart';
import '../../../core/utils/validators.dart';
import '../../../data/services/auth_gateway.dart' show GoogleSignInResult;
import '../providers/auth_controller.dart';
import 'widgets/auth_widgets.dart';
import 'widgets/google_sign_in_button.dart';

/// Customer registration. Drivers cannot register here.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _confirmationSent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
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
      final signedIn =
          await ref.read(authControllerProvider.notifier).registerCustomer(
                fullName: _name.text,
                email: _email.text,
                phone: _phone.text,
                password: _password.text,
              );
      if (!signedIn && mounted) {
        setState(() {
          _busy = false;
          _confirmationSent = true;
        });
      }
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _google() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(authControllerProvider.notifier).signInWithGoogle();
      if (!mounted) return;
      if (result == GoogleSignInResult.cancelled) {
        setState(() => _busy = false);
      }
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
    if (_confirmationSent) {
      return AuthScaffold(
        title: 'Check your email',
        subtitle: 'We sent a confirmation link to ${_email.text.trim()}. '
            'Open it, then sign in.',
        showBack: true,
        children: [
          FilledButton(
            onPressed: () => context.go(AppRoutes.login),
            child: const Text('Go to sign in'),
          ),
        ],
      );
    }

    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Book doorstep servicing in a few taps.',
      showBack: true,
      children: [
        if (_error != null) MessageBanner(message: _error!),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.fullName,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  validator: Validators.email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: Validators.phone,
                  decoration: const InputDecoration(
                    labelText: 'Mobile number',
                    prefixText: '+91 ',
                  ),
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _password,
                  label: 'Password',
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.newPassword,
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirm,
                  label: 'Confirm password',
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (value) =>
                      Validators.confirmPassword(value, _password.text),
                  onSubmitted: _submit,
                ),
                const SizedBox(height: 24),
                BusyButton(
                  label: 'Create account',
                  busy: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
        GoogleSignInSection(busy: _busy, onPressed: _google),
        const SizedBox(height: 8),
        Text(
          'With Google you can add your mobile number later, in your profile. '
          'We need it before your first booking.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => context.go(AppRoutes.login),
          child: const Text('Already have an account? Sign in'),
        ),
      ],
    );
  }
}
