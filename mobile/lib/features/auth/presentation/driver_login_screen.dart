import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/network/auth_failure.dart';
import '../../../core/utils/validators.dart';
import '../providers/auth_controller.dart';
import 'widgets/auth_widgets.dart';

/// Drivers sign in with the ID and password the garage gave them. There is no
/// sign-up here: driver accounts are created by an administrator.
class DriverLoginScreen extends ConsumerStatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  ConsumerState<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends ConsumerState<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _driverId = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _driverId.dispose();
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
      await ref.read(authControllerProvider.notifier).signInDriver(
            driverId: _driverId.text,
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
      title: 'Driver sign in',
      subtitle: 'Use the driver ID and password provided by the garage.',
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
                  controller: _driverId,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username],
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.none,
                  validator: Validators.driverId,
                  decoration: const InputDecoration(labelText: 'Driver ID'),
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
