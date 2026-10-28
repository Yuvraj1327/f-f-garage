import 'package:flutter/material.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';

/// The text boxes and choices that describe what a package sells: price,
/// discount, advance share, labour, time, warranty, repeat interval and the
/// lists of what is included. Shared by the package form and the service
/// editor (which edits a service's single package inline).
class PackageDraft {
  PackageDraft([ServicePackage? p])
      : name = TextEditingController(text: p?.name ?? ''),
        price = TextEditingController(text: p == null ? '' : plain(p.price)),
        original = TextEditingController(
          text: p?.originalPrice == null ? '' : plain(p!.originalPrice!),
        ),
        advance = TextEditingController(
          text: p?.advancePercent == null ? '' : plain(p!.advancePercent!),
        ),
        labour = TextEditingController(
          text: p?.labourCharge == null ? '' : plain(p!.labourCharge!),
        ),
        duration = TextEditingController(
          text: p?.estimatedDurationMinutes?.toString() ?? '',
        ),
        warranty = TextEditingController(text: p?.warrantyDays?.toString() ?? ''),
        repeat = TextEditingController(
          text: p?.repeatIntervalDays?.toString() ?? '',
        ),
        description = TextEditingController(text: p?.description ?? ''),
        inclusions = TextEditingController(text: p?.inclusions.join('\n') ?? ''),
        parts = TextEditingController(text: p?.includedParts.join('\n') ?? ''),
        exclusions = TextEditingController(text: p?.exclusions.join('\n') ?? ''),
        partsNote = TextEditingController(text: p?.partsNote ?? ''),
        order = TextEditingController(text: (p?.displayOrder ?? 0).toString()),
        partsPolicy = p?.partsPolicy ?? PartsPolicy.serviceOnly,
        active = p?.isActive ?? true;

  final TextEditingController name;
  final TextEditingController price;
  final TextEditingController original;
  final TextEditingController advance;
  final TextEditingController labour;
  final TextEditingController duration;
  final TextEditingController warranty;
  final TextEditingController repeat;
  final TextEditingController description;
  final TextEditingController inclusions;
  final TextEditingController parts;
  final TextEditingController exclusions;
  final TextEditingController partsNote;
  final TextEditingController order;
  PartsPolicy partsPolicy;
  bool active;

  void dispose() {
    for (final c in [
      name, price, original, advance, labour, duration, warranty, repeat,
      description, inclusions, parts, exclusions, partsNote, order, //
    ]) {
      c.dispose();
    }
  }

  /// 499.0 -> "499", 499.5 -> "499.50" (what a person would type).
  static String plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  /// One entry per line; blanks and repeats are dropped (the server does the
  /// same, so what is saved matches what the admin sees after saving).
  static List<String> lines(TextEditingController controller) {
    final seen = <String>{};
    final result = <String>[];
    for (final line in controller.text.split('\n')) {
      final text = Validators.normalizeName(line);
      if (text.isNotEmpty && seen.add(text.toLowerCase())) result.add(text);
    }
    return result;
  }

  String? _validateList(TextEditingController c, int max) {
    final items = lines(c);
    if (items.length > max) return 'At most $max entries';
    if (items.any((i) => i.length > 120)) {
      return 'Each entry must be at most 120 characters';
    }
    return null;
  }

  double? get priceValue => Validators.parseAmount(price.text);
  double? get originalValue =>
      original.text.trim().isEmpty ? null : Validators.parseAmount(original.text);
  double? get advanceValue =>
      advance.text.trim().isEmpty ? null : double.tryParse(advance.text.trim());
  double? get labourValue =>
      labour.text.trim().isEmpty ? null : Validators.parseAmount(labour.text);
  int? get durationValue => int.tryParse(duration.text.trim());
  int? get warrantyValue => int.tryParse(warranty.text.trim());
  int? get repeatValue => int.tryParse(repeat.text.trim());
  String? get descriptionValue =>
      description.text.trim().isEmpty ? null : description.text.trim();
  String? get noteValue =>
      partsNote.text.trim().isEmpty ? null : partsNote.text.trim();

