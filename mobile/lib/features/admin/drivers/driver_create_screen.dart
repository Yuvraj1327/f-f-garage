import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// Creates a driver login (ID + password). Drivers cannot register themselves.
class DriverCreateScreen extends ConsumerStatefulWidget {
  const DriverCreateScreen({super.key});

  @override
  ConsumerState<DriverCreateScreen> createState() => _DriverCreateScreenState();
}

class _DriverCreateScreenState extends ConsumerState<DriverCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final driver = await ref.read(adminDriverRepositoryProvider).create(
            driverId: Validators.normalizeDriverId(_id.text),
            password: _password.text,
            fullName: Validators.normalizeName(_name.text),
            phone: Validators.normalizedMobile(_phone.text),
          );
      if (!mounted) return;
      refreshAdminDrivers(ref);
      showSnack(context, 'Driver ${driver.loginId} created');
      context.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Add driver',
      formKey: _formKey,
      busy: _busy,
      error: _error,
      onSave: _save,
      saveLabel: 'Create driver',
      children: [
        TextFormField(
          key: const ValueKey('driver-id'),
          controller: _id,
          decoration: const InputDecoration(labelText: 'Driver ID (login)'),
          autocorrect: false,
          validator: Validators.driverId,
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('driver-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Full name'),
          textCapitalization: TextCapitalization.words,
          validator: Validators.fullName,
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('driver-phone'),
          controller: _phone,
          decoration: const InputDecoration(labelText: 'Mobile number (optional)'),
          keyboardType: TextInputType.phone,
          validator: (value) => value == null || value.trim().isEmpty
              ? null
              : Validators.phone(value),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('driver-password'),
          controller: _password,
          decoration: const InputDecoration(labelText: 'Password'),
          obscureText: true,
          validator: (value) {
            final problem = Validators.newPassword(value);
            if (problem != null) return problem;
            if ((value ?? '').toLowerCase() ==
                Validators.normalizeDriverId(_id.text)) {
              return 'Password must not be the same as the driver ID';
            }
            return null;
          },
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('driver-confirm'),
          controller: _confirm,
          decoration: const InputDecoration(labelText: 'Confirm password'),
          obscureText: true,
          validator: (value) =>
              Validators.confirmPassword(value, _password.text),
        ),
      ],
    );
  }
}
