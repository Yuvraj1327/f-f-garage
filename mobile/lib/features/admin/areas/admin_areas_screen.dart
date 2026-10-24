import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/service_area.dart';
import '../../../data/providers/data_providers.dart';
import '../providers/admin_providers.dart';

/// PIN codes where doorstep service is available: add, edit, activate or
/// deactivate, remove.
class AdminAreasScreen extends ConsumerStatefulWidget {
  const AdminAreasScreen({super.key});

  @override
  ConsumerState<AdminAreasScreen> createState() => _AdminAreasScreenState();
}

class _AdminAreasScreenState extends ConsumerState<AdminAreasScreen> {
  String _search = '';

  Future<void> _openForm([ServiceArea? area]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AreaDialog(existing: area),
    );
    if (saved == true) {
      ref.invalidate(adminAreasProvider);
    }
  }

  Future<void> _delete(ServiceArea area) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${area.pincode}?',
      message: 'Customers in ${area.areaName} will no longer be able to book. '
          'Existing bookings keep their address. To pause the area instead, '
          'switch it off.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await ref.read(serviceAreaRepositoryProvider).delete(area.id);
      ref.invalidate(adminAreasProvider);
    } catch (error) {
      if (mounted) {
        showErrorSnack(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final areas = ref.watch(adminAreasProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Service areas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add PIN code'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search PIN code, area or city',
                ),
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
              ),
            ),
            Expanded(
              child: AsyncView<List<ServiceArea>>(
                value: areas,
                onRetry: () => ref.invalidate(adminAreasProvider),
                builder: (all) {
                  final items = all
                      .where(
                        (a) =>
                            _search.isEmpty ||
                            a.pincode.contains(_search) ||
                            a.areaName.toLowerCase().contains(_search) ||
                            a.city.toLowerCase().contains(_search),
                      )
                      .toList();
                  if (all.isEmpty) {
                    return const EmptyView(
                      message: 'No service areas yet. Add the PIN codes you '
                          'serve.',
                    );
                  }
                  if (items.isEmpty) {
                    return const EmptyView(message: 'No matching areas.');
                  }
                  return RefreshIndicator(
                    onRefresh: () => ref.refresh(adminAreasProvider.future),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88, top: 8),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final area = items[index];
                        return ListTile(
                          title: Row(
                            children: [
                              Text(area.pincode),
                              if (!area.isActive) ...[
                                const SizedBox(width: 8),
                                const InactiveBadge(),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '${area.areaName}, ${area.city}, ${area.state}',
                          ),
                          onTap: () => _openForm(area),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ActiveSwitch(
                                value: area.isActive,
                                semanticLabel: '${area.pincode} active',
                                onChanged: (value) async {
                                  await ref
                                      .read(serviceAreaRepositoryProvider)
                                      .update(area.id, {'is_active': value});
                                  ref.invalidate(adminAreasProvider);
                                },
                              ),
                              IconButton(
                                tooltip: 'Remove ${area.pincode}',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(area),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaDialog extends ConsumerStatefulWidget {
  const _AreaDialog({this.existing});

  final ServiceArea? existing;

  @override
  ConsumerState<_AreaDialog> createState() => _AreaDialogState();
}

class _AreaDialogState extends ConsumerState<_AreaDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _pincode;
  late final TextEditingController _area;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late bool _active;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _pincode = TextEditingController(text: a?.pincode ?? '');
    _area = TextEditingController(text: a?.areaName ?? '');
    _city = TextEditingController(text: a?.city ?? '');
    _state = TextEditingController(text: a?.state ?? '');
    _active = a?.isActive ?? true;
  }

  @override
  void dispose() {
    _pincode.dispose();
    _area.dispose();
    _city.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(serviceAreaRepositoryProvider);
    final pincode = Validators.normalizePincode(_pincode.text);
    final area = Validators.normalizeName(_area.text);
    final city = Validators.normalizeName(_city.text);
    final state = Validators.normalizeName(_state.text);
    try {
      final existing = widget.existing;
      if (existing == null) {
        await repo.create(
          pincode: pincode,
          areaName: area,
          city: city,
          state: state,
          isActive: _active,
        );
      } else {
        final changes = <String, dynamic>{
          if (pincode != existing.pincode) 'pincode': pincode,
          if (area != existing.areaName) 'area_name': area,
          if (city != existing.city) 'city': city,
          if (state != existing.state) 'state': state,
          if (_active != existing.isActive) 'is_active': _active,
        };
        if (changes.isNotEmpty) {
          await repo.update(existing.id, changes);
        }
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
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
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit service area' : 'Add service area'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              TextFormField(
                controller: _pincode,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 7, // room for a space typed in the middle
                validator: Validators.pincode,
                decoration: const InputDecoration(
                  labelText: 'PIN code',
                  counterText: '',
                ),
              ),
              fieldGap,
              TextFormField(
                controller: _area,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    Validators.requiredText(v, label: 'area name', max: 80),
                decoration: const InputDecoration(labelText: 'Area name'),
              ),
              fieldGap,
              TextFormField(
                controller: _city,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    Validators.requiredText(v, label: 'city', max: 80),
                decoration: const InputDecoration(labelText: 'City'),
              ),
              fieldGap,
              TextFormField(
                controller: _state,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    Validators.requiredText(v, label: 'state', max: 80),
                decoration: const InputDecoration(labelText: 'State'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Serviceable'),
                value: _active,
                onChanged: _busy ? null : (v) => setState(() => _active = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
