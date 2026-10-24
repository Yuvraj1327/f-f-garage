import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/auth_failure.dart';
import '../../../core/utils/validators.dart';
import '../providers/auth_controller.dart';
import 'widgets/auth_widgets.dart';

/// Sign-in for garage administrators (accounts are created in Supabase by the
/// project owner; there is no sign-up). Opens the service-management area.
class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
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
      await ref.read(authControllerProvider.notifier).signInAdmin(
            email: _email.text,
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
      title: 'Admin sign in',
      subtitle: 'Manage services, service areas and availability.',
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
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => context.go(AppRoutes.login),
          child: const Text('I am a customer'),
        ),
      ],
    );
  }
}
