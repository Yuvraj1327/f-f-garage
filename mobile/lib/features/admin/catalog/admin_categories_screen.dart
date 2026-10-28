import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/enums.dart';
import '../../../data/providers/data_providers.dart';
import '../../catalog/providers/catalog_providers.dart';
import '../providers/admin_providers.dart';

/// The service categories: add, rename, switch off and drag into the order
/// customers see. Two-wheeler services only.
class AdminCategoriesScreen extends ConsumerStatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  ConsumerState<AdminCategoriesScreen> createState() =>
      _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends ConsumerState<AdminCategoriesScreen> {
  /// Shown while a reorder is being saved, so the row does not jump back.
  List<ServiceCategory>? _pending;

  void _refresh() {
    ref.invalidate(adminCategoriesProvider);
    ref.invalidate(categoriesProvider);
    refreshCatalog(ref);
  }

  Future<void> _reorder(List<ServiceCategory> items, int from, int to) async {
    final list = [...items];
    if (to > from) to -= 1;
    list.insert(to, list.removeAt(from));
    setState(() => _pending = list);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .reorderCategories([for (final c in list) c.id]);
      _refresh();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Future<void> _edit(ServiceCategory? existing) async {
    final result = await showDialog<_CategoryEdit>(
      context: context,
      builder: (_) => _CategoryDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    final repo = ref.read(catalogRepositoryProvider);
    try {
      if (existing == null) {
        await repo.createCategory(name: result.name, tab: result.tab);
      } else {
        await repo.updateCategory(existing.id, {
          if (result.name != existing.name) 'name': result.name,
          if (result.tab != existing.tab) 'tab': result.tab.apiValue,
        });
      }
      _refresh();
    } catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(adminCategoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add-category'),
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: SafeArea(
        child: AsyncView<List<ServiceCategory>>(
          value: value,
          onRetry: () => ref.invalidate(adminCategoriesProvider),
          builder: (loaded) {
            final items = _pending ?? loaded;
            if (items.isEmpty) {
              return const EmptyView(message: 'No categories yet.');
            }
            return ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: items.length,
              buildDefaultDragHandles: false,
              onReorder: (from, to) => _reorder(items, from, to),
              itemBuilder: (context, index) {
                final c = items[index];
                return ListTile(
                  key: ValueKey('category-${c.id}'),
                  title: Text(c.name),
                  subtitle: Text(
                    c.isActive ? c.tab.label : '${c.tab.label} - hidden',
                  ),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: ValueKey('category-edit-${c.id}'),
                        tooltip: 'Rename',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(c),
                      ),
                      ActiveSwitch(
                        key: ValueKey('category-active-${c.id}'),
                        value: c.isActive,
                        semanticLabel: '${c.name} visible',
                        onChanged: (on) async {
                          await ref
                              .read(catalogRepositoryProvider)
                              .updateCategory(c.id, {'is_active': on});
                          _refresh();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _CategoryEdit {
  const _CategoryEdit(this.name, this.tab);

  final String name;
  final CatalogTab tab;
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.existing});

  final ServiceCategory? existing;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late CatalogTab _tab = widget.existing?.tab ?? CatalogTab.repair;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    // Built-in categories keep their tab; the server refuses to move them.
    final tabLocked = existing?.systemKey != null;
    return AlertDialog(
      title: Text(existing == null ? 'New category' : 'Edit category'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('category-name'),
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.length < 2) return 'Enter at least 2 characters';
                return null;
              },
              decoration: const InputDecoration(labelText: 'Category name'),
            ),
            fieldGap,
            DropdownButtonFormField<CatalogTab>(
              key: const ValueKey('category-tab'),
              value: _tab,
              items: [
                for (final tab in CatalogTab.values)
                  DropdownMenuItem(value: tab, child: Text(tab.label)),
              ],
              onChanged: tabLocked
                  ? null
                  : (v) => setState(() => _tab = v ?? CatalogTab.repair),
              decoration: const InputDecoration(
                labelText: 'Shown under',
                helperText: 'Which tab of the customer screen lists it',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('category-save'),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _CategoryEdit(_name.text.trim().replaceAll(RegExp(r'\s+'), ' '), _tab),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
