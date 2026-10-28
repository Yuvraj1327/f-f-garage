import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/billing.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';

/// Who is raising extra work.
enum ExtraActor { driver, admin }

typedef ExtraKey = (String bookingId, ExtraActor actor);

/// The extra work requests on one booking, for the driver or the admin.
final extraRequestsProvider =
    FutureProvider.autoDispose.family<List<ExtraRequest>, ExtraKey>((ref, key) {
  final repo = ref.watch(billingRepositoryProvider);
  return key.$2 == ExtraActor.driver
      ? repo.driverExtras(key.$1)
      : repo.adminExtras(key.$1);
});

/// Extra parts or repairs found during the service. The customer must approve
/// each one before it is added to the bill; the job cannot be finished while
/// one is waiting for an answer.
class ExtraRequestsPanel extends ConsumerStatefulWidget {
  const ExtraRequestsPanel({
    super.key,
    required this.bookingId,
    required this.actor,
    required this.canRequest,
    this.onChanged,
  });

  final String bookingId;
  final ExtraActor actor;

  /// True while the service is in progress (the only time one can be raised).
  final bool canRequest;

  /// Called after a request is raised or withdrawn, so the screen can reload.
  final VoidCallback? onChanged;

  @override
  ConsumerState<ExtraRequestsPanel> createState() => _ExtraRequestsPanelState();
}

class _ExtraRequestsPanelState extends ConsumerState<ExtraRequestsPanel> {
  bool _busy = false;

  ExtraKey get _key => (widget.bookingId, widget.actor);

  Future<void> _request() async {
    final input = await showDialog<_ExtraInput>(
      context: context,
      builder: (_) => const _ExtraDialog(),
    );
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(billingRepositoryProvider);
      if (widget.actor == ExtraActor.driver) {
        await repo.driverRequest(
          widget.bookingId,
          name: input.name,
          amount: input.amount,
          chargeType: input.type,
          description: input.description,
        );
      } else {
        await repo.adminRequest(
          widget.bookingId,
          name: input.name,
          amount: input.amount,
          chargeType: input.type,
          description: input.description,
        );
      }
      if (!mounted) return;
      ref.invalidate(extraRequestsProvider(_key));
      widget.onChanged?.call();
      showSuccessSnack(context, 'Sent to the customer for approval.');
    } catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _withdraw(ExtraRequest extra) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(billingRepositoryProvider);
      if (widget.actor == ExtraActor.driver) {
        await repo.driverWithdraw(widget.bookingId, extra.id);
      } else {
        await repo.adminWithdraw(widget.bookingId, extra.id);
      }
      if (!mounted) return;
      ref.invalidate(extraRequestsProvider(_key));
      widget.onChanged?.call();
    } catch (error) {
      if (!mounted) return;
      ref.invalidate(extraRequestsProvider(_key));
      showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extras = ref.watch(extraRequestsProvider(_key)).valueOrNull ?? const [];
    if (extras.isEmpty && !widget.canRequest) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final waiting = extras.any((e) => e.isOpen);
    return Card(
      key: const ValueKey('extra-requests'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Extra work', style: textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Found something more to fix? Ask the customer. It is billed '
              'only if they approve.',
              style: textTheme.bodySmall,
            ),
            for (final extra in extras)
              Padding(
                key: ValueKey('extra-${extra.id}'),
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(extra.name, style: textTheme.titleSmall),
                          Text(
                            '${formatMoney(extra.amount)} - ${extra.status.label}',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (extra.isOpen)
                      TextButton(
                        key: ValueKey('withdraw-${extra.id}'),
                        onPressed: _busy ? null : () => _withdraw(extra),
                        child: const Text('Withdraw'),
                      ),
                  ],
                ),
              ),
            if (waiting) ...[
              const SizedBox(height: 8),
              Text(
                'Waiting for the customer. The job can be finished once every '
                'request is answered or withdrawn.',
                key: const ValueKey('extras-waiting'),
                style: textTheme.bodySmall,
              ),
            ],
            if (widget.canRequest) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('request-extra'),
                onPressed: _busy ? null : _request,
                icon: const Icon(Icons.add),
                label: const Text('Request extra work'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExtraInput {
  const _ExtraInput(this.name, this.amount, this.type, this.description);

  final String name;
  final double amount;
  final ExtraChargeType type;
  final String? description;
}

class _ExtraDialog extends StatefulWidget {
  const _ExtraDialog();

  @override
  State<_ExtraDialog> createState() => _ExtraDialogState();
}

class _ExtraDialogState extends State<_ExtraDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  ExtraChargeType _type = ExtraChargeType.sparePart;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _ExtraInput(
        _name.text.trim(),
        double.parse(_amount.text.trim()),
        _type,
        _description.text.trim().isEmpty ? null : _description.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Request extra work'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('extra-name'),
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 120,
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Say what needs doing'
                    : null,
                decoration: const InputDecoration(
                  labelText: 'What is needed',
                  hintText: 'Front brake pads',
                ),
              ),
              TextFormField(
                key: const ValueKey('extra-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim());
                  if (value == null || value <= 0) return 'Enter the amount';
                  if (value > 500000) return 'That amount is too large';
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'Amount (Rs)',
                  prefixText: '₹ ',
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<ExtraChargeType>(
                value: _type,
                items: [
                  for (final type in ExtraChargeType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(chargeTypeLabel(type)),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _type = value ?? ExtraChargeType.sparePart),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextFormField(
                controller: _description,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note for the customer (optional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('extra-submit'),
          onPressed: _submit,
          child: const Text('Send for approval'),
        ),
      ],
    );
  }
}
