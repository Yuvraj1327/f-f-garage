import 'package:ff_garage/core/network/api_exception.dart';
import 'package:ff_garage/data/models/garage_settings.dart';
import 'package:ff_garage/data/repositories/garage_settings_repository.dart';

/// Stands in for `/admin/garage-settings`: keeps what was saved and counts the
/// calls. Set [error] to make the next call fail.
class FakeGarageSettingsRepository implements GarageSettingsRepository {
  FakeGarageSettingsRepository([GarageSettings? initial])
      : current = initial ??
            const GarageSettings(
              name: 'F&F Two Wheeler Garage',
              phone: '+919876543210',
              whatsapp: '919876543210',
              email: 'help@example.com',
              address: '12 Main Road, Pune',
              hours: 'Mon-Sat 9am-7pm',
              fromDatabase: false,
            );

  GarageSettings current;
  ApiException? error;
  int loads = 0;
  int saves = 0;

  @override
  Future<GarageSettings> load() async {
    loads++;
    if (error != null) throw error!;
    return current;
  }

  @override
  Future<GarageSettings> save({
    required String name,
    required String phone,
    required String whatsapp,
    required String email,
    required String address,
    required String hours,
  }) async {
    if (error != null) throw error!;
    saves++;
    current = GarageSettings(
      name: name,
      phone: phone,
      whatsapp: whatsapp,
      email: email,
      address: address,
      hours: hours,
      fromDatabase: true,
    );
    return current;
  }
}
