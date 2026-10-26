import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/garage_settings.dart';
import '../../../data/providers/data_providers.dart';

/// The garage details an administrator edits (loaded fresh each time).
final garageSettingsProvider = FutureProvider.autoDispose<GarageSettings>(
  (ref) => ref.watch(garageSettingsRepositoryProvider).load(),
);
