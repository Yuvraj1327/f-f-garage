import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/support_contact.dart';
import '../../../data/providers/data_providers.dart';

/// The garage's contact details, loaded from the backend each time the support
/// screen opens (so changing them needs no app release).
final supportContactProvider = FutureProvider.autoDispose<SupportContact>(
  (ref) => ref.watch(supportRepositoryProvider).contact(),
);