  /// The values that differ from [existing], as an update request body.
  Map<String, dynamic> changes(ServicePackage existing, {bool withName = true}) {
    final n = Validators.normalizeName(name.text);
    String joined(List<String> l) => l.join('\n');
    return {
      if (withName && n != existing.name) 'name': n,
      if (priceValue != existing.price) 'price': priceValue!.toStringAsFixed(2),
      if (originalValue != existing.originalPrice)
        'original_price': originalValue?.toStringAsFixed(2),
      if (advanceValue != existing.advancePercent)
        'advance_percent': advanceValue?.toStringAsFixed(2),
      if (labourValue != existing.labourCharge)
        'labour_charge': labourValue?.toStringAsFixed(2),
      if (warrantyValue != existing.warrantyDays) 'warranty_days': warrantyValue,
      if (repeatValue != existing.repeatIntervalDays)
        'repeat_interval_days': repeatValue,
      if (durationValue != existing.estimatedDurationMinutes)
        'estimated_duration_minutes': durationValue,
      if (joined(lines(exclusions)) != joined(existing.exclusions))
        'exclusions': lines(exclusions),
      if (joined(lines(inclusions)) != joined(existing.inclusions))
        'inclusions': lines(inclusions),
      if (joined(lines(parts)) != joined(existing.includedParts))
        'included_parts': lines(parts),
      if (partsPolicy != existing.partsPolicy)
        'parts_policy': partsPolicy.apiValue,
      if (noteValue != existing.partsNote) 'parts_note': noteValue,
      if (descriptionValue != existing.description)
        'description': descriptionValue,
    };
  }

  String? validateOriginal(String? v) {
    if ((v ?? '').trim().isEmpty) return null;
    final o = Validators.parseAmount(v!);
    final p = Validators.parseAmount(price.text);
    if (o == null) return 'Enter a valid amount';
    if (p != null && o < p) return 'Cannot be lower than the price';
    return null;
  }

  String? validateLabour(String? v) {
    if ((v ?? '').trim().isEmpty) return null;
    final l = Validators.parseAmount(v!);
    final p = Validators.parseAmount(price.text);
    if (l == null) return 'Enter a valid amount';
    if (p != null && l > p) return 'Cannot be more than the price';
    return null;
  }

  String? validateAdvance(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    return n == null || n < 1 || n > 100 ? 'Enter 1 to 100' : null;
  }

  String? validateWarranty(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final d = int.tryParse(t);
    return d == null || d < 1 || d > 3650 ? 'Enter 1 to 3650 days' : null;
  }

  String? validateRepeat(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final d = int.tryParse(t);
    return d == null || d < 1 || d > 3650 ? 'Enter 1 to 3650 days' : null;
  }
}

/// The form fields for a [PackageDraft]. [showName] is off in the service
/// editor, where the package takes the service's name.
class PackageFields extends StatefulWidget {
  const PackageFields({
    super.key,
    required this.draft,
    required this.busy,
    this.showName = true,
    this.showOrderAndActive = true,
  });

  final PackageDraft draft;
  final bool busy;
  final bool showName;
  final bool showOrderAndActive;

  @override
  State<PackageFields> createState() => _PackageFieldsState();
}

class _PackageFieldsState extends State<PackageFields> {
  PackageDraft get d => widget.draft;
  bool get off => widget.busy;

