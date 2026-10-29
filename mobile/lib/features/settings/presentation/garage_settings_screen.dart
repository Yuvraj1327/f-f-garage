import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/garage_settings.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';
import '../../support/providers/support_providers.dart';
import '../providers/garage_settings_providers.dart';
import '../../admin/presentation/admin_scaffold.dart';

/// Administrators only: the garage's name and contact details. Saved through
/// `PUT /admin/garage-settings`; customers and drivers see them on Help &
/// support straight away. (The router and the backend both refuse other roles.)
class GarageSettingsScreen extends ConsumerWidget {
  const GarageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(garageSettingsProvider);
    return AdminScaffold(
      section: AdminSection.garage,
      body: SafeArea(
        child: AsyncView<GarageSettings>(
          value: settings,
          onRetry: () => ref.invalidate(garageSettingsProvider),
          builder: (data) => _GarageForm(initial: data),
        ),
      ),
    );
  }
}

class _GarageForm extends ConsumerStatefulWidget {
  const _GarageForm({required this.initial});

  final GarageSettings initial;

  @override
  ConsumerState<_GarageForm> createState() => _GarageFormState();
}

class _GarageFormState extends ConsumerState<_GarageForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _whatsapp = TextEditingController(text: widget.initial.whatsapp);
  late final _email = TextEditingController(text: widget.initial.email);
  late final _address = TextEditingController(text: widget.initial.address);
  late final _hours = TextEditingController(text: widget.initial.hours);
  late final _refund =
      TextEditingController(text: widget.initial.refundPolicy);
  bool _busy = false;
  bool _saved = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _whatsapp, _email, _address, _hours, _refund]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _optionalPhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return digits.length < 7 || digits.length > 15
        ? 'Enter 7 to 15 digits'
        : null;
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      await ref.read(garageSettingsRepositoryProvider).save(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            whatsapp: _whatsapp.text.trim(),
            email: _email.text.trim(),
            address: _address.text.trim(),
            hours: _hours.text.trim(),
            refundPolicy: _refund.text.trim(),
          );
      ref.invalidate(supportContactProvider);
      if (!mounted) return;
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
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (!widget.initial.fromDatabase && !_saved)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'These are the server defaults. Save to make them the '
                "garage's own details.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (_error != null) MessageBanner(message: _error!),
          if (_saved)
            const MessageBanner(message: 'Garage details saved.', isError: false),
          TextFormField(
            key: const ValueKey('garage-name'),
            controller: _name,
            enabled: !_busy,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            maxLength: 120,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter the garage name' : null,
            decoration: const InputDecoration(labelText: 'Garage name'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('garage-phone'),
            controller: _phone,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: _optionalPhone,
            decoration: const InputDecoration(labelText: 'Business phone'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('garage-whatsapp'),
            controller: _whatsapp,
            enabled: !_busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: _optionalPhone,
            decoration: const InputDecoration(labelText: 'WhatsApp number'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('garage-email'),
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (v) {
              final text = (v ?? '').trim();
              if (text.isEmpty) return null;
              return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)
                  ? null
                  : 'Enter a valid email address';
            },
            decoration: const InputDecoration(labelText: 'Business email'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('garage-address'),
            controller: _address,
            enabled: !_busy,
            maxLines: 2,
            maxLength: 300,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Address'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('garage-hours'),
            controller: _hours,
            enabled: !_busy,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Opening hours',
              hintText: 'Mon-Sat, 9 am - 7 pm',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: const ValueKey('garage-refund-policy'),
            controller: _refund,
            enabled: !_busy,
            minLines: 2,
            maxLines: 5,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Refund policy (shown to customers)',
              helperText: 'Refunds are decided by an admin case by case and '
                  'made in the payment gateway, then recorded here. '
                  'Nothing is refunded automatically.',
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          BusyButton(label: 'Save', busy: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
