import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../data/models/service_area.dart';
import '../../../data/providers/data_providers.dart';
import '../../auth/presentation/widgets/auth_widgets.dart';

/// "Do you service my area?" - the customer types a PIN code and gets a clear
/// yes or no.
class PincodeCheckCard extends ConsumerStatefulWidget {
  const PincodeCheckCard({super.key});

  @override
  ConsumerState<PincodeCheckCard> createState() => _PincodeCheckCardState();
}

class _PincodeCheckCardState extends ConsumerState<PincodeCheckCard> {
  final _formKey = GlobalKey<FormState>();
  final _pincode = TextEditingController();
  bool _busy = false;
  String? _error;
  PincodeCheck? _result;

  @override
  void dispose() {
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(serviceAreaRepositoryProvider)
          .checkPincode(Validators.normalizePincode(_pincode.text));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
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
    final result = _result;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Do we service your area?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pincode,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.search,
                      maxLength: 7,
                      validator: Validators.pincode,
                      onFieldSubmitted: (_) => _check(),
                      decoration: const InputDecoration(
                        labelText: 'PIN code',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 96,
                      height: 48,
                      child: BusyButton(
                        label: 'Check',
                        busy: _busy,
                        onPressed: _check,
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                MessageBanner(message: _error!),
              ],
              if (result != null) ...[
                const SizedBox(height: 8),
                MessageBanner(
                  isError: !result.serviceable,
                  message: result.serviceable
                      ? 'Good news! We service ${result.areaName}, '
                          '${result.city} (${result.pincode}).'
                      : 'Sorry, we do not service ${result.pincode} yet.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