  @override
  Widget build(BuildContext context) {
    const number = TextInputType.numberWithOptions(decimal: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showName) ...[
          TextFormField(
            controller: d.name,
            enabled: !off,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: (v) =>
                Validators.requiredText(v, label: 'package name', max: 80),
            decoration: const InputDecoration(labelText: 'Package name'),
          ),
          fieldGap,
        ],
        TextFormField(
          controller: d.price,
          enabled: !off,
          keyboardType: number,
          textInputAction: TextInputAction.next,
          validator: Validators.price,
          decoration: const InputDecoration(
            labelText: 'Price',
            helperText: 'What the customer pays (after any discount)',
            prefixText: '₹ ',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-original'),
          controller: d.original,
          enabled: !off,
          keyboardType: number,
          validator: d.validateOriginal,
          decoration: const InputDecoration(
            labelText: 'Original price (optional)',
            helperText: 'The regular price, shown crossed out with the discount',
            prefixText: '₹ ',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-advance'),
          controller: d.advance,
          enabled: !off,
          keyboardType: number,
          validator: d.validateAdvance,
          decoration: const InputDecoration(
            labelText: 'Advance payment (optional)',
            helperText: 'Paid when booking; empty uses the garage default',
            suffixText: '%',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-labour'),
          controller: d.labour,
          enabled: !off,
          keyboardType: number,
          validator: d.validateLabour,
          decoration: const InputDecoration(
            labelText: 'Labour charge (optional)',
            helperText: 'The labour part of the price',
            prefixText: '₹ ',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: d.duration,
          enabled: !off,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          validator: Validators.optionalDuration,
          decoration: const InputDecoration(
            labelText: 'Estimated duration (optional)',
            suffixText: 'minutes',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-warranty'),
          controller: d.warranty,
          enabled: !off,
          keyboardType: TextInputType.number,
          validator: d.validateWarranty,
          decoration: const InputDecoration(
            labelText: 'Warranty (optional)',
            suffixText: 'days',
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-repeat'),
          controller: d.repeat,
          enabled: !off,
          keyboardType: TextInputType.number,
          validator: d.validateRepeat,
          decoration: const InputDecoration(
            labelText: 'Repeat interval (optional)',
            helperText: 'How often the service is worth repeating',
            suffixText: 'days',
          ),
        ),
        fieldGap,
        TextFormField(
          controller: d.description,
          enabled: !off,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          validator: (v) =>
              Validators.optionalText(v, label: 'description', max: 1000),
          decoration: const InputDecoration(labelText: 'Description (optional)'),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-inclusions'),
          controller: d.inclusions,
          enabled: !off,
          minLines: 3,
          maxLines: 8,
          textCapitalization: TextCapitalization.sentences,
          validator: (_) => d._validateList(d.inclusions, 30),
          decoration: const InputDecoration(
            labelText: 'What is included (one per line)',
            alignLabelWithHint: true,
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-parts'),
          controller: d.parts,
          enabled: !off,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          validator: (_) => d._validateList(d.parts, 30),
          decoration: const InputDecoration(
            labelText: 'Parts included (one per line)',
            alignLabelWithHint: true,
          ),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-exclusions'),
          controller: d.exclusions,
          enabled: !off,
          minLines: 2,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          validator: (_) => d._validateList(d.exclusions, 30),
          decoration: const InputDecoration(
            labelText: 'What is not included (one per line)',
            alignLabelWithHint: true,
          ),
        ),
        fieldGap,
        DropdownButtonFormField<PartsPolicy>(
          key: const ValueKey('package-parts-policy'),
          value: d.partsPolicy,
          items: const [
            DropdownMenuItem(
              value: PartsPolicy.serviceOnly,
              child: Text('Labour only (parts extra)'),
            ),
            DropdownMenuItem(
              value: PartsPolicy.partsIncluded,
              child: Text('Parts included'),
            ),
            DropdownMenuItem(
              value: PartsPolicy.partsExtra,
              child: Text('Parts charged extra'),
            ),
          ],
          onChanged: off
              ? null
              : (value) => setState(
                    () => d.partsPolicy = value ?? PartsPolicy.serviceOnly,
                  ),
          decoration: const InputDecoration(labelText: 'Spare parts'),
        ),
        fieldGap,
        TextFormField(
          key: const ValueKey('package-parts-note'),
          controller: d.partsNote,
          enabled: !off,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Parts note (optional)',
            helperText: 'Shown to the customer instead of the default text',
          ),
        ),
        if (widget.showOrderAndActive) ...[
          fieldGap,
          TextFormField(
            controller: d.order,
            enabled: !off,
            keyboardType: TextInputType.number,
            validator: Validators.displayOrder,
            decoration: const InputDecoration(
              labelText: 'Display order',
              helperText: 'Lower numbers are listed first',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Visible to customers'),
            value: d.active,
            onChanged: off ? null : (v) => setState(() => d.active = v),
          ),
        ],
      ],
    );
  }
}
