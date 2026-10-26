import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/auth_failure.dart';
import '../../../core/utils/validators.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../auth/providers/auth_controller.dart';

/// Change the signed-in user's own password. The current password is checked
/// first; the new one is set through Supabase Auth (never stored by the app).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _done = false;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _new.text,
          );
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      setState(() {
        _busy = false;
        _done = true;
      });
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
    final toggle = IconButton(
      tooltip: _hide ? 'Show passwords' : 'Hide passwords',
      icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _hide = !_hide),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_error != null) MessageBanner(message: _error!),
              if (_done)
                const MessageBanner(
                  message: 'Password changed. Use the new one next time you sign in.',
                  isError: false,
                ),
              TextFormField(
                key: const ValueKey('current-password'),
                controller: _current,
                enabled: !_busy,
                obscureText: _hide,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                validator: Validators.requiredPassword,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: toggle,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('new-password'),
                controller: _new,
                enabled: !_busy,
                obscureText: _hide,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final problem = Validators.newPassword(value);
                  if (problem != null) return problem;
                  if (value == _current.text) {
                    return 'Choose a different password from the current one';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 8 characters',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('confirm-password'),
                controller: _confirm,
                enabled: !_busy,
                obscureText: _hide,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (value) => Validators.confirmPassword(value, _new.text),
                decoration: const InputDecoration(labelText: 'Confirm new password'),
              ),
              const SizedBox(height: 24),
              BusyButton(label: 'Update password', busy: _busy, onPressed: _submit),
              const SizedBox(height: 16),
              Text(
                'Signed in with Google? Your Google account has its own password; '
                'manage it in your Google account settings.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
