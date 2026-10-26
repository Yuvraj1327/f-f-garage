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

class CustomerLoginScreen extends ConsumerStatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  ConsumerState<CustomerLoginScreen> createState() =>
      _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends ConsumerState<CustomerLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
      await ref.read(authControllerProvider.notifier).signInCustomer(
            email: _email.text,
            password: _password.text,
          );
      // On success the router moves to the home screen and this screen is
      // disposed, so there is nothing more to do here.
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
      // signedIn: the router moves on. redirecting (Web): the browser is on its
      // way to Google, so keep the button disabled. cancelled: back to normal.
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
    final notice = ref.watch(authControllerProvider.select((s) => s.notice));
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to book doorstep servicing for your bike or scooter.',
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
        GoogleSignInSection(busy: _busy, onPressed: _google),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => context.go(AppRoutes.register),
          child: const Text('New here? Create an account'),
        ),
        TextButton(
          key: const ValueKey('staff-login-link'),
          onPressed: _busy ? null : () => context.go(AppRoutes.staffLogin),
          child: const Text('Driver & Admin Login'),
        ),
      ],
    );
  }
}
