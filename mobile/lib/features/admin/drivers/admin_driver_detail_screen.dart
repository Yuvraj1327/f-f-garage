import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/driver.dart';
import '../../../data/providers/data_providers.dart';
import '../../booking/presentation/booking_widgets.dart';
import '../providers/admin_providers.dart';

/// One driver: details, switch on/off, change details, reset the password, and
/// the bookings they still have to do (so work can be moved before switching
/// them off).
class AdminDriverDetailScreen extends ConsumerWidget {
  const AdminDriverDetailScreen({super.key, required this.driverId});

  final String driverId;

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    DriverAccount driver,
    bool active,
  ) async {
    if (!active) {
      final open = driver.openBookings;
      final confirmed = await confirmAction(
        context,
        title: 'Switch off ${driver.label}?',
        message: open == 0
            ? 'They will be signed out of access immediately and cannot be '
                'given bookings.'
            : '${driver.label} still has $open open booking'
                '${open == 1 ? '' : 's'}. They will lose access immediately, '
                'so assign those bookings to someone else.',
        confirmLabel: 'Switch off',
      );
      if (!confirmed) return;
    }
    await ref
        .read(adminDriverRepositoryProvider)
        .update(driver.id, {'is_active': active});
    refreshAdminDrivers(ref);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    DriverAccount driver,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditDialog(driver: driver),
    );
    if (saved == true) refreshAdminDrivers(ref);
  }

  Future<void> _resetPassword(BuildContext context, DriverAccount driver) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PasswordDialog(driver: driver),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDriverProvider(driverId));
    return Scaffold(
      appBar: AppBar(title: Text(value.valueOrNull?.label ?? 'Driver')),
      body: SafeArea(
        child: AsyncView<DriverAccount>(
          value: value,
          onRetry: () => ref.invalidate(adminDriverProvider(driverId)),
          builder: (driver) => RefreshIndicator(
            onRefresh: () async {
              refreshAdminDrivers(ref);
              ref.invalidate(adminDriverOpenBookingsProvider(driverId));
              await ref.read(adminDriverProvider(driverId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(
                  title: 'Account',
                  children: [
                    SummaryRow(label: 'Name', value: driver.fullName ?? '-'),
                    SummaryRow(label: 'Driver ID', value: driver.loginId),
                    SummaryRow(label: 'Mobile', value: driver.phone ?? '-'),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            driver.isActive
                                ? 'Active - can sign in and take bookings'
                                : 'Switched off - cannot sign in',
                          ),
                        ),
                        ActiveSwitch(
                          key: const ValueKey('driver-active'),
                          value: driver.isActive,
                          semanticLabel: 'Driver active',
                          onChanged: (active) =>
                              _setActive(context, ref, driver, active),
                        ),
                      ],
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('edit-driver'),
                      onPressed: () => _edit(context, ref, driver),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit details'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('reset-password'),
                      onPressed: () => _resetPassword(context, driver),
                      icon: const Icon(Icons.lock_reset),
                      label: const Text('Reset password'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _OpenBookings(driverId: driver.id),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenBookings extends ConsumerWidget {
  const _OpenBookings({required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(adminDriverOpenBookingsProvider(driverId));
    return SectionCard(
      title: 'Open bookings',
      children: [
        value.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Column(
            children: [
              Text(errorMessage(error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(adminDriverOpenBookingsProvider(driverId)),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (page) {
            if (page.items.isEmpty) {
              return const Text('No open bookings.');
            }
            return Column(
              children: [for (final b in page.items) _BookingRow(booking: b)],
            );
          },
        ),
      ],
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('open-${booking.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text('${booking.code} - ${booking.serviceName}'),
      subtitle: Text('${formatDate(booking.date)}, ${booking.timeLabel}'),
      trailing: BookingStatusChip(status: booking.status),
      onTap: () => context.push(AppRoutes.adminBooking(booking.id)),
    );
  }
}

class _EditDialog extends ConsumerStatefulWidget {
  const _EditDialog({required this.driver});

  final DriverAccount driver;

  @override
  ConsumerState<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends ConsumerState<_EditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.driver.fullName ?? '');
  late final _phone = TextEditingController(text: widget.driver.phone ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final name = Validators.normalizeName(_name.text);
    final phone = Validators.normalizedMobile(_phone.text);
    final changes = <String, dynamic>{
      if (name != widget.driver.fullName) 'full_name': name,
      if (phone != null && phone != widget.driver.phone) 'phone': phone,
    };
    if (changes.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminDriverRepositoryProvider)
          .update(widget.driver.id, changes);
      if (mounted) Navigator.of(context).pop(true);
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
    return AlertDialog(
      title: const Text('Edit driver'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) Text(_error!),
            TextFormField(
              key: const ValueKey('edit-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: Validators.fullName,
            ),
            fieldGap,
            TextFormField(
              key: const ValueKey('edit-phone'),
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Mobile number'),
              keyboardType: TextInputType.phone,
              validator: Validators.phone,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save-driver'),
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog({required this.driver});

  final DriverAccount driver;

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(adminDriverRepositoryProvider)
          .resetPassword(widget.driver.id, _password.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, 'Password reset for ${widget.driver.label}');
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
    return AlertDialog(
      title: Text('Reset password for ${widget.driver.label}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) Text(_error!),
            TextFormField(
              key: const ValueKey('new-password'),
              controller: _password,
              decoration: const InputDecoration(labelText: 'New password'),
              obscureText: true,
              validator: Validators.newPassword,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('save-password'),
          onPressed: _busy ? null : _save,
          child: const Text('Reset'),
        ),
      ],
    );
  }
}
