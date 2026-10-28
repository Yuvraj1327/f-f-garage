import 'package:flutter/material.dart';

/// What the customer did in the pick list: chose [value], or asked to type it
/// themselves ([manual]).
class PickResult {
  const PickResult.value(String this.value) : manual = false;
  const PickResult.manual()
      : value = null,
        manual = true;

  final String? value;
  final bool manual;
}

/// A field that looks like a drop-down and opens a searchable list. The last
/// row is always "Can't find ...? Enter manually".
class OptionPickerField extends StatelessWidget {
  const OptionPickerField({
    super.key,
    required this.controller,
    required this.label,
    required this.sheetTitle,
    required this.options,
    required this.manualLabel,
    required this.onPicked,
    this.enabled = true,
    this.validator,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final String sheetTitle;
  final List<String> options;

  /// The text of the last row, e.g. "Can't find vehicle make? Enter manually".
  final String manualLabel;
  final ValueChanged<PickResult> onPicked;
  final bool enabled;
  final String? Function(String?)? validator;
  final String? helper;

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<PickResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickerSheet(
        title: sheetTitle,
        options: options,
        selected: controller.text,
        manualLabel: manualLabel,
      ),
    );
    if (result != null) onPicked(result);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      enabled: enabled,
      validator: validator,
      onTap: enabled ? () => _open(context) : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        suffixIcon: const Icon(Icons.arrow_drop_down),
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.manualLabel,
  });

  final String title;
  final List<String> options;
  final String selected;
  final String manualLabel;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final o in widget.options)
        if (q.isEmpty || o.toLowerCase().contains(q)) o,
    ];
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('picker-search'),
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nothing matches. You can enter it manually.'),
                    ),
                  for (final option in shown)
                    ListTile(
                      key: ValueKey('option-$option'),
                      title: Text(option),
                      trailing: option == widget.selected
                          ? Icon(Icons.check, color: scheme.primary)
                          : null,
                      onTap: () =>
                          Navigator.of(context).pop(PickResult.value(option)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('option-manual'),
              leading: Icon(Icons.edit_outlined, color: scheme.primary),
              title: Text(
                widget.manualLabel,
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.of(context).pop(const PickResult.manual()),
            ),
          ],
        ),
      ),
    );
  }
}
