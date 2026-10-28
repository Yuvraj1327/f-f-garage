import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/coupon.dart';
import '../../../data/providers/data_providers.dart';

final adminCouponsProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(billingRepositoryProvider).coupons(),
);

/// Discount codes customers can enter at checkout. An admin creates and
/// switches them on or off; the server checks every rule when a code is used.
class AdminCouponsScreen extends ConsumerWidget {
  const AdminCouponsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _CouponDialog(),
    );
    if (saved == true) ref.invalidate(adminCouponsProvider);
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, Coupon coupon) async {
    try {
      await ref
          .read(billingRepositoryProvider)
          .updateCoupon(coupon.id, {'is_active': !coupon.isActive});
      ref.invalidate(adminCouponsProvider);
    } catch (error) {
      if (context.mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(adminCouponsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Coupons')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('new-coupon'),
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New coupon'),
      ),
      body: SafeArea(
        child: AsyncView<List<Coupon>>(
          value: coupons,
          onRetry: () => ref.invalidate(adminCouponsProvider),
          builder: (items) {
            if (items.isEmpty) {
              return const EmptyView(
                icon: Icons.local_offer_outlined,
                message: 'No coupons yet. Create one to offer a discount.',
              );
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(adminCouponsProvider.future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  for (final coupon in items)
                    Card(
                      key: ValueKey('coupon-${coupon.id}'),
                      child: ListTile(
                        leading: const Icon(Icons.local_offer_outlined),
                        title: Text(coupon.code),
                        subtitle: Text(
                          [
                            coupon.offerLabel,
                            if (coupon.minOrderAmount > 0)
                              'min ${formatMoney(coupon.minOrderAmount)}',
                            if (coupon.endsAt != null)
                              'until ${formatDate(coupon.endsAt!.toLocal())}',
                            'used ${coupon.timesUsed}'
                                '${coupon.usageLimit == null ? '' : '/${coupon.usageLimit}'}',
                          ].join(' - '),
                        ),
                        trailing: Switch(
                          key: ValueKey('coupon-switch-${coupon.id}'),
                          value: coupon.isActive,
                          onChanged: (_) => _toggle(context, ref, coupon),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CouponDialog extends ConsumerStatefulWidget {
  const _CouponDialog();

  @override
  ConsumerState<_CouponDialog> createState() => _CouponDialogState();
}

class _CouponDialogState extends ConsumerState<_CouponDialog> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _max = TextEditingController();
  final _min = TextEditingController();
  final _limit = TextEditingController();
  final _days = TextEditingController();
  String _type = 'percent';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _value, _max, _min, _limit, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _number(TextEditingController c) => double.tryParse(c.text.trim());

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final days = int.tryParse(_days.text.trim());
    try {
      await ref.read(billingRepositoryProvider).createCoupon(
            code: _code.text.trim(),
            discountType: _type,
            discountValue: _number(_value)!,
            maxDiscount: _type == 'percent' ? _number(_max) : null,
            minOrderAmount: _number(_min) ?? 0,
            endsAt: days == null
                ? null
                : DateTime.now().add(Duration(days: days)),
            usageLimit: int.tryParse(_limit.text.trim()),
          );
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
      title: const Text('New coupon'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              TextFormField(
                key: const ValueKey('coupon-code'),
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                maxLength: 20,
                validator: (v) {
                  final text = (v ?? '').trim();
                  return RegExp(r'^[A-Za-z0-9_-]{3,20}$').hasMatch(text)
                      ? null
                      : '3-20 letters, digits, - or _';
                },
                decoration: const InputDecoration(labelText: 'Code'),
              ),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'percent', label: Text('% off')),
                  ButtonSegment(value: 'flat', label: Text('₹ off')),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              TextFormField(
                key: const ValueKey('coupon-value'),
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim());
                  if (value == null || value <= 0) return 'Enter a value';
                  if (_type == 'percent' && value > 100) return 'At most 100';
                  return null;
                },
                decoration: InputDecoration(
                  labelText: _type == 'percent' ? 'Percent off' : 'Rupees off',
                ),
              ),
              if (_type == 'percent')
                TextFormField(
                  controller: _max,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Maximum discount (optional)',
                    prefixText: '₹ ',
                  ),
                ),
              TextFormField(
                controller: _min,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Minimum order (optional)',
                  prefixText: '₹ ',
                ),
              ),
              TextFormField(
                controller: _limit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total uses (optional)',
                  helperText: 'Each customer can use it once',
                ),
              ),
              TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Valid for days (optional)',
                ),
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
          key: const ValueKey('coupon-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
