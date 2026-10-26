import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/dialogs.dart';
import '../providers/auth_controller.dart';

/// Asks "Sign out?" and, on yes, ends the session (the router then returns to
/// the sign-in screen). Shared by Settings and Profile.
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await confirmAction(
    context,
    title: 'Sign out?',
    message: 'You will need to sign in again to use the app.',
    confirmLabel: 'Sign out',
  );
  if (confirmed) {
    await ref.read(authControllerProvider.notifier).signOut();
  }
}
