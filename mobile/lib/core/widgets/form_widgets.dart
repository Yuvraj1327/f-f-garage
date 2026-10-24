import 'package:flutter/material.dart';

import '../../features/auth/presentation/widgets/auth_widgets.dart'
    show BusyButton, MessageBanner;
import 'async_view.dart';

/// Page frame for the admin forms: scrolls (so the keyboard never hides a
/// field), shows an inline error, and has one Save button that spins while the
/// request runs.
class FormPage extends StatelessWidget {
  const FormPage({
    super.key,
    required this.title,
    required this.formKey,
    required this.busy,
    required this.onSave,
    required this.children,
    this.error,
    this.saveLabel = 'Save',
    this.actions,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final bool busy;
  final VoidCallback onSave;
  final List<Widget> children;
  final String? error;
  final String saveLabel;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: ListView(
                padding: const EdgeInsets.all(16),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  if (error != null) MessageBanner(message: error!),
                  ...children,
                  const SizedBox(height: 24),
                  BusyButton(label: saveLabel, busy: busy, onPressed: onSave),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A spacing helper between form fields.
const SizedBox fieldGap = SizedBox(height: 16);

/// A Switch that runs an async change, disables itself meanwhile and reports a
/// failure in a snack bar (the caller refreshes the data on success).
class ActiveSwitch extends StatefulWidget {
  const ActiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel = 'Active',
  });

  final bool value;
  final Future<void> Function(bool value) onChanged;
  final String semanticLabel;

  @override
  State<ActiveSwitch> createState() => _ActiveSwitchState();
}

class _ActiveSwitchState extends State<ActiveSwitch> {
  bool _busy = false;

  Future<void> _change(bool value) async {
    setState(() => _busy = true);
    try {
      await widget.onChanged(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      child: Switch(
        value: widget.value,
        onChanged: _busy ? null : _change,
      ),
    );
  }
}

/// Small label for things that are switched off.
class InactiveBadge extends StatelessWidget {
  const InactiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('Inactive', style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
