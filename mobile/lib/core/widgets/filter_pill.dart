import 'package:flutter/material.dart';

/// A rounded filter chip: solid blue with white text when selected, white with a
/// grey outline otherwise ("All / Upcoming / Completed / Cancelled").
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: scheme.primary,
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurface,
          ),
      onSelected: (_) => onSelected(),
    );
  }
}
